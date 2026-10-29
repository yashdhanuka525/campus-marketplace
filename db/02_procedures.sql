-- =====================================================================
-- Campus Resale Marketplace -- procedures and triggers
-- Run this SECOND, after 01_schema.sql.
-- The FastAPI backend never writes raw INSERT/UPDATE for anything that
-- touches money or item status -- it only calls these procedures.
-- That way the rules (locking, checks, ledger entries) hold no matter
-- what calls them: this app, SQL Developer, or another client.
-- =====================================================================

-- ---------------------------------------------------------------------
-- create_user: makes a USERS row and its WALLETS row in one atomic
-- transaction, so a user can never exist without a wallet, and a
-- wallet can never exist without a user.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_user(
    p_reg_no       IN  VARCHAR2,
    p_full_name    IN  VARCHAR2,
    p_email        IN  VARCHAR2,
    p_phone        IN  VARCHAR2,
    p_hostel_block IN  VARCHAR2,
    p_user_id      OUT NUMBER
) AS
BEGIN
    INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
    VALUES (p_reg_no, p_full_name, p_email, p_phone, p_hostel_block)
    RETURNING user_id INTO p_user_id;

    INSERT INTO wallets (user_id, balance) VALUES (p_user_id, 0);

    COMMIT;
END create_user;
/

-- ---------------------------------------------------------------------
-- create_user_with_password: password-enabled atomic user + wallet creation.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE create_user_with_password(
    p_reg_no        IN  VARCHAR2,
    p_full_name     IN  VARCHAR2,
    p_email         IN  VARCHAR2,
    p_phone         IN  VARCHAR2,
    p_hostel_block  IN  VARCHAR2,
    p_password_hash IN  VARCHAR2,
    p_user_id       OUT NUMBER
) AS
BEGIN
    INSERT INTO users (reg_no, full_name, email, phone, hostel_block, password_hash)
    VALUES (p_reg_no, p_full_name, p_email, p_phone, p_hostel_block, p_password_hash)
    RETURNING user_id INTO p_user_id;

    INSERT INTO wallets (user_id, balance) VALUES (p_user_id, 0);

    COMMIT;
END create_user_with_password;
/

-- ---------------------------------------------------------------------
-- topup_wallet: adds money to a wallet and logs it in the ledger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE topup_wallet(
    p_user_id IN NUMBER,
    p_amount  IN NUMBER
) AS
    v_dummy NUMBER;
BEGIN
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Top-up amount must be positive');
    END IF;

    -- lock this user's wallet row so two top-ups can't race each other
    SELECT balance INTO v_dummy FROM wallets WHERE user_id = p_user_id FOR UPDATE;

    UPDATE wallets SET balance = balance + p_amount, updated_at = SYSTIMESTAMP
    WHERE user_id = p_user_id;

    INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount)
    VALUES (p_user_id, NULL, 'TOPUP', p_amount);

    COMMIT;
END topup_wallet;
/

-- ---------------------------------------------------------------------
-- reserve_item: the core escrow-hold procedure. Locks the item row
-- and the buyer's wallet row, checks both, moves the money into
-- escrow, and flips the item to RESERVED.
-- ORA-20001: item is not available any more
-- ORA-20002: buyer doesn't have enough balance
-- ORA-20003: buyer is trying to buy their own listing
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE reserve_item(
    p_item_id  IN NUMBER,
    p_buyer_id IN NUMBER,
    p_txn_id   OUT NUMBER
) AS
    v_price     items.price%TYPE;
    v_status    items.status%TYPE;
    v_seller_id items.seller_id%TYPE;
    v_balance   wallets.balance%TYPE;
BEGIN
    -- Step 1: lock the item row -- this is what stops two buyers
    -- reserving the same item at the same instant. The second
    -- transaction waits here until the first commits or rolls back.
    SELECT price, status, seller_id INTO v_price, v_status, v_seller_id
    FROM items WHERE item_id = p_item_id
    FOR UPDATE;

    IF v_status <> 'AVAILABLE' THEN
        RAISE_APPLICATION_ERROR(-20001, 'Item is no longer available');
    END IF;

    IF v_seller_id = p_buyer_id THEN
        RAISE_APPLICATION_ERROR(-20003, 'You cannot reserve your own listing');
    END IF;

    -- Step 2: lock the buyer's wallet row and check funds
    SELECT balance INTO v_balance FROM wallets WHERE user_id = p_buyer_id FOR UPDATE;

    IF v_balance < v_price THEN
        RAISE_APPLICATION_ERROR(-20002, 'Insufficient wallet balance');
    END IF;

    -- Step 3: move the money into escrow
    UPDATE wallets SET balance = balance - v_price, updated_at = SYSTIMESTAMP
    WHERE user_id = p_buyer_id;

    INSERT INTO escrow_transactions (item_id, buyer_id, amount, deadline_at)
    VALUES (p_item_id, p_buyer_id, v_price, SYSTIMESTAMP + INTERVAL '3' DAY)
    RETURNING txn_id INTO p_txn_id;

    INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount)
    VALUES (p_buyer_id, p_txn_id, 'ESCROW_HOLD', v_price);

    -- Step 4: flip the item to RESERVED
    UPDATE items SET status = 'RESERVED' WHERE item_id = p_item_id;

    COMMIT;
END reserve_item;
/

-- ---------------------------------------------------------------------
-- confirm_delivery: seller confirms the item was handed over.
-- Releases the held money to the seller and closes the transaction.
-- ORA-20004: transaction not found / not HELD any more
-- ORA-20005: caller is not the seller on this transaction
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE confirm_delivery(
    p_txn_id    IN NUMBER,
    p_seller_id IN NUMBER
) AS
    v_status  escrow_transactions.escrow_status%TYPE;
    v_amount  escrow_transactions.amount%TYPE;
    v_item_id escrow_transactions.item_id%TYPE;
    v_seller  items.seller_id%TYPE;
BEGIN
    SELECT escrow_status, amount, item_id INTO v_status, v_amount, v_item_id
    FROM escrow_transactions WHERE txn_id = p_txn_id
    FOR UPDATE;

    IF v_status <> 'HELD' THEN
        RAISE_APPLICATION_ERROR(-20004, 'This transaction is not awaiting delivery');
    END IF;

    SELECT seller_id INTO v_seller FROM items WHERE item_id = v_item_id;
    IF v_seller <> p_seller_id THEN
        RAISE_APPLICATION_ERROR(-20005, 'Only the seller can confirm delivery');
    END IF;

    UPDATE escrow_transactions
    SET escrow_status = 'RELEASED', delivered_at = SYSTIMESTAMP, closed_at = SYSTIMESTAMP
    WHERE txn_id = p_txn_id;

    UPDATE wallets SET balance = balance + v_amount, updated_at = SYSTIMESTAMP
    WHERE user_id = p_seller_id;

    INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount)
    VALUES (p_seller_id, p_txn_id, 'RELEASE', v_amount);

    UPDATE items SET status = 'SOLD' WHERE item_id = v_item_id;

    COMMIT;
END confirm_delivery;
/

-- ---------------------------------------------------------------------
-- cancel_or_refund_escrow: buyer cancels before delivery, seller
-- rejects a reservation before delivery, or this is called with no
-- actor (e.g. by expire_listings) once the deadline has passed.
-- Refunds the held money back to the buyer and reopens the listing
-- (or marks it EXPIRED if its listing expiry window has already passed).
-- ORA-20004: transaction not found / not HELD any more
-- ORA-20006: caller is neither the buyer nor the seller on this txn
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE cancel_or_refund_escrow(
    p_txn_id   IN NUMBER,
    p_actor_id IN NUMBER DEFAULT NULL
) AS
    v_status    escrow_transactions.escrow_status%TYPE;
    v_amount    escrow_transactions.amount%TYPE;
    v_buyer     escrow_transactions.buyer_id%TYPE;
    v_item_id   escrow_transactions.item_id%TYPE;
    v_seller_id items.seller_id%TYPE;
BEGIN
    SELECT escrow_status, amount, buyer_id, item_id
    INTO v_status, v_amount, v_buyer, v_item_id
    FROM escrow_transactions WHERE txn_id = p_txn_id
    FOR UPDATE;

    IF v_status <> 'HELD' THEN
        RAISE_APPLICATION_ERROR(-20004, 'This transaction is not awaiting delivery');
    END IF;

    IF p_actor_id IS NOT NULL THEN
        SELECT seller_id INTO v_seller_id FROM items WHERE item_id = v_item_id;
        IF p_actor_id NOT IN (v_buyer, v_seller_id) THEN
            RAISE_APPLICATION_ERROR(-20006, 'You are not authorized to cancel this transaction');
        END IF;
    END IF;

    UPDATE escrow_transactions
    SET escrow_status = 'REFUNDED', closed_at = SYSTIMESTAMP
    WHERE txn_id = p_txn_id;

    UPDATE wallets SET balance = balance + v_amount, updated_at = SYSTIMESTAMP
    WHERE user_id = v_buyer;

    INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount)
    VALUES (v_buyer, p_txn_id, 'REFUND', v_amount);

    UPDATE items
    SET status = CASE WHEN expires_at < SYSTIMESTAMP THEN 'EXPIRED' ELSE 'AVAILABLE' END
    WHERE item_id = v_item_id;

    COMMIT;
END cancel_or_refund_escrow;
/

-- ---------------------------------------------------------------------
-- expire_listings: flips stale AVAILABLE listings to EXPIRED, and
-- auto-refunds any HELD transaction whose deadline has passed.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE expire_listings AS
BEGIN
    UPDATE items SET status = 'EXPIRED'
    WHERE status = 'AVAILABLE' AND expires_at < SYSTIMESTAMP;

    FOR r IN (
        SELECT txn_id FROM escrow_transactions
        WHERE escrow_status = 'HELD' AND deadline_at < SYSTIMESTAMP
    ) LOOP
        cancel_or_refund_escrow(r.txn_id);
    END LOOP;

    COMMIT;
END expire_listings;
/

-- ---------------------------------------------------------------------
-- trg_update_seller_rating: after a review is inserted, verify that
-- the transaction is RELEASED (ORA-20007) and recompute the seller's
-- rating_avg / rating_count.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_update_seller_rating
AFTER INSERT ON reviews
FOR EACH ROW
DECLARE
    v_seller_id     users.user_id%TYPE;
    v_escrow_status escrow_transactions.escrow_status%TYPE;
    v_old_avg       users.rating_avg%TYPE;
    v_old_count     users.rating_count%TYPE;
BEGIN
    SELECT i.seller_id, t.escrow_status INTO v_seller_id, v_escrow_status
    FROM escrow_transactions t JOIN items i ON i.item_id = t.item_id
    WHERE t.txn_id = :NEW.txn_id;

    IF v_escrow_status <> 'RELEASED' THEN
        RAISE_APPLICATION_ERROR(-20007, 'Reviews can only be submitted for RELEASED transactions');
    END IF;

    SELECT rating_avg, rating_count INTO v_old_avg, v_old_count
    FROM users WHERE user_id = v_seller_id FOR UPDATE;

    UPDATE users
    SET rating_avg   = ROUND(((v_old_avg * v_old_count) + :NEW.rating) / (v_old_count + 1), 2),
        rating_count = v_old_count + 1
    WHERE user_id = v_seller_id;
END trg_update_seller_rating;
/

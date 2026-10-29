-- =====================================================================
-- Campus Resale Marketplace -- sample data
-- Run this THIRD, after 01_schema.sql and 02_procedures.sql.
-- (01_schema.sql already seeds the 5 categories, so this file does
-- not insert them again.)
-- =====================================================================

-- =====================================================================
-- 3. USERS  (5 rows -> user_id 1-5)
-- =====================================================================
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES ('24BCE2334', 'Yash Dhanuka',    'yash.dhanuka2024@vitstudent.ac.in',    '9876500001', 'C Block');
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES ('24BCE2105', 'Vansh Mishra',    'vansh.mishra2024@vitstudent.ac.in',    '9876500002', 'D Block');
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES ('24BCE2404', 'Antriksh Baliyan','antriksh.baliyan2024@vitstudent.ac.in','9876500003', 'C Block');
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES ('24BCE2210', 'Priya Sharma',    'priya.sharma2024@vitstudent.ac.in',    '9876500004', 'A Block');
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES ('24BCE2456', 'Rohan Gupta',     'rohan.gupta2024@vitstudent.ac.in',     '9876500005', 'B Block');

-- =====================================================================
-- 4. WALLETS  (one row per user, 1:1 with USERS)
--    Balances below are the FINAL balances after all the escrow
--    transactions and the WALLET_LEDGER entries in section 7 are
--    applied -- see the worked-out numbers in the comment above
--    each row.
-- =====================================================================
-- Yash    : topped up 5000, held+refunded 200 (item 8), released 350 in (item 1 sale) -> 5350
INSERT INTO wallets (user_id, balance) VALUES (1, 5350.00);
-- Vansh   : topped up 3000, held 350 for item 1 (released to seller, does not come back) -> 2650
INSERT INTO wallets (user_id, balance) VALUES (2, 2650.00);
-- Antriksh: topped up 4000, held 600 for item 2 (still HELD, not resolved yet) -> 3400
INSERT INTO wallets (user_id, balance) VALUES (3, 3400.00);
-- Priya   : topped up 2000, released 800 in (item 5 sale) -> 2800
INSERT INTO wallets (user_id, balance) VALUES (4, 2800.00);
-- Rohan   : topped up 1000, held 800 for item 5 (released to seller) -> 200
INSERT INTO wallets (user_id, balance) VALUES (5, 200.00);

-- =====================================================================
-- 5. ITEMS  (8 rows -> item_id 1-8)
-- =====================================================================
-- item 1: sold (txn 1, RELEASED)
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (1, 1, 'Data Structures Textbook', 'Cormen 3rd edition, some highlighting inside', 350, 'GOOD', 'SOLD',
        SYSTIMESTAMP - INTERVAL '10' DAY, SYSTIMESTAMP + INTERVAL '4' DAY);

-- item 2: reserved (txn 2, HELD)
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (1, 2, 'Casio Scientific Calculator', 'fx-991ES Plus, works fine, barely used', 600, 'LIKE_NEW', 'RESERVED',
        SYSTIMESTAMP - INTERVAL '3' DAY, SYSTIMESTAMP + INTERVAL '11' DAY);

-- item 3: available
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (2, 3, 'Hero Sprint Cycle', 'Single speed, new tyres fitted last month', 2500, 'GOOD', 'AVAILABLE',
        SYSTIMESTAMP - INTERVAL '2' DAY, SYSTIMESTAMP + INTERVAL '12' DAY);

-- item 4: expired (no transaction, expiry sweep already flipped it)
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (3, 2, 'Boat Wired Earphones', 'One earbud has a loose connection', 250, 'FAIR', 'EXPIRED',
        SYSTIMESTAMP - INTERVAL '20' DAY, SYSTIMESTAMP - INTERVAL '6' DAY);

-- item 5: sold (txn 3, RELEASED)
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (4, 4, 'Study Table', 'Wooden study table, minor scratch on one leg', 800, 'FAIR', 'SOLD',
        SYSTIMESTAMP - INTERVAL '8' DAY, SYSTIMESTAMP + INTERVAL '6' DAY);

-- item 6: available
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (4, 1, 'AI Notes Printout', 'Complete CAT-1 and CAT-2 notes, spiral bound', 100, 'NEW', 'AVAILABLE',
        SYSTIMESTAMP - INTERVAL '1' DAY, SYSTIMESTAMP + INTERVAL '13' DAY);

-- item 7: available
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (5, 5, 'Badminton Racket', 'Yonex, restrung once, good grip', 450, 'GOOD', 'AVAILABLE',
        SYSTIMESTAMP - INTERVAL '4' DAY, SYSTIMESTAMP + INTERVAL '10' DAY);

-- item 8: available again after a refund (txn 4, REFUNDED)
INSERT INTO items (seller_id, category_id, title, description, price, item_condition, status, listed_at, expires_at)
VALUES (2, 2, 'Old Laptop Charger', '65W type-C charger, tested working', 200, 'FAIR', 'AVAILABLE',
        SYSTIMESTAMP - INTERVAL '6' DAY, SYSTIMESTAMP + INTERVAL '8' DAY);

-- =====================================================================
-- 6. ESCROW_TRANSACTIONS  (4 rows -> txn_id 1-4)
--    Only ONE row is HELD (txn 2) so it doesn't collide with the
--    ux_one_held_per_item unique index.
-- =====================================================================
-- txn 1: Vansh buys item 1 (Yash's book) - completed, RELEASED
INSERT INTO escrow_transactions (item_id, buyer_id, amount, escrow_status, created_at, deadline_at, delivered_at, closed_at)
VALUES (1, 2, 350, 'RELEASED',
        SYSTIMESTAMP - INTERVAL '10' DAY, SYSTIMESTAMP - INTERVAL '7' DAY,
        SYSTIMESTAMP - INTERVAL '9' DAY, SYSTIMESTAMP - INTERVAL '9' DAY);

-- txn 2: Antriksh reserves item 2 (Yash's calculator) - still HELD, not resolved
INSERT INTO escrow_transactions (item_id, buyer_id, amount, escrow_status, created_at, deadline_at, delivered_at, closed_at)
VALUES (2, 3, 600, 'HELD',
        SYSTIMESTAMP - INTERVAL '3' DAY, SYSTIMESTAMP + INTERVAL '11' DAY,
        NULL, NULL);

-- txn 3: Rohan buys item 5 (Priya's study table) - completed, RELEASED
INSERT INTO escrow_transactions (item_id, buyer_id, amount, escrow_status, created_at, deadline_at, delivered_at, closed_at)
VALUES (5, 5, 800, 'RELEASED',
        SYSTIMESTAMP - INTERVAL '8' DAY, SYSTIMESTAMP - INTERVAL '5' DAY,
        SYSTIMESTAMP - INTERVAL '7' DAY, SYSTIMESTAMP - INTERVAL '7' DAY);

-- txn 4: Yash reserved item 8 (Vansh's charger) but cancelled - REFUNDED
INSERT INTO escrow_transactions (item_id, buyer_id, amount, escrow_status, created_at, deadline_at, delivered_at, closed_at)
VALUES (8, 1, 200, 'REFUNDED',
        SYSTIMESTAMP - INTERVAL '6' DAY, SYSTIMESTAMP - INTERVAL '3' DAY,
        NULL, SYSTIMESTAMP - INTERVAL '4' DAY);

-- =====================================================================
-- 7. WALLET_LEDGER  (12 rows -> ledger_id 1-12)
--    Every balance in section 4 is the running total of these rows.
-- =====================================================================
-- top-ups (txn_id is NULL, these are not tied to any transaction)
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (1, NULL, 'TOPUP', 5000);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (2, NULL, 'TOPUP', 3000);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (3, NULL, 'TOPUP', 4000);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (4, NULL, 'TOPUP', 2000);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (5, NULL, 'TOPUP', 1000);

-- txn 1 (item 1, 350): Vansh's money held, then released to Yash
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (2, 1, 'ESCROW_HOLD', 350);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (1, 1, 'RELEASE', 350);

-- txn 2 (item 2, 600): Antriksh's money held, still sitting in escrow
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (3, 2, 'ESCROW_HOLD', 600);

-- txn 3 (item 5, 800): Rohan's money held, then released to Priya
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (5, 3, 'ESCROW_HOLD', 800);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (4, 3, 'RELEASE', 800);

-- txn 4 (item 8, 200): Yash's money held, then refunded back to Yash
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (1, 4, 'ESCROW_HOLD', 200);
INSERT INTO wallet_ledger (user_id, txn_id, entry_type, amount) VALUES (1, 4, 'REFUND', 200);

-- =====================================================================
-- 8. REVIEWS  (2 rows -> review_id 1-2)
--    Only completed (RELEASED) transactions can be reviewed.
-- =====================================================================
INSERT INTO reviews (txn_id, rating, comments)
VALUES (1, 5, 'Book was in exactly the condition described, quick handover.');

INSERT INTO reviews (txn_id, rating, comments)
VALUES (3, 4, 'Table was fine, one leg had a small scratch not mentioned in the listing.');

COMMIT;

-- =====================================================================
-- 9. Sanity checks -- run these to confirm the seed data is consistent
-- (ratings for users 1 and 4 should already show up below, written by
--  trg_update_seller_rating the moment the two INSERT INTO reviews ran)
-- =====================================================================
-- Every wallet balance should equal the sum of its ledger entries
-- (TOPUP/RELEASE/REFUND add, ESCROW_HOLD subtracts):
SELECT w.user_id, w.balance AS wallet_balance,
       SUM(CASE WHEN l.entry_type = 'ESCROW_HOLD' THEN -l.amount ELSE l.amount END) AS ledger_total
FROM wallets w JOIN wallet_ledger l ON l.user_id = w.user_id
GROUP BY w.user_id, w.balance
ORDER BY w.user_id;

-- Only item 2 / txn 2 should show up as currently HELD:
SELECT item_id, txn_id, escrow_status FROM escrow_transactions WHERE escrow_status = 'HELD';

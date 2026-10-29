-- =====================================================================
-- Campus Resale Marketplace -- table creation
-- Run this FIRST, as your Oracle XE user/schema.
-- =====================================================================

CREATE TABLE users (
    user_id       NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reg_no        VARCHAR2(15)  NOT NULL UNIQUE,
    full_name     VARCHAR2(100) NOT NULL,
    email         VARCHAR2(120) NOT NULL UNIQUE,
    phone         VARCHAR2(15),
    hostel_block  VARCHAR2(30),
    password_hash VARCHAR2(255),
    rating_avg    NUMBER(3,2)   DEFAULT 0 NOT NULL,
    rating_count  NUMBER(6)     DEFAULT 0 NOT NULL,
    created_at    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT chk_users_rating_avg   CHECK (rating_avg BETWEEN 0 AND 5),
    CONSTRAINT chk_users_rating_count CHECK (rating_count >= 0)
);

CREATE TABLE wallets (
    user_id     NUMBER PRIMARY KEY,
    balance     NUMBER(10,2) DEFAULT 0 NOT NULL,
    updated_at  TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_wallets_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_wallet_balance CHECK (balance >= 0)
);

CREATE TABLE categories (
    category_id    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name  VARCHAR2(50) NOT NULL UNIQUE
);

CREATE TABLE items (
    item_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id       NUMBER        NOT NULL,
    category_id     NUMBER        NOT NULL,
    title           VARCHAR2(150) NOT NULL,
    description     VARCHAR2(1000),
    price           NUMBER(10,2)  NOT NULL,
    item_condition  VARCHAR2(10)  DEFAULT 'GOOD' NOT NULL,
    status          VARCHAR2(10)  DEFAULT 'AVAILABLE' NOT NULL,
    listed_at       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
    expires_at      TIMESTAMP     NOT NULL,
    CONSTRAINT fk_items_seller   FOREIGN KEY (seller_id)   REFERENCES users(user_id),
    CONSTRAINT fk_items_category FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT chk_items_price     CHECK (price > 0),
    CONSTRAINT chk_items_condition CHECK (item_condition IN ('NEW','LIKE_NEW','GOOD','FAIR')),
    CONSTRAINT chk_items_status    CHECK (status IN ('AVAILABLE','RESERVED','SOLD','EXPIRED')),
    CONSTRAINT chk_items_expiry    CHECK (expires_at > listed_at)
);

CREATE TABLE escrow_transactions (
    txn_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        NUMBER       NOT NULL,
    buyer_id       NUMBER       NOT NULL,
    amount         NUMBER(10,2) NOT NULL,
    escrow_status  VARCHAR2(10) DEFAULT 'HELD' NOT NULL,
    created_at     TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
    deadline_at    TIMESTAMP    NOT NULL,
    delivered_at   TIMESTAMP,
    closed_at      TIMESTAMP,
    CONSTRAINT fk_txn_item  FOREIGN KEY (item_id)  REFERENCES items(item_id),
    CONSTRAINT fk_txn_buyer FOREIGN KEY (buyer_id) REFERENCES users(user_id),
    CONSTRAINT chk_txn_amount CHECK (amount > 0),
    CONSTRAINT chk_txn_status CHECK (escrow_status IN ('HELD','RELEASED','REFUNDED')),
    CONSTRAINT chk_txn_closed CHECK (
        (escrow_status = 'HELD'  AND closed_at IS NULL) OR
        (escrow_status <> 'HELD' AND closed_at IS NOT NULL))
);

-- at most one HELD transaction per item at any time
CREATE UNIQUE INDEX ux_one_held_per_item
    ON escrow_transactions (CASE WHEN escrow_status = 'HELD' THEN item_id END);

CREATE TABLE wallet_ledger (
    ledger_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     NUMBER       NOT NULL,
    txn_id      NUMBER,
    entry_type  VARCHAR2(12) NOT NULL,
    amount      NUMBER(10,2) NOT NULL,
    created_at  TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_ledger_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_ledger_txn  FOREIGN KEY (txn_id)  REFERENCES escrow_transactions(txn_id),
    CONSTRAINT chk_ledger_type   CHECK (entry_type IN ('TOPUP','ESCROW_HOLD','RELEASE','REFUND')),
    CONSTRAINT chk_ledger_amount CHECK (amount > 0)
);

CREATE TABLE reviews (
    review_id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    txn_id      NUMBER NOT NULL UNIQUE,
    rating      NUMBER(1) NOT NULL,
    comments    VARCHAR2(500),
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_reviews_txn FOREIGN KEY (txn_id) REFERENCES escrow_transactions(txn_id),
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX ix_items_seller       ON items (seller_id);
CREATE INDEX ix_items_status_exp   ON items (status, expires_at);
CREATE INDEX ix_txn_buyer          ON escrow_transactions (buyer_id);
CREATE INDEX ix_txn_item           ON escrow_transactions (item_id);
CREATE INDEX ix_ledger_user        ON wallet_ledger (user_id);

INSERT INTO categories (category_name) VALUES ('Books');
INSERT INTO categories (category_name) VALUES ('Electronics');
INSERT INTO categories (category_name) VALUES ('Cycles');
INSERT INTO categories (category_name) VALUES ('Furniture');
INSERT INTO categories (category_name) VALUES ('Other');
COMMIT;

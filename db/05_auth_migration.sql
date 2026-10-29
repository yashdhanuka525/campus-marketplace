-- =====================================================================
-- Password sign-in migration.
-- Run as the same schema user used by the FastAPI app after 02_procedures.sql.
-- Safe for both a fresh install and an existing USERS table.
-- =====================================================================

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM user_tab_columns
    WHERE table_name = 'USERS' AND column_name = 'PASSWORD_HASH';

    IF v_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE users ADD (password_hash VARCHAR2(255))';
    END IF;
END;
/

-- Existing rows keep a NULL hash until their owner sets a password in
-- the app using their registration number, email, and phone.
CREATE OR REPLACE PROCEDURE create_user_with_password(
    p_reg_no       IN  VARCHAR2,
    p_full_name    IN  VARCHAR2,
    p_email        IN  VARCHAR2,
    p_phone        IN  VARCHAR2,
    p_hostel_block IN  VARCHAR2,
    p_password_hash IN VARCHAR2,
    p_user_id      OUT NUMBER
) AS
BEGIN
    INSERT INTO users (reg_no, full_name, email, phone, hostel_block, password_hash)
    VALUES (p_reg_no, p_full_name, p_email, p_phone, p_hostel_block, p_password_hash)
    RETURNING user_id INTO p_user_id;

    INSERT INTO wallets (user_id, balance) VALUES (p_user_id, 0);
    COMMIT;
END create_user_with_password;
/

# Campus Resale Marketplace

A full-stack escrow-based resale marketplace: FastAPI + python-oracledb
backend, plain HTML/CSS/JS frontend, Oracle Database for everything
(including the locking and escrow logic, which lives in PL/SQL
procedures, not in Python).

See `DATABASE_EXPLAINED.md` for how the whole system actually works
table by table and attribute by attribute.

## 1. Set up the database (do this first, in SQL Developer / SQLcl)

Connect to your Oracle 21c XE pluggable database (`XEPDB1`) as the
schema/user you'll use for this project, then run these files in order:

```
db/01_schema.sql          -- creates all tables + the 5 seed categories
db/02_procedures.sql      -- creates the escrow procedures + rating trigger
db/05_auth_migration.sql  -- adds password sign-in support (required)
db/03_sample_data.sql     -- optional: demo users, items, and transactions
```

For an existing database, run `db/05_auth_migration.sql` once as the same
schema user configured in `.env`. Older accounts can use **Set password**
once with their registration number, email, and phone.

`db/04_scheduler.sql` is optional -- it automates the expiry sweep with
`DBMS_SCHEDULER`. Skip it if your account doesn't have `CREATE JOB`.

## 2. Set up the backend (in VS Code)

Open this folder in VS Code, then in its integrated terminal:

```bash
# create and activate a virtual environment
python -m venv .venv
.venv\Scripts\activate        # Windows
source .venv/bin/activate     # macOS / Linux

# install dependencies
pip install -r requirements.txt

# copy the env template and fill in your real Oracle credentials
copy .env.example .env        # Windows
cp .env.example .env          # macOS / Linux
```

Edit `.env`:
```
ORACLE_USER=your_schema_name
ORACLE_PASSWORD=your_password
ORACLE_DSN=localhost:1521/XEPDB1
# Optional: APP_SESSION_SECRET=your_private_random_value
```

## 3. Run it

```bash
uvicorn app.main:app --reload
```

Open **http://localhost:8000** -- that's the frontend. The interactive
API docs are at **http://localhost:8000/docs** (handy for the
concurrency demo: open two browser tabs there and fire two `reserve`
calls on the same item back to back).

## 4. Try the "does it really write to Oracle" check

1. In the browser, choose **Create account**, enter your registration details,
   and set a password. Sign in with your registration number and password.
2. Switch to SQL Developer and run:
   ```sql
   SELECT * FROM users ORDER BY user_id DESC;
   SELECT * FROM wallets ORDER BY user_id DESC;
   ```
   Your new row is there in both tables -- `create_user` inserts into
   both as one atomic transaction (see `DATABASE_EXPLAINED.md`).
3. Reserve an item in the **Browse** tab, then check:
   ```sql
   SELECT * FROM escrow_transactions ORDER BY txn_id DESC;
   SELECT * FROM wallet_ledger ORDER BY ledger_id DESC;
   SELECT item_id, status FROM items WHERE item_id = <that item>;
   ```

## Project layout

```
campus-marketplace/
├── db/
│   ├── 01_schema.sql        tables + constraints + indexes
│   ├── 02_procedures.sql    PL/SQL procedures + the rating trigger
│   ├── 03_sample_data.sql   demo data (optional)
│   └── 04_scheduler.sql     DBMS_SCHEDULER job (optional)
├── app/
│   ├── main.py              FastAPI app, mounts routers + frontend
│   ├── db.py                Oracle connection pool
│   ├── errors.py            turns ORA-20xxx errors into clean HTTP errors
│   └── routers/
│       ├── users.py         signup, list users
│       ├── items.py         list/create listings, categories
│       ├── escrow.py        reserve / deliver / refund
│       ├── wallet.py        top-up, balance, ledger history
│       ├── reviews.py       leave a review
│       └── admin.py         manual expiry sweep
├── frontend/
│   ├── index.html
│   ├── style.css
│   └── app.js
├── requirements.txt
├── .env.example
└── DATABASE_EXPLAINED.md
```



Daily Startup Routine (3 Steps)
Step 1: Start Docker Container
Make sure Docker Desktop is open, then in your terminal run:

PowerShell
docker start oracle-db-fixed
Step 2: Activate Virtual Environment
Navigate to your project directory (if not already there) and activate Python:

PowerShell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned; .\venv\Scripts\Activate.ps1
Step 3: Start the Website Backend
PowerShell
uvicorn app.main:app --reload
Your website is now live at http://localhost:8000 and the API documentation is at http://localhost:8000/docs.

Command to Enter SQL*Plus (Terminal Database CLI)
Open a new terminal tab in VS Code (click the + icon so Uvicorn keeps running in the first tab) and run:

PowerShell
docker exec -it oracle-db-fixed sqlplus system/Marketplace2026@localhost:1521/XEPDB1
Note on port 1521 vs 1522: Inside the container, Oracle always listens on its internal port 1521. Windows talks to it from the outside via port 1522. When you use docker exec, you are running directly inside the container, so it connects via localhost:1521/XEPDB1.

Essential SQL Formatting Setup (Run once after entering SQL*Plus)
Paste this block into the SQL> prompt so table columns don't wrap across lines:

SQL
SET LINESIZE 220
SET PAGESIZE 100
SET SQLBLANKLINES ON
SET SERVEROUTPUT ON
SET TAB OFF
SET FEEDBACK ON

COLUMN reg_no         FORMAT A12
COLUMN full_name      FORMAT A20
COLUMN email          FORMAT A34
COLUMN phone          FORMAT A12
COLUMN hostel_block   FORMAT A12
COLUMN category_name  FORMAT A15
COLUMN title          FORMAT A28
COLUMN description    FORMAT A32 WORD_WRAPPED
COLUMN item_condition FORMAT A10
COLUMN status         FORMAT A11
COLUMN escrow_status  FORMAT A13
COLUMN entry_type     FORMAT A13
COLUMN comments       FORMAT A36 WORD_WRAPPED
COLUMN table_name     FORMAT A22
COLUMN grantee        FORMAT A16
COLUMN privilege      FORMAT A18
Quick Table Inspection Commands (Run inside SQL*Plus)
SQL
-- 1. Check all users and ratings
SELECT user_id, reg_no, full_name, hostel_block, rating_avg, rating_count FROM users ORDER BY user_id;

-- 2. Check current wallet balances
SELECT user_id, balance, TO_CHAR(updated_at, 'YYYY-MM-DD HH24:MI:SS') AS last_updated FROM wallets ORDER BY user_id;

-- 3. Check items and current status (AVAILABLE / RESERVED / SOLD / EXPIRED)
SELECT item_id, seller_id, title, price, item_condition, status FROM items ORDER BY item_id;

-- 4. Check active and completed escrow transactions
SELECT txn_id, item_id, buyer_id, amount, escrow_status, TO_CHAR(closed_at, 'YYYY-MM-DD HH24:MI') AS closed_at FROM escrow_transactions ORDER BY txn_id;

-- 5. Check the immutable money ledger (every hold, topup, release, refund)
SELECT ledger_id, user_id, txn_id, entry_type, amount FROM wallet_ledger ORDER BY ledger_id;

-- 6. Check ratings and reviews
SELECT review_id, txn_id, rating, comments FROM reviews ORDER BY review_id;

-- 7. Verification Query (Proves wallet balances match ledger sums)
SELECT w.user_id, w.balance AS wallet_balance,
       SUM(CASE WHEN l.entry_type = 'ESCROW_HOLD' THEN -l.amount ELSE l.amount END) AS ledger_total
FROM wallets w JOIN wallet_ledger l ON l.user_id = w.user_id
GROUP BY w.user_id, w.balance
ORDER BY w.user_id;
How to Shut Down Cleanly
To stop Uvicorn: Click inside the terminal running the server and press Ctrl + C.

To exit SQL*Plus: Type EXIT and press Enter.

To stop the Docker container (optional, saves battery/RAM when done):

PowerShell
docker stop oracle-db-fixed

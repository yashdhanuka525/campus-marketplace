# How this system actually works

This explains, end to end, what happens in the database every time
something happens on the website, and why every table and every
column exists. Read this alongside `db/01_schema.sql` (tables),
`db/02_procedures.sql` (the logic) and `app/routers/` (the API).

---

## 1. The one rule that explains the whole design

**The website never writes directly to money-related or
status-related columns.** Every action that touches `wallets.balance`,
`items.status`, or `escrow_transactions.escrow_status` goes through a
PL/SQL procedure in `db/02_procedures.sql`. FastAPI just collects the
HTTP request and calls the procedure with plain values — it never
builds an `UPDATE wallets SET balance = ...` itself.

This matters for one reason: **if the rule lives only in Python, it
only protects you when Python is the one touching the database.** The
moment two requests arrive at almost the same time, or someone runs a
raw `UPDATE` from SQL Developer, an app-level rule does nothing. A
rule enforced with `SELECT ... FOR UPDATE` inside the database holds
no matter what is calling it.

---

## 2. What happens when you create a user (the "will I see it in `SELECT * FROM users`" question)

Yes — immediately, because of how `create_user` is written:

```sql
INSERT INTO users (reg_no, full_name, email, phone, hostel_block)
VALUES (...) RETURNING user_id INTO p_user_id;

INSERT INTO wallets (user_id, balance) VALUES (p_user_id, 0);

COMMIT;
```

1. You fill the **New user** form and submit.
2. The browser sends a JSON body to `POST /api/users`.
3. FastAPI (`app/routers/users.py`) unpacks that JSON into plain
   Python values and calls `create_user(...)` through `python-oracledb`.
4. Oracle runs both `INSERT`s **as one transaction** and commits.
5. The moment that `COMMIT` happens, the row is permanently on disk.
   `SELECT * FROM users;` in SQL Developer shows it straight away —
   there's no caching layer or delay in between.

**Why insert into `WALLETS` in the same procedure instead of letting
the user "add a wallet later"?** Because `WALLETS.user_id` is `NOT
NULL` and references `USERS`, and the app needs a wallet to exist
before that user can ever reserve an item. Doing both inserts in one
procedure call means a user can never exist without a wallet, and a
half-created user (row in `USERS` but nothing in `WALLETS`) is
structurally impossible — not just "unlikely because the app is
careful."

---

## 3. What happens when you click Reserve (the full request path)

```
Browser click
  → JS: fetch POST /api/items/42/reserve  {buyer_id: 7}
  → FastAPI: unpacks JSON, calls reserve_item(42, 7)
  → Oracle: locks the item row, locks the wallet row, checks both,
            moves the money, flips status, commits
  → FastAPI: wraps the result as JSON
  → JS: updates the page
```

Inside Oracle, in order:

1. `SELECT price, status, seller_id FROM items WHERE item_id = 42
   FOR UPDATE;` — **locks this one row.** If another buyer clicked
   Reserve on item 42 a moment earlier and their transaction hasn't
   committed yet, this line **waits** until it does.
2. If `status <> 'AVAILABLE'` → raise an error, nothing changes. This
   is what the second buyer hits if they lost the race.
3. `SELECT balance FROM wallets WHERE user_id = 7 FOR UPDATE;` — locks
   the buyer's wallet row, checks they can afford it.
4. `UPDATE wallets SET balance = balance - 350 ...` — money leaves the
   buyer's balance.
5. `INSERT INTO escrow_transactions (...) VALUES (..., 'HELD', ...)` —
   a new row records that this money is now held, not spent.
6. `INSERT INTO wallet_ledger (...) VALUES (..., 'ESCROW_HOLD', 350)` —
   a permanent record of this specific movement.
7. `UPDATE items SET status = 'RESERVED' WHERE item_id = 42;`
8. `COMMIT;` — all six writes above become permanent together, or (if
   any step failed) none of them do.

**What "Confirm delivery" does differently:** it takes the same `HELD`
row, checks the caller is really the seller, then does the mirror
image — moves the escrowed amount from "held" into the seller's
`wallets.balance`, writes a `RELEASE` ledger row, sets
`escrow_status = 'RELEASED'`, and flips the item to `SOLD`.

**What "Cancel / refund" does:** same `HELD` row, but the money goes
back to the *buyer's* balance, a `REFUND` ledger row is written, and
the item goes back to `AVAILABLE` so someone else can reserve it.

---

## 4. "We're not storing real money — so what's the point of the wallet table?"

This is a fair question, and worth being able to answer directly in
the viva: **`WALLETS` and `WALLET_LEDGER` don't simulate a bank — they
simulate the *constraint* that a real payment system would enforce,**
which is: *money that's promised to someone can't be spent twice, and
every movement of it has to be traceable.*

Walk through what breaks if you remove the wallet tables and just let
people "reserve" an item with no balance check:

- **Nothing stops a reservation from being made with no way to pay.**
  The `FOR UPDATE` lock on `wallets.balance` in `reserve_item` is what
  turns "click reserve" into something that can actually fail
  (`ORA-20002 Insufficient wallet balance`) — without it, reserving is
  just a label, not a commitment.
- **There's nothing to refund.** The whole reason `REFUNDED` exists as
  a state is that money moved into escrow and now has to move back.
  If no balance ever moved, "refund" would be a no-op, and your
  escrow state machine (the core of this project, per your abstract)
  has no teeth.
- **There's no proof a transaction happened.** `WALLET_LEDGER` is what
  lets you run the consistency check in `db/03_sample_data.sql`
  (section 9) — summing a user's ledger entries and proving it equals
  their current balance. That query is your evidence, in the viva,
  that the system keeps money consistent under concurrent access. You
  can't demonstrate that with nothing to sum.
- **The locking demo has nothing to show.** Your whole "two sessions
  try to reserve the same item" test (see your abstract) only means
  something because a successful reserve *does* something irreversible
  — it moves a number. If reserving didn't touch a balance, both
  sessions "succeeding" would look identical to both failing.

So the honest framing for your teacher: **this project is not a
payment system, it's a database-concurrency and transaction-integrity
project, and the wallet is the mechanism that makes "integrity" a
checkable, visible thing** — an actual balance that must never go
negative (`chk_wallet_balance CHECK (balance >= 0)`), must never
silently lose money (every change has a matching ledger row), and
must never let two people spend the same rupee (`FOR UPDATE` locking).
If you plugged in a real payment gateway later, the top-up endpoint is
the only thing that would change — `reserve_item`, `confirm_delivery`
and `cancel_or_refund_escrow` would work exactly as they do now,
because they were never pretending to talk to a bank in the first
place; they only ever talked to this ledger.

---

## 5. Every table, what changes and why

### USERS
| Column | Changes when | Why it exists |
|---|---|---|
| `user_id` | Set once at signup | Primary key everything else points to |
| `reg_no` | Set once | Ties the account to a real student; `UNIQUE` stops duplicate accounts |
| `full_name` | Set at signup, editable | Shown to the other party in a trade |
| `email` | Set at signup, editable | Login identity, `UNIQUE` |
| `phone` | Set at signup, editable | Needed to actually coordinate a handover |
| `hostel_block` | Set at signup, editable | Lets buyers filter by convenience |
| `rating_avg` | **Only by `trg_update_seller_rating`**, after each review | Trust signal before a buyer reserves — the whole fix for "no reputation system" |
| `rating_count` | Same trigger, +1 each time | Without it, `rating_avg` alone is misleading (5.0 from 1 review ≠ 5.0 from 40) |
| `created_at` | Set once | Audit trail |

### WALLETS
| Column | Changes when | Why |
|---|---|---|
| `user_id` | Set once (PK = FK to USERS) | 1:1 — no separate `wallet_id` needed |
| `balance` | Every top-up (+), reserve (−), release to seller (+), refund to buyer (+) | The number the whole escrow system exists to keep correct — see §4 |
| `updated_at` | Every time `balance` changes | Lets you audit *when* it last moved |

### CATEGORIES
| Column | Changes when | Why |
|---|---|---|
| `category_id` | Set once (seed data) | PK — `ITEMS` stores a number instead of repeating "Electronics" in every row (normalization) |
| `category_name` | Rarely | `UNIQUE` so a category can't exist twice under different ids |

### ITEMS
| Column | Changes when | Why |
|---|---|---|
| `item_id` | Set once at listing | PK |
| `seller_id` | Set once | Who gets paid when this sells |
| `category_id` | Set at listing, editable pre-reservation | Powers search/filter |
| `title` / `description` | Set at listing, editable | What the buyer evaluates |
| `price` | Set at listing, editable while `AVAILABLE` | Copied into `escrow_transactions.amount` at reserve time, on purpose, so a later price edit can't retroactively change what's owed |
| `item_condition` | Set at listing | Structured buyer-decision data |
| `status` | `AVAILABLE → RESERVED` (reserve) `→ SOLD` (delivery confirmed) or back to `AVAILABLE` (refund) `→ EXPIRED` (expiry sweep) | **The core state machine of the whole project** |
| `listed_at` | Set once | Used to compute `expires_at`, sort newest-first |
| `expires_at` | Set once at listing | Lets `expire_listings` find stale posts — fixes the "seniors dump everything then vanish" seasonal problem |

### ESCROW_TRANSACTIONS
| Column | Changes when | Why |
|---|---|---|
| `txn_id` | Set once at reserve | PK |
| `item_id` / `buyer_id` | Set once | Who/what this transaction is for |
| `amount` | Set once, copied from `items.price` | The amount actually held — independent of later price edits |
| `escrow_status` | `HELD →` `RELEASED` (delivery) or `REFUNDED` (cancel/timeout) | Drives every money movement |
| `created_at` | Set once | Audit |
| `deadline_at` | Set once at reserve | `expire_listings` uses this to auto-refund if nobody confirms in time |
| `delivered_at` | Set once, on delivery confirmation | Proof the handover happened |
| `closed_at` | Set once, when status leaves `HELD` | `chk_txn_closed` uses this to keep the row internally consistent |

### WALLET_LEDGER
| Column | Changes when | Why |
|---|---|---|
| `ledger_id` | Set once per entry | PK |
| `user_id` | Set once | Whose balance this entry affected |
| `txn_id` | Set once, `NULL` for top-ups | Links a hold/release/refund back to the transaction that caused it |
| `entry_type` | Set once (`TOPUP`/`ESCROW_HOLD`/`RELEASE`/`REFUND`) | Lets you sum a user's history and prove it equals their balance — see §4 |
| `amount` | Set once | Size of that movement |
| `created_at` | Set once | Orders the history chronologically |

### REVIEWS
| Column | Changes when | Why |
|---|---|---|
| `review_id` | Set once | PK |
| `txn_id` | Set once, `UNIQUE` | One review per transaction |
| `rating` | Set once | Feeds `trg_update_seller_rating` |
| `comments` | Set once, optional | Human-readable feedback |
| `created_at` | Set once | Audit |

---

## 6. Why the logic lives in PL/SQL and not in `app/routers/*.py`

Every router function is intentionally thin — it unpacks the HTTP
request, calls one procedure, and turns the result back into JSON.
None of them contain an `IF` statement that decides whether a
reservation is allowed. That decision is made inside
`reserve_item` because:

- It must run **inside the same lock** that protects the row, or the
  check-then-act gap re-opens (see the concurrency explanation in
  `db/02_procedures.sql`'s comments).
- It must hold **no matter which client calls it** — this FastAPI app
  today, a different frontend tomorrow, or a TA running the procedure
  by hand in SQL Developer to test it.

If asked "why Python/FastAPI at all, then" — be honest: it's the
interface that lets the rules (which live entirely in Oracle) be
demonstrated from a browser instead of typing PL/SQL calls by hand.

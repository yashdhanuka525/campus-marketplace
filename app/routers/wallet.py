from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.auth import require_current_user, require_same_user
from app.db import get_connection, rows_to_dicts
from app.errors import run_db

router = APIRouter(prefix="/api/wallet", tags=["wallet"])


class TopupBody(BaseModel):
    user_id: int
    amount: float


@router.post("/topup")
def topup(body: TopupBody, current_user_id: int = Depends(require_current_user)):
    """
    This is a SIMULATED top-up -- no real payment gateway is called.
    It exists so the escrow flow has a balance to hold and release
    without wiring up actual UPI/card payments, which is out of scope
    for a DBMS course project. See DATABASE_EXPLAINED.md for the full
    reasoning on why the WALLET table still matters even though no
    real money moves through it.
    """
    require_same_user(body.user_id, current_user_id)

    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            cur.callproc("topup_wallet", [body.user_id, body.amount])
            return {"user_id": body.user_id, "topped_up": body.amount}
    return run_db(do)


@router.get("/{user_id}")
def balance_and_history(user_id: int, current_user_id: int = Depends(require_current_user)):
    require_same_user(user_id, current_user_id)
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT balance FROM wallets WHERE user_id = :id", id=user_id)
        bal = cur.fetchone()
        cur.execute("""
            SELECT ledger_id, txn_id, entry_type, amount, created_at
            FROM wallet_ledger WHERE user_id = :id
            ORDER BY created_at DESC
        """, id=user_id)
        history = rows_to_dicts(cur)
        return {"balance": bal[0] if bal else 0, "history": history}

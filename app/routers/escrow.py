from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.auth import require_current_user, require_same_user
from app.db import get_connection, rows_to_dicts
from app.errors import run_db

router = APIRouter(prefix="/api", tags=["escrow"])


class ReserveBody(BaseModel):
    buyer_id: int


@router.post("/items/{item_id}/reserve")
def reserve_item(item_id: int, body: ReserveBody, current_user_id: int = Depends(require_current_user)):
    """
    Calls reserve_item(item_id, buyer_id) -- see db/02_procedures.sql.
    This is the row-locking step: the procedure does
    `SELECT ... FROM items WHERE item_id = :id FOR UPDATE` before
    checking anything, so if two people click Reserve on the same
    item at nearly the same moment, the second call physically waits
    at that line until the first one commits, then its own status
    check fails because the item is already RESERVED.
    """
    require_same_user(body.buyer_id, current_user_id)

    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            out_txn = cur.var(int)
            cur.callproc("reserve_item", [item_id, body.buyer_id, out_txn])
            val = out_txn.getvalue()
            txn_id = val[0] if isinstance(val, (list, tuple)) else val
            return {"txn_id": int(txn_id), "status": "HELD"}
    return run_db(do)


class ActorBody(BaseModel):
    user_id: int


@router.post("/escrow/{txn_id}/deliver")
def confirm_delivery(txn_id: int, body: ActorBody, current_user_id: int = Depends(require_current_user)):
    """Seller confirms handover -> money releases to seller, item -> SOLD."""
    require_same_user(body.user_id, current_user_id)
    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            cur.callproc("confirm_delivery", [txn_id, body.user_id])
            return {"txn_id": txn_id, "status": "RELEASED"}
    return run_db(do)


@router.post("/escrow/{txn_id}/refund")
def refund(txn_id: int, body: ActorBody, current_user_id: int = Depends(require_current_user)):
    """
    Buyer cancels before delivery, OR seller rejects a reservation
    before delivery -> either way, money refunds to the buyer and the
    item goes back to AVAILABLE. body.user_id is passed through to the
    procedure, which checks it's actually the buyer or the seller on
    this transaction (ORA-20006 if not) -- without that check, anyone
    who knew a txn_id could refund a stranger's pending purchase.
    """
    require_same_user(body.user_id, current_user_id)

    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            cur.callproc("cancel_or_refund_escrow", [txn_id, body.user_id])
            return {"txn_id": txn_id, "status": "REFUNDED"}
    return run_db(do)


@router.get("/escrow/mine")
def my_transactions(user_id: int, role: str = "buyer", current_user_id: int = Depends(require_current_user)):
    require_same_user(user_id, current_user_id)
    col = "t.buyer_id" if role == "buyer" else "i.seller_id"
    # When the viewer is the buyer, show the seller's contact info;
    # when the viewer is the seller, show the buyer's contact info.
    if role == "buyer":
        counterparty_join = "LEFT JOIN users cp ON cp.user_id = i.seller_id"
    else:
        counterparty_join = "LEFT JOIN users cp ON cp.user_id = t.buyer_id"
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(f"""
            SELECT t.txn_id, t.item_id, i.title, t.amount, t.escrow_status,
                   t.created_at, t.deadline_at, t.delivered_at, t.closed_at,
                   i.seller_id, t.buyer_id, r.rating AS review_rating,
                   cp.full_name AS counterparty_name,
                   cp.phone     AS counterparty_phone,
                   cp.hostel_block AS counterparty_hostel
            FROM escrow_transactions t
            JOIN items i ON i.item_id = t.item_id
            {counterparty_join}
            LEFT JOIN reviews r ON r.txn_id = t.txn_id
            WHERE {col} = :user_id
            ORDER BY t.created_at DESC
        """, user_id=user_id)
        return rows_to_dicts(cur)

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.auth import require_current_user
from app.db import get_connection, rows_to_dicts
from app.errors import run_db

router = APIRouter(prefix="/api", tags=["reviews"])


class NewReview(BaseModel):
    txn_id: int
    rating: int = Field(ge=1, le=5)
    comments: str | None = Field(default=None, max_length=500)


@router.post("/reviews")
def add_review(body: NewReview, current_user_id: int = Depends(require_current_user)):
    """
    A plain INSERT -- all the real work happens inside Oracle in
    trg_update_seller_rating, which fires automatically right after
    this row lands and recomputes the seller's rating_avg/rating_count
    in USERS. The app never touches those two columns directly.
    """
    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT buyer_id, escrow_status FROM escrow_transactions WHERE txn_id = :txn_id",
                txn_id=body.txn_id,
            )
            row = cur.fetchone()
            if not row or int(row[0]) != current_user_id:
                raise HTTPException(status_code=403, detail="Only the buyer in this transaction can leave a review")
            if row[1] != "RELEASED":
                raise HTTPException(status_code=400, detail="Only completed (RELEASED) transactions can be reviewed")
            cur.execute("""
                INSERT INTO reviews (txn_id, rating, comments)
                VALUES (:txn_id, :rating, :comments)
            """, txn_id=body.txn_id, rating=body.rating, comments=body.comments)
            conn.commit()
            return {"txn_id": body.txn_id, "rating": body.rating}

    try:
        return run_db(do)
    except HTTPException as exc:
        if "ORA-00001" in str(exc.detail):
            raise HTTPException(status_code=409, detail="You have already submitted a review for this transaction.") from exc
        raise


@router.get("/reviews/seller/{seller_id}")
def seller_reviews(seller_id: int, _current_user_id: int = Depends(require_current_user)):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT r.review_id, r.rating, r.comments, r.created_at, i.title
            FROM reviews r
            JOIN escrow_transactions t ON t.txn_id = r.txn_id
            JOIN items i ON i.item_id = t.item_id
            WHERE i.seller_id = :id
            ORDER BY r.created_at DESC
        """, id=seller_id)
        return rows_to_dicts(cur)

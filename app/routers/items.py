from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import require_current_user, require_same_user
from app.db import get_connection, rows_to_dicts
from app.errors import run_db

router = APIRouter(prefix="/api", tags=["items"])


@router.get("/categories")
def list_categories(_current_user_id: int = Depends(require_current_user)):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT category_id, category_name FROM categories ORDER BY category_name")
        return rows_to_dicts(cur)


class NewItem(BaseModel):
    seller_id: int
    category_id: int
    title: str
    description: str | None = None
    price: float
    item_condition: str = "GOOD"
    days_valid: int = 14


@router.post("/items")
def create_item(body: NewItem, current_user_id: int = Depends(require_current_user)):
    """
    A plain INSERT is enough here -- no money moves and no other row
    needs to change, so there's nothing to protect with a procedure.
    The CHECK constraints on ITEMS (price > 0, valid condition/status,
    expires_at > listed_at) are what actually guard this insert.
    """
    if body.price <= 0:
        raise HTTPException(status_code=400, detail="Price must be positive")
    require_same_user(body.seller_id, current_user_id)

    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            out_id = cur.var(int)
            cur.execute("""
                INSERT INTO items (seller_id, category_id, title, description,
                                    price, item_condition, expires_at)
                VALUES (:seller_id, :category_id, :title, :description,
                        :price, :item_condition, SYSTIMESTAMP + :days_valid)
                RETURNING item_id INTO :out_id
            """, seller_id=body.seller_id, category_id=body.category_id, title=body.title,
                 description=body.description, price=body.price,
                 item_condition=body.item_condition, days_valid=body.days_valid, out_id=out_id)
            conn.commit()
            val = out_id.getvalue()
            item_id = val[0] if isinstance(val, (list, tuple)) else val
            return {"item_id": int(item_id)}
    return run_db(do)


@router.get("/items")
def list_items(status: str = "AVAILABLE", category_id: int | None = None, _current_user_id: int = Depends(require_current_user)):
    with get_connection() as conn:
        cur = conn.cursor()
        sql = """
            SELECT i.item_id, i.title, i.description, i.price, i.item_condition,
                   i.status, i.listed_at, i.expires_at,
                   c.category_name, u.user_id AS seller_id, u.full_name AS seller_name,
                   u.rating_avg AS seller_rating,
                   u.phone AS seller_phone, u.hostel_block AS seller_hostel
            FROM items i
            JOIN categories c ON c.category_id = i.category_id
            JOIN users u ON u.user_id = i.seller_id
            WHERE i.status = :status
        """
        params = {"status": status}
        if category_id is not None:
            sql += " AND i.category_id = :category_id"
            params["category_id"] = category_id
        sql += " ORDER BY i.listed_at DESC"
        cur.execute(sql, params)
        return rows_to_dicts(cur)


@router.get("/items/mine")
def my_items(seller_id: int, current_user_id: int = Depends(require_current_user)):
    require_same_user(seller_id, current_user_id)
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT item_id, title, price, status, listed_at, expires_at
            FROM items WHERE seller_id = :id ORDER BY listed_at DESC
        """, id=seller_id)
        return rows_to_dicts(cur)


@router.get("/items/{item_id}")
def get_item(item_id: int, _current_user_id: int = Depends(require_current_user)):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT i.item_id, i.title, i.description, i.price, i.item_condition,
                   i.status, i.listed_at, i.expires_at,
                   c.category_name, u.user_id AS seller_id, u.full_name AS seller_name,
                   u.rating_avg AS seller_rating,
                   u.phone AS seller_phone, u.hostel_block AS seller_hostel
            FROM items i
            JOIN categories c ON c.category_id = i.category_id
            JOIN users u ON u.user_id = i.seller_id
            WHERE i.item_id = :id
        """, id=item_id)
        rows = rows_to_dicts(cur)
        if not rows:
            raise HTTPException(status_code=404, detail="Item not found")
        return rows[0]

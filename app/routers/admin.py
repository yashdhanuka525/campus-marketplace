from fastapi import APIRouter, Depends

from app.auth import require_current_user
from app.db import get_connection
from app.errors import run_db

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.post("/expire-listings")
def expire_listings(_current_user_id: int = Depends(require_current_user)):
    """
    Calls the expire_listings procedure by hand, for demo purposes.
    In a real deployment this would be wired to DBMS_SCHEDULER to run
    every hour -- see db/04_scheduler.sql for that (optional, needs
    CREATE JOB privilege, which student XE accounts don't always have).
    """
    def do():
        with get_connection() as conn:
            cur = conn.cursor()
            cur.callproc("expire_listings", [])
            return {"ran": True}
    return run_db(do)

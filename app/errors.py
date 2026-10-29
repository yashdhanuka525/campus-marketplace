"""
Every custom ORA-20xxx error raised by our PL/SQL procedures (see
db/02_procedures.sql) is turned into a clean HTTP 400 with the message
the procedure wrote, instead of a raw 500 stack trace.
"""
import oracledb
from fastapi import HTTPException


def run_db(fn):
    """Call fn(); turn an application-raised ORA-20xxx error into HTTP 400."""
    try:
        return fn()
    except oracledb.DatabaseError as e:
        (error,) = e.args
        message = getattr(error, "message", str(error))
        code = getattr(error, "code", None)
        if code is not None and 20000 <= code <= 20999:
            # our own RAISE_APPLICATION_ERROR(-200xx, '...') -- a normal,
            # expected business-rule rejection (item gone, low balance...)
            raise HTTPException(status_code=400, detail=message)
        # anything else is a real bug / unexpected DB error
        raise HTTPException(status_code=500, detail=message)

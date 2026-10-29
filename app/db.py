"""
Oracle connection pool.

Everything the app does to the database goes through get_connection(),
which hands out a pooled connection and always returns it to the pool
afterwards -- the app never opens a fresh connection per request.
"""
import os
import oracledb
from contextlib import contextmanager
from dotenv import load_dotenv

load_dotenv()

ORACLE_USER = os.getenv("ORACLE_USER", "campus_marketplace")
ORACLE_PASSWORD = os.getenv("ORACLE_PASSWORD", "")
ORACLE_DSN = os.getenv("ORACLE_DSN", "localhost:1521/XEPDB1")

# python-oracledb's default "Thin" mode talks to Oracle directly over
# the network -- no Oracle Instant Client install needed.
pool = oracledb.create_pool(
    user=ORACLE_USER,
    password=ORACLE_PASSWORD,
    dsn=ORACLE_DSN,
    min=2,
    max=10,
    increment=1,
)


@contextmanager
def get_connection():
    conn = pool.acquire()
    try:
        yield conn
    finally:
        pool.release(conn)


def rows_to_dicts(cursor):
    cols = [c[0].lower() for c in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]

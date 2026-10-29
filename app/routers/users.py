"""Password-based signup and sign-in; no public account directory."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.auth import create_session_token, hash_password, require_current_user, verify_password
from app.db import get_connection
from app.errors import run_db

router = APIRouter(prefix="/api/auth", tags=["auth"])


class Credentials(BaseModel):
    reg_no: str = Field(min_length=1, max_length=15)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("reg_no")
    @classmethod
    def normalize_reg_no(cls, value: str) -> str:
        return value.strip()


class Signup(Credentials):
    full_name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=120)
    phone: str = Field(min_length=1, max_length=15)
    hostel_block: str = Field(min_length=1, max_length=30)

    @field_validator("full_name", "email", "phone", "hostel_block")
    @classmethod
    def trim_required_values(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value

    @field_validator("email")
    @classmethod
    def email_looks_valid(cls, value: str) -> str:
        if "@" not in value or "." not in value.split("@")[-1]:
            raise ValueError("Enter a valid email address")
        return value


class ExistingAccountPassword(BaseModel):
    """One-time password setup for users created before password login."""
    reg_no: str = Field(min_length=1, max_length=15)
    email: str = Field(min_length=3, max_length=120)
    phone: str = Field(min_length=1, max_length=15)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("reg_no", "email", "phone")
    @classmethod
    def trim_required_values(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field is required")
        return value


def _session(user_id: int, full_name: str) -> dict:
    return {
        "access_token": create_session_token(user_id),
        "token_type": "bearer",
        "user_id": int(user_id),
        "full_name": full_name,
    }


def _run_signup(fn):
    try:
        return run_db(fn)
    except HTTPException as exc:
        if "ORA-00001" in str(exc.detail):
            raise HTTPException(
                status_code=409,
                detail="That registration number or email is already in use.",
            ) from exc
        raise


@router.post("/signup")
def signup(body: Signup):
    password_hash = hash_password(body.password)

    def create():
        with get_connection() as conn:
            cur = conn.cursor()
            out_id = cur.var(int)
            cur.callproc(
                "create_user_with_password",
                [body.reg_no, body.full_name, body.email, body.phone,
                 body.hostel_block, password_hash, out_id],
            )
            val = out_id.getvalue()
            user_id = val[0] if isinstance(val, (list, tuple)) else val
            return int(user_id)

    user_id = _run_signup(create)
    return _session(user_id, body.full_name)


@router.post("/login")
def login(body: Credentials):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT user_id, full_name, password_hash FROM users WHERE reg_no = :reg_no",
            reg_no=body.reg_no,
        )
        row = cur.fetchone()
    # Keep the same response for an unknown registration and a wrong password.
    if not row or not verify_password(body.password, row[2]):
        raise HTTPException(status_code=401, detail="Registration number or password is incorrect")
    return _session(row[0], row[1])


@router.post("/set-password")
def set_password(body: ExistingAccountPassword):
    """Let a pre-auth account claim password login by matching its stored details."""
    password_hash = hash_password(body.password)
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            """SELECT user_id, full_name FROM users
               WHERE reg_no = :reg_no AND LOWER(email) = LOWER(:email)
                 AND phone = :phone AND password_hash IS NULL""",
            reg_no=body.reg_no, email=body.email, phone=body.phone,
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(
                status_code=404,
                detail="Could not verify this account. Check the registration number, email, and phone, or sign in if a password is already set.",
            )
        cur.execute(
            "UPDATE users SET password_hash = :password_hash WHERE user_id = :user_id AND password_hash IS NULL",
            password_hash=password_hash, user_id=row[0],
        )
        if cur.rowcount != 1:
            conn.rollback()
            raise HTTPException(status_code=409, detail="A password was just set for this account. Sign in instead.")
        conn.commit()
    return _session(row[0], row[1])


@router.get("/me")
def current_account(user_id: int = Depends(require_current_user)):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT user_id, full_name FROM users WHERE user_id = :id", id=user_id)
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="Account no longer exists")
    return {"user_id": int(row[0]), "full_name": row[1]}

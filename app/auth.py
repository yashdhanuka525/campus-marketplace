"""Small signed sessions for the classroom marketplace."""
import base64
import hashlib
import hmac
import json
import os
import secrets
import time

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from dotenv import load_dotenv

load_dotenv()

_secret = os.getenv("APP_SESSION_SECRET") or secrets.token_urlsafe(48)
_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    derived = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return "scrypt$16384$8$1${}${}".format(
        base64.urlsafe_b64encode(salt).decode("ascii").rstrip("="),
        base64.urlsafe_b64encode(derived).decode("ascii").rstrip("="),
    )


def verify_password(password: str, stored: str | None) -> bool:
    if not stored:
        return False
    try:
        scheme, n, r, p, salt_text, digest_text = stored.split("$")
        if scheme != "scrypt":
            return False
        salt = base64.urlsafe_b64decode(salt_text + "=" * (-len(salt_text) % 4))
        expected = base64.urlsafe_b64decode(digest_text + "=" * (-len(digest_text) % 4))
        actual = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=int(n), r=int(r), p=int(p), dklen=len(expected))
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def create_session_token(user_id: int) -> str:
    payload = json.dumps({"sub": int(user_id), "exp": int(time.time()) + 60 * 60 * 12}, separators=(",", ":")).encode()
    encoded = base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")
    signature = hmac.new(_secret.encode(), encoded.encode("ascii"), hashlib.sha256).digest()
    return encoded + "." + base64.urlsafe_b64encode(signature).decode("ascii").rstrip("=")


def require_current_user(credentials: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> int:
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Sign in to continue")
    try:
        encoded, signed = credentials.credentials.split(".", 1)
        expected = hmac.new(_secret.encode(), encoded.encode("ascii"), hashlib.sha256).digest()
        signature = base64.urlsafe_b64decode(signed + "=" * (-len(signed) % 4))
        if not hmac.compare_digest(expected, signature):
            raise ValueError("bad signature")
        payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
        user_id = int(payload["sub"])
        if int(payload["exp"]) < int(time.time()):
            raise ValueError("expired")
        return user_id
    except (ValueError, TypeError, KeyError, json.JSONDecodeError):
        raise HTTPException(status_code=401, detail="Session expired. Sign in again.")


def require_same_user(requested_user_id: int, authenticated_user_id: int) -> None:
    if int(requested_user_id) != int(authenticated_user_id):
        raise HTTPException(status_code=403, detail="You can only act as the signed-in account")

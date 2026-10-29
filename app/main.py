from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.routers import users, items, escrow, wallet, reviews, admin

app = FastAPI(title="Campus Resale Marketplace")

# Local dev only -- lets the frontend call the API even if it's ever
# served from a different port while testing.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(users.router)
app.include_router(items.router)
app.include_router(escrow.router)
app.include_router(wallet.router)
app.include_router(reviews.router)
app.include_router(admin.router)

# Serves frontend/index.html at "/" and the rest of frontend/ alongside
# it. This is mounted LAST so the /api/... routes above take priority.
app.mount("/", StaticFiles(directory="frontend", html=True), name="frontend")

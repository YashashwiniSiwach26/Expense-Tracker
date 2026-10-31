"""Automated API tests. Requires PostgreSQL with schema.sql loaded.
Run from project root:  pip install pytest   then   pytest -q
"""
import uuid
import pytest
from app import app


@pytest.fixture()
def client():
    app.config["TESTING"] = True
    return app.test_client()


def login(c, email="demo@example.com", pw="Demo@123"):
    return c.post("/api/login", json={"email": email, "password": pw})


def test_login_and_protection(client):
    assert client.get("/api/summary").status_code == 401
    assert login(client, pw="wrong").status_code == 401
    assert login(client).status_code == 200
    assert client.get("/api/summary").status_code == 200


def test_register_validation(client):
    r = client.post("/api/register", json={"full_name": "T", "email": "bad", "password": "x"})
    assert r.status_code == 400
    email = f"{uuid.uuid4().hex[:8]}@test.com"
    ok = client.post("/api/register", json={"full_name": "Test User", "email": email, "password": "Test@1234"})
    assert ok.status_code == 201
    dup = client.post("/api/register", json={"full_name": "Test User", "email": email, "password": "Test@1234"})
    assert dup.status_code == 409


def test_expense_crud_and_validation(client):
    login(client)
    bad = client.post("/api/transactions", json={"type": "expense", "category_id": 1, "amount": "-5", "txn_date": "2026-01-01"})
    assert bad.status_code == 400
    r = client.post("/api/transactions", json={"type": "expense", "category_id": 1, "amount": "99.50",
                                              "txn_date": "2026-01-01", "description": "pytest"})
    assert r.status_code == 201
    tid = r.get_json()["id"]
    assert client.put(f"/api/transactions/{tid}", json={"category_id": 2, "amount": "120", "txn_date": "2026-01-02"}).status_code == 200
    assert client.put(f"/api/transactions/{tid}", json={"category_id": 9, "amount": "120", "txn_date": "2026-01-02"}).status_code == 400
    assert client.delete(f"/api/transactions/{tid}").status_code == 200
    assert client.delete(f"/api/transactions/{tid}").status_code == 404


def test_user_isolation(client):
    login(client)
    rows = client.get("/api/transactions?type=expense").get_json()
    victim = rows[0]["transaction_id"]
    other = app.test_client()
    login(other, "second@example.com")
    assert other.delete(f"/api/transactions/{victim}").status_code == 404
    assert other.put(f"/api/transactions/{victim}", json={"category_id": 1, "amount": "1", "txn_date": "2026-01-01"}).status_code == 404
    ids = [r["transaction_id"] for r in other.get("/api/transactions?type=expense").get_json()]
    assert victim not in ids


def test_budget_rules(client):
    login(client)
    assert client.post("/api/budgets", json={"category_id": 9, "amount_limit": "500", "month": "2030-01"}).status_code == 400
    assert client.post("/api/budgets", json={"category_id": 1, "amount_limit": "0", "month": "2030-01"}).status_code == 400
    assert client.post("/api/budgets", json={"category_id": 1, "amount_limit": "500", "month": "2030-01"}).status_code in (201, 409)
    assert client.post("/api/budgets", json={"category_id": 1, "amount_limit": "500", "month": "2030-01"}).status_code == 409


def test_reports(client):
    login(client)
    for p, v in (("daily", "2026-10"), ("monthly", "2026"), ("yearly", "")):
        r = client.get(f"/api/reports?period={p}&value={v}")
        assert r.status_code == 200 and "rows" in r.get_json()
    assert client.get("/api/reports?period=bad").status_code == 400

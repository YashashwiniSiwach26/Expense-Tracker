"""Database helper: one PostgreSQL connection per request (psycopg2)."""
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import g
from config import DB_CONFIG


def get_db():
    if "db" not in g:
        g.db = psycopg2.connect(cursor_factory=RealDictCursor, **DB_CONFIG)
    return g.db


def close_db(exc=None):
    db = g.pop("db", None)
    if db is not None and not db.closed:
        db.close()


def fetch_all(sql, params=()):
    with get_db().cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def fetch_one(sql, params=()):
    rows = fetch_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=(), commit=True):
    """Run INSERT/UPDATE/DELETE with parameters.
    Returns (row, rowcount); `row` holds the RETURNING values if the SQL has a RETURNING clause."""
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(sql, params)
            row = cur.fetchone() if cur.description else None
            rowcount = cur.rowcount
        if commit:
            db.commit()
        return row, rowcount
    except Exception:
        db.rollback()
        raise

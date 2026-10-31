"""Personal Expense & Budget Tracker - Flask backend.

Every SQL statement is parameterised (%s placeholders) and every query that touches
Transactions / Budgets / AuditLog is filtered by the logged-in user's id.
"""
import re
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from functools import wraps

import psycopg2
from flask import (Flask, jsonify, redirect, render_template, request,
                   session, url_for)
from flask.json.provider import DefaultJSONProvider
from werkzeug.security import check_password_hash, generate_password_hash

import config
from db import close_db, execute, fetch_all, fetch_one, get_db


# ---------------------------------------------------------------- app setup
class AppJSONProvider(DefaultJSONProvider):
    @staticmethod
    def default(o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, (date, datetime)):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


app = Flask(__name__)
app.secret_key = config.SECRET_KEY
app.json = AppJSONProvider(app)
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")
app.teardown_appcontext(close_db)

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
MAX_AMOUNT = Decimal("9999999999.99")


# ---------------------------------------------------------------- helpers
class ValidationError(Exception):
    pass


def parse_amount(value):
    try:
        amount = Decimal(str(value).strip())
    except (InvalidOperation, AttributeError):
        raise ValidationError("Amount must be a valid number")
    if not amount.is_finite():
        raise ValidationError("Amount must be a valid number")
    if amount <= 0:
        raise ValidationError("Amount must be greater than zero")
    if amount > MAX_AMOUNT:
        raise ValidationError("Amount is too large")
    if amount.as_tuple().exponent < -2:
        raise ValidationError("Amount can have at most 2 decimal places")
    return amount


def parse_date(value, field="Date"):
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date()
    except ValueError:
        raise ValidationError(f"{field} must be in YYYY-MM-DD format")


def parse_month(value):
    """'2026-10' -> date(2026, 10, 1); defaults to current month."""
    if not value:
        return date.today().replace(day=1)
    try:
        return datetime.strptime(str(value), "%Y-%m").date().replace(day=1)
    except ValueError:
        raise ValidationError("Month must be in YYYY-MM format")


def next_month(d):
    return date(d.year + (d.month == 12), d.month % 12 + 1, 1)


def prev_month(d):
    return date(d.year - (d.month == 1), 12 if d.month == 1 else d.month - 1, 1)


def clean_text(value, max_len):
    text = (value or "").strip()
    if len(text) > max_len:
        raise ValidationError(f"Text must be at most {max_len} characters")
    return text or None


def get_category(category_id, expected_type):
    """Return the category row only if it exists and has the expected type."""
    try:
        cid = int(category_id)
    except (TypeError, ValueError):
        raise ValidationError("Please choose a category")
    cat = fetch_one("SELECT category_id, name, type FROM Categories WHERE category_id = %s", (cid,))
    if not cat or cat["type"] != expected_type:
        raise ValidationError(f"Invalid {expected_type} category")
    return cat


def api_login_required(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        if "user_id" not in session:
            return jsonify(error="Please log in first"), 401
        return fn(*a, **kw)
    return wrapper


def page_login_required(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        if "user_id" not in session:
            return redirect(url_for("login_page"))
        return fn(*a, **kw)
    return wrapper


@app.before_request
def require_json_for_writes():
    # State-changing API calls must be JSON; a cross-site HTML form cannot send that (CSRF defence).
    if request.path.startswith("/api/") and request.method in ("POST", "PUT", "DELETE"):
        if request.method != "DELETE" and not request.is_json:
            return jsonify(error="Content-Type must be application/json"), 415


@app.errorhandler(ValidationError)
def handle_validation(e):
    return jsonify(error=str(e)), 400


@app.errorhandler(psycopg2.Error)
def handle_db_error(e):
    code = getattr(e, "pgcode", None)
    if code == "23505":                               # unique_violation
        return jsonify(error="That record already exists"), 409
    if code == "P0001":                               # RAISE EXCEPTION in our trigger functions
        return jsonify(error=e.diag.message_primary), 400
    if code in ("23514", "23503", "22003", "22007"):  # check / foreign key / numeric / date errors
        return jsonify(error="The database rejected this value"), 400
    app.logger.exception("Database error")
    return jsonify(error="Database error. Please try again."), 500


# ---------------------------------------------------------------- pages
@app.route("/")
def index():
    return redirect(url_for("dashboard_page" if "user_id" in session else "login_page"))


@app.route("/login")
def login_page():
    return render_template("login.html")


@app.route("/register")
def register_page():
    return render_template("register.html")


@app.route("/dashboard")
@page_login_required
def dashboard_page():
    return render_template("dashboard.html", page="dashboard", title="Dashboard")


@app.route("/income")
@page_login_required
def income_page():
    return render_template("transactions.html", page="income", kind="income", title="Income")


@app.route("/expenses")
@page_login_required
def expenses_page():
    return render_template("transactions.html", page="expenses", kind="expense", title="Expenses")


@app.route("/budgets")
@page_login_required
def budgets_page():
    return render_template("budgets.html", page="budgets", title="Budgets")


@app.route("/reports")
@page_login_required
def reports_page():
    return render_template("reports.html", page="reports", title="Reports")


# ---------------------------------------------------------------- authentication
@app.route("/api/register", methods=["POST"])
def api_register():
    d = request.get_json(silent=True) or {}
    name = (d.get("full_name") or "").strip()
    email = (d.get("email") or "").strip().lower()
    password = d.get("password") or ""
    if not 2 <= len(name) <= 100:
        raise ValidationError("Name must be 2-100 characters")
    if not EMAIL_RE.match(email) or len(email) > 120:
        raise ValidationError("Enter a valid email address")
    if len(password) < 8 or not re.search(r"[A-Za-z]", password) or not re.search(r"\d", password):
        raise ValidationError("Password must be at least 8 characters with a letter and a number")
    if fetch_one("SELECT user_id FROM Users WHERE email = %s", (email,)):
        return jsonify(error="An account with this email already exists"), 409
    execute("INSERT INTO Users (full_name, email, password_hash) VALUES (%s, %s, %s)",
            (name, email, generate_password_hash(password)))
    return jsonify(message="Account created. You can log in now."), 201


@app.route("/api/login", methods=["POST"])
def api_login():
    d = request.get_json(silent=True) or {}
    email = (d.get("email") or "").strip().lower()
    user = fetch_one("SELECT user_id, full_name, password_hash FROM Users WHERE email = %s", (email,))
    if not user or not check_password_hash(user["password_hash"], d.get("password") or ""):
        return jsonify(error="Invalid email or password"), 401
    session.clear()
    session["user_id"] = user["user_id"]
    session["full_name"] = user["full_name"]
    return jsonify(message="Welcome back!", redirect=url_for("dashboard_page"))


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login_page"))


@app.route("/api/me")
@api_login_required
def api_me():
    return jsonify(user_id=session["user_id"], full_name=session["full_name"])


# ---------------------------------------------------------------- categories
@app.route("/api/categories")
@api_login_required
def api_categories():
    ctype = request.args.get("type")
    if ctype in ("income", "expense"):
        return jsonify(fetch_all("SELECT category_id, name, type FROM Categories WHERE type = %s ORDER BY name", (ctype,)))
    return jsonify(fetch_all("SELECT category_id, name, type FROM Categories ORDER BY type, name"))


# ---------------------------------------------------------------- transactions (income + expense)
@app.route("/api/transactions")
@api_login_required
def api_transactions_list():
    ttype = request.args.get("type")
    if ttype not in ("income", "expense"):
        raise ValidationError("type must be income or expense")
    sql = ("SELECT t.transaction_id, t.category_id, c.name AS category, t.amount, t.txn_date, t.description "
           "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
           "WHERE t.user_id = %s AND c.type = %s")
    params = [session["user_id"], ttype]
    if request.args.get("from"):
        sql += " AND t.txn_date >= %s"
        params.append(parse_date(request.args["from"], "From date"))
    if request.args.get("to"):
        sql += " AND t.txn_date <= %s"
        params.append(parse_date(request.args["to"], "To date"))
    if request.args.get("category_id"):
        sql += " AND t.category_id = %s"
        params.append(int(request.args["category_id"]) if request.args["category_id"].isdigit() else 0)
    if request.args.get("min"):
        sql += " AND t.amount >= %s"
        params.append(parse_amount(request.args["min"]))
    if request.args.get("max"):
        sql += " AND t.amount <= %s"
        params.append(parse_amount(request.args["max"]))
    sql += " ORDER BY t.txn_date DESC, t.transaction_id DESC"
    return jsonify(fetch_all(sql, params))


def read_txn_payload(ttype):
    d = request.get_json(silent=True) or {}
    amount = parse_amount(d.get("amount"))
    txn_date = parse_date(d.get("txn_date"))
    desc = clean_text(d.get("description"), 255)
    cat = get_category(d.get("category_id"), ttype)
    return cat["category_id"], amount, txn_date, desc


@app.route("/api/transactions", methods=["POST"])
@api_login_required
def api_transactions_create():
    ttype = (request.get_json(silent=True) or {}).get("type")
    if ttype not in ("income", "expense"):
        raise ValidationError("type must be income or expense")
    cid, amount, txn_date, desc = read_txn_payload(ttype)
    row, _ = execute(
        "INSERT INTO Transactions (user_id, category_id, amount, txn_date, description) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING transaction_id",
        (session["user_id"], cid, amount, txn_date, desc))
    return jsonify(message="Record added", id=row["transaction_id"]), 201


def owned_txn(txn_id):
    """Fetch a transaction only if it belongs to the logged-in user (with its type)."""
    return fetch_one(
        "SELECT t.transaction_id, c.type FROM Transactions t "
        "JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.transaction_id = %s AND t.user_id = %s", (txn_id, session["user_id"]))


@app.route("/api/transactions/<int:txn_id>", methods=["PUT"])
@api_login_required
def api_transactions_update(txn_id):
    existing = owned_txn(txn_id)
    if not existing:
        return jsonify(error="Record not found"), 404
    cid, amount, txn_date, desc = read_txn_payload(existing["type"])
    execute("UPDATE Transactions SET category_id=%s, amount=%s, txn_date=%s, description=%s "
            "WHERE transaction_id=%s AND user_id=%s",
            (cid, amount, txn_date, desc, txn_id, session["user_id"]))
    return jsonify(message="Record updated")


@app.route("/api/transactions/<int:txn_id>", methods=["DELETE"])
@api_login_required
def api_transactions_delete(txn_id):
    _, rows = execute("DELETE FROM Transactions WHERE transaction_id=%s AND user_id=%s",
                      (txn_id, session["user_id"]))
    if rows == 0:
        return jsonify(error="Record not found"), 404
    return jsonify(message="Record deleted")


# ---------------------------------------------------------------- budgets
def budget_rows(uid, month):
    rows = fetch_all(
        "SELECT budget_id, category_id, category, amount_limit, spent "
        "FROM v_budget_status WHERE user_id = %s AND ym = %s ORDER BY category",
        (uid, month.strftime("%Y-%m")))
    for r in rows:
        limit, spent = float(r["amount_limit"]), float(r["spent"])
        r["percent"] = round(spent / limit * 100, 1)
        r["remaining"] = round(limit - spent, 2)
        r["status"] = ("exceeded" if spent > limit else "reached" if spent == limit
                       else "near" if spent >= 0.8 * limit else "ok")
    return rows


@app.route("/api/budgets")
@api_login_required
def api_budgets_list():
    return jsonify(budget_rows(session["user_id"], parse_month(request.args.get("month"))))


@app.route("/api/budgets", methods=["POST"])
@api_login_required
def api_budgets_create():
    d = request.get_json(silent=True) or {}
    cat = get_category(d.get("category_id"), "expense")
    month = parse_month(d.get("month"))
    amount = parse_amount(d.get("amount_limit"))
    execute("INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit) VALUES (%s,%s,%s,%s)",
            (session["user_id"], cat["category_id"], month, amount))
    return jsonify(message="Budget saved"), 201


@app.route("/api/budgets/<int:budget_id>", methods=["PUT"])
@api_login_required
def api_budgets_update(budget_id):
    amount = parse_amount((request.get_json(silent=True) or {}).get("amount_limit"))
    if not fetch_one("SELECT budget_id FROM Budgets WHERE budget_id=%s AND user_id=%s",
                     (budget_id, session["user_id"])):
        return jsonify(error="Budget not found"), 404
    execute("UPDATE Budgets SET amount_limit=%s WHERE budget_id=%s AND user_id=%s",
            (amount, budget_id, session["user_id"]))
    return jsonify(message="Budget updated")


@app.route("/api/budgets/<int:budget_id>", methods=["DELETE"])
@api_login_required
def api_budgets_delete(budget_id):
    _, rows = execute("DELETE FROM Budgets WHERE budget_id=%s AND user_id=%s",
                      (budget_id, session["user_id"]))
    if rows == 0:
        return jsonify(error="Budget not found"), 404
    return jsonify(message="Budget deleted")


@app.route("/api/budgets/copy", methods=["POST"])
@api_login_required
def api_budgets_copy():
    """Copy last month's budgets into the target month - one atomic transaction."""
    month = parse_month((request.get_json(silent=True) or {}).get("month"))
    uid, prev = session["user_id"], prev_month(month)
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit) "
            "SELECT user_id, category_id, %s, amount_limit FROM Budgets "
            "WHERE user_id = %s AND budget_month = %s "
            "AND category_id NOT IN (SELECT category_id FROM Budgets WHERE user_id = %s AND budget_month = %s)",
            (month, uid, prev, uid, month))
        copied = cur.rowcount
        db.commit()                       # all rows are saved together ...
    except Exception:
        db.rollback()                     # ... or none of them are
        raise
    finally:
        cur.close()
    return jsonify(message=f"Copied {copied} budget(s) from {prev:%B %Y}", copied=copied)


# ---------------------------------------------------------------- dashboard
@app.route("/api/summary")
@api_login_required
def api_summary():
    uid = session["user_id"]
    month = parse_month(request.args.get("month"))
    ym = month.strftime("%Y-%m")
    totals = fetch_one(
        "SELECT COALESCE(SUM(CASE WHEN c.type='income'  THEN t.amount END), 0) AS income, "
        "       COALESCE(SUM(CASE WHEN c.type='expense' THEN t.amount END), 0) AS expense "
        "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s", (uid,))
    this_month = fetch_one(
        "SELECT total_income AS income, total_expense AS expense FROM v_monthly_summary "
        "WHERE user_id = %s AND ym = %s", (uid, ym)) or {"income": 0, "expense": 0}
    by_category = fetch_all(
        "SELECT c.name AS category, SUM(t.amount) AS total FROM Transactions t "
        "JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s AND c.type = 'expense' AND t.txn_date >= %s AND t.txn_date < %s "
        "GROUP BY c.category_id, c.name ORDER BY total DESC", (uid, month, next_month(month)))
    trend = fetch_all(
        "SELECT ym, total_income, total_expense FROM v_monthly_summary "
        "WHERE user_id = %s ORDER BY ym DESC LIMIT 12", (uid,))[::-1]
    recent = fetch_all(
        "SELECT t.transaction_id, c.name AS category, c.type, t.amount, t.txn_date, t.description "
        "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s ORDER BY t.txn_date DESC, t.transaction_id DESC LIMIT 5", (uid,))
    alerts = [b for b in budget_rows(uid, month) if b["status"] != "ok"]
    return jsonify(month=ym, total_income=totals["income"], total_expense=totals["expense"],
                   balance=float(totals["income"]) - float(totals["expense"]),
                   month_income=this_month["income"], month_expense=this_month["expense"],
                   by_category=by_category, trend=trend, recent=recent, alerts=alerts)


# ---------------------------------------------------------------- reports
@app.route("/api/reports")
@api_login_required
def api_reports():
    uid = session["user_id"]
    period = request.args.get("period", "monthly")
    value = request.args.get("value", "")
    if period == "daily":                       # value = YYYY-MM -> one row per day
        start = parse_month(value)
        end = next_month(start)
        label = "t.txn_date"
    elif period == "monthly":                   # value = YYYY -> one row per month
        year = int(value) if value.isdigit() and 1900 <= int(value) <= 9998 else date.today().year
        start, end = date(year, 1, 1), date(year + 1, 1, 1)
        label = "to_char(t.txn_date, 'YYYY-MM')"
    elif period == "yearly":                    # all years
        start, end = date(1900, 1, 1), date(9999, 12, 31)
        label = "EXTRACT(YEAR FROM t.txn_date)::int"
    else:
        raise ValidationError("period must be daily, monthly or yearly")

    # `label` is chosen from the three constant strings above, never from user input.
    rows = fetch_all(
        f"SELECT {label} AS label, "
        "SUM(CASE WHEN c.type='income'  THEN t.amount ELSE 0 END) AS income, "
        "SUM(CASE WHEN c.type='expense' THEN t.amount ELSE 0 END) AS expense, "
        "COUNT(*) AS txn_count "
        "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s AND t.txn_date >= %s AND t.txn_date < %s "
        f"GROUP BY {label} ORDER BY {label}", (uid, start, end))
    top = fetch_all(
        "SELECT c.name AS category, SUM(t.amount) AS total, COUNT(*) AS txn_count "
        "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s AND c.type = 'expense' AND t.txn_date >= %s AND t.txn_date < %s "
        "GROUP BY c.category_id, c.name HAVING SUM(t.amount) > 0 "
        "ORDER BY total DESC LIMIT 5", (uid, start, end))
    big = fetch_all(
        "SELECT t.txn_date, c.name AS category, t.amount, t.description "
        "FROM Transactions t JOIN Categories c ON c.category_id = t.category_id "
        "WHERE t.user_id = %s AND c.type = 'expense' AND t.txn_date >= %s AND t.txn_date < %s "
        "AND t.amount > (SELECT AVG(t2.amount) FROM Transactions t2 "
        "                JOIN Categories c2 ON c2.category_id = t2.category_id "
        "                WHERE t2.user_id = %s AND c2.type = 'expense' "
        "                AND t2.txn_date >= %s AND t2.txn_date < %s) "
        "ORDER BY t.amount DESC LIMIT 5", (uid, start, end, uid, start, end))
    audit = fetch_all(
        "SELECT action, transaction_id, old_amount, new_amount, logged_at FROM AuditLog "
        "WHERE user_id = %s ORDER BY log_id DESC LIMIT 10", (uid,))
    return jsonify(rows=rows, top_categories=top, above_average=big, audit=audit,
                   highest_category=top[0] if top else None)


if __name__ == "__main__":
    app.run(debug=True)

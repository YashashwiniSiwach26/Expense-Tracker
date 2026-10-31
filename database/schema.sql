-- =====================================================================
--  Personal Expense & Budget Tracker  |  PostgreSQL 12+
--
--  1) Create an empty database once:   createdb -U postgres expense_tracker
--  2) Load this file:                  psql -U postgres -d expense_tracker -f database/schema.sql
--  (Re-running the file wipes and rebuilds all project tables.)
-- =====================================================================
DROP VIEW  IF EXISTS v_budget_status, v_monthly_summary;
DROP TABLE IF EXISTS AuditLog, Budgets, Transactions, Categories, Users CASCADE;
DROP FUNCTION  IF EXISTS fn_txn_validate(), fn_budget_validate(), fn_txn_audit(), fn_user_normalise(),
                         fn_month_spent(INT, INT, DATE), fn_budget_status(NUMERIC, NUMERIC),
                         fn_user_balance(INT), fn_budget_alerts(INT, DATE);
DROP PROCEDURE IF EXISTS sp_add_transaction(INT, INT, NUMERIC, DATE, VARCHAR), sp_copy_budgets(INT, DATE, DATE);

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------
CREATE TABLE Users (
    user_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- type tells whether a category is an expense category or an income source
CREATE TABLE Categories (
    category_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(50) NOT NULL UNIQUE,
    type           VARCHAR(10) NOT NULL CHECK (type IN ('income', 'expense'))
);

-- one user -> many transactions ; one category -> many transactions
-- (income / expense is NOT stored here; it is derived from Categories.type -> 3NF)
CREATE TABLE Transactions (
    transaction_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        INT NOT NULL,
    category_id    INT NOT NULL,
    amount         NUMERIC(12,2) NOT NULL,
    txn_date       DATE NOT NULL,
    description    VARCHAR(255),
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_txn_amount CHECK (amount > 0),
    CONSTRAINT fk_txn_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_txn_category FOREIGN KEY (category_id)
        REFERENCES Categories(category_id) ON DELETE RESTRICT
);

-- one budget per user + expense category + month
CREATE TABLE Budgets (
    budget_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        INT NOT NULL,
    category_id    INT NOT NULL,
    budget_month   DATE NOT NULL,                 -- always the 1st day of the month
    amount_limit   NUMERIC(12,2) NOT NULL,
    CONSTRAINT chk_budget_amount CHECK (amount_limit > 0),
    CONSTRAINT uq_budget UNIQUE (user_id, category_id, budget_month),
    CONSTRAINT fk_budget_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_budget_category FOREIGN KEY (category_id)
        REFERENCES Categories(category_id) ON DELETE RESTRICT
);

-- Audit table filled automatically by a trigger (supporting table, not one of the 4 core tables).
-- It has no foreign key on purpose: audit history must survive even if a user is deleted.
CREATE TABLE AuditLog (
    log_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        INT NOT NULL,
    transaction_id INT NOT NULL,
    action         VARCHAR(10) NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_amount     NUMERIC(12,2),
    new_amount     NUMERIC(12,2),
    logged_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 2. INDEXES (columns used in WHERE / JOIN / GROUP BY most often)
-- ---------------------------------------------------------------------
CREATE INDEX idx_txn_user_date ON Transactions (user_id, txn_date);
CREATE INDEX idx_txn_user_cat  ON Transactions (user_id, category_id);
CREATE INDEX idx_txn_amount    ON Transactions (amount);
CREATE INDEX idx_budget_month  ON Budgets (user_id, budget_month);
CREATE INDEX idx_audit_user    ON AuditLog (user_id, logged_at);

-- ---------------------------------------------------------------------
-- 3. VIEWS
-- ---------------------------------------------------------------------
-- Monthly income / expense summary for every user
CREATE VIEW v_monthly_summary AS
SELECT t.user_id,
       to_char(t.txn_date, 'YYYY-MM')                                AS ym,
       SUM(CASE WHEN c.type = 'income'  THEN t.amount ELSE 0 END)    AS total_income,
       SUM(CASE WHEN c.type = 'expense' THEN t.amount ELSE 0 END)    AS total_expense,
       COUNT(*)                                                      AS txn_count
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
GROUP BY t.user_id, to_char(t.txn_date, 'YYYY-MM');

-- Budget versus actual spending (uses a correlated subquery)
CREATE VIEW v_budget_status AS
SELECT b.budget_id, b.user_id, b.category_id, c.name AS category,
       to_char(b.budget_month, 'YYYY-MM') AS ym,
       b.amount_limit,
       (SELECT COALESCE(SUM(t.amount), 0)
          FROM Transactions t
         WHERE t.user_id = b.user_id
           AND t.category_id = b.category_id
           AND t.txn_date >= b.budget_month
           AND t.txn_date <  b.budget_month + INTERVAL '1 month') AS spent
FROM Budgets b
JOIN Categories c ON c.category_id = b.category_id;

-- ---------------------------------------------------------------------
-- 4. TRIGGERS (PL/pgSQL: a trigger function + a CREATE TRIGGER statement)
-- ---------------------------------------------------------------------
-- Validation: reject non-positive amounts
CREATE FUNCTION fn_txn_validate() RETURNS trigger AS $$
BEGIN
    IF NEW.amount <= 0 THEN
        RAISE EXCEPTION 'Transaction amount must be greater than zero';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_validate
BEFORE INSERT OR UPDATE ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_txn_validate();

-- Validation: budgets are only allowed for expense categories; normalise month to day 1
CREATE FUNCTION fn_budget_validate() RETURNS trigger AS $$
DECLARE
    v_type VARCHAR(10);
BEGIN
    SELECT type INTO v_type FROM Categories WHERE category_id = NEW.category_id;
    IF v_type IS DISTINCT FROM 'expense' THEN
        RAISE EXCEPTION 'Budgets can only be set for expense categories';
    END IF;
    NEW.budget_month := date_trunc('month', NEW.budget_month)::date;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_budget_validate
BEFORE INSERT OR UPDATE ON Budgets
FOR EACH ROW EXECUTE FUNCTION fn_budget_validate();

-- Auditing: every INSERT / UPDATE / DELETE on Transactions is logged
CREATE FUNCTION fn_txn_audit() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO AuditLog (user_id, transaction_id, action, old_amount, new_amount)
        VALUES (NEW.user_id, NEW.transaction_id, 'INSERT', NULL, NEW.amount);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO AuditLog (user_id, transaction_id, action, old_amount, new_amount)
        VALUES (NEW.user_id, NEW.transaction_id, 'UPDATE', OLD.amount, NEW.amount);
        RETURN NEW;
    ELSE
        INSERT INTO AuditLog (user_id, transaction_id, action, old_amount, new_amount)
        VALUES (OLD.user_id, OLD.transaction_id, 'DELETE', OLD.amount, NULL);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_txn_audit
AFTER INSERT OR UPDATE OR DELETE ON Transactions
FOR EACH ROW EXECUTE FUNCTION fn_txn_audit();

-- Normalisation: e-mail is stored trimmed and in lower case, names are trimmed
CREATE FUNCTION fn_user_normalise() RETURNS trigger AS $$
BEGIN
    NEW.email     := lower(trim(NEW.email));
    NEW.full_name := trim(NEW.full_name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_normalise
BEFORE INSERT OR UPDATE ON Users
FOR EACH ROW EXECUTE FUNCTION fn_user_normalise();

-- ---------------------------------------------------------------------
-- 5. STORED FUNCTIONS, PROCEDURES AND CURSORS (PL/pgSQL)
-- ---------------------------------------------------------------------
-- Stored function: total spent by a user in one category during one month
CREATE FUNCTION fn_month_spent(p_user INT, p_category INT, p_month DATE) RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM Transactions
    WHERE user_id = p_user
      AND category_id = p_category
      AND txn_date >= date_trunc('month', p_month)::date
      AND txn_date <  (date_trunc('month', p_month) + INTERVAL '1 month')::date;
    RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;

-- Stored function with IF / ELSIF: budget status text
CREATE FUNCTION fn_budget_status(p_spent NUMERIC, p_limit NUMERIC) RETURNS TEXT AS $$
BEGIN
    IF p_spent > p_limit THEN
        RETURN 'EXCEEDED';
    ELSIF p_spent = p_limit THEN
        RETURN 'REACHED';
    ELSIF p_spent >= 0.8 * p_limit THEN
        RETURN 'NEAR LIMIT';
    ELSE
        RETURN 'OK';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Stored function written in plain SQL: balance = total income - total expenses
CREATE FUNCTION fn_user_balance(p_user INT) RETURNS NUMERIC AS $$
    SELECT COALESCE(SUM(CASE WHEN c.type = 'income' THEN t.amount ELSE -t.amount END), 0)
    FROM Transactions t
    JOIN Categories c ON c.category_id = t.category_id
    WHERE t.user_id = p_user;
$$ LANGUAGE sql STABLE;

-- Stored procedure: validated insert of a transaction
CREATE PROCEDURE sp_add_transaction(p_user INT, p_category INT, p_amount NUMERIC,
                                    p_date DATE, p_desc VARCHAR DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_type VARCHAR(10);
BEGIN
    SELECT type INTO v_type FROM Categories WHERE category_id = p_category;
    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Category % does not exist', p_category;
    END IF;
    INSERT INTO Transactions (user_id, category_id, amount, txn_date, description)
    VALUES (p_user, p_category, p_amount, p_date, p_desc);
    RAISE NOTICE 'Added % of Rs. % on %', v_type, p_amount, p_date;
END;
$$;

-- Stored procedure: copy the budgets of one month to another month
CREATE PROCEDURE sp_copy_budgets(p_user INT, p_from DATE, p_to DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT;
BEGIN
    INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit)
    SELECT b.user_id, b.category_id, date_trunc('month', p_to)::date, b.amount_limit
    FROM Budgets b
    WHERE b.user_id = p_user AND b.budget_month = date_trunc('month', p_from)::date
    ON CONFLICT (user_id, category_id, budget_month) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '% budget(s) copied', v_rows;
END;
$$;

-- Function with an explicit CURSOR: lists budgets that are near, reached or exceeded
CREATE FUNCTION fn_budget_alerts(p_user INT, p_month DATE)
RETURNS TABLE (category_name VARCHAR, budget_limit NUMERIC, spent NUMERIC, status TEXT) AS $$
DECLARE
    cur CURSOR FOR
        SELECT c.name AS cname, b.amount_limit AS lim, b.category_id AS cid
        FROM Budgets b
        JOIN Categories c ON c.category_id = b.category_id
        WHERE b.user_id = p_user AND b.budget_month = date_trunc('month', p_month)::date
        ORDER BY c.name;
    rec RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        category_name := rec.cname;
        budget_limit  := rec.lim;
        spent         := fn_month_spent(p_user, rec.cid, p_month);
        status        := fn_budget_status(spent, rec.lim);
        IF status <> 'OK' THEN
            RETURN NEXT;
        END IF;
    END LOOP;
    CLOSE cur;
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------------------------------------------------------------------
-- 6. SAMPLE DATA   (demo login:  demo@example.com / Demo@123)
-- ---------------------------------------------------------------------
INSERT INTO Categories (name, type) VALUES
 ('Food','expense'),('Travel','expense'),('Education','expense'),('Shopping','expense'),
 ('Bills','expense'),('Entertainment','expense'),('Health','expense'),('Other Expense','expense'),
 ('Salary','income'),('Pocket Money','income'),('Scholarship','income'),('Other Income','income');

INSERT INTO Users (full_name, email, password_hash) VALUES
 ('Demo Student', 'demo@example.com',
  'pbkdf2:sha256:1000000$Dp0JCS3IJojqFMj1$4545b8cba42d2de9f3fc2e89ce00f47639e6191745d92db10f6e7aa200404ab5'),
 ('Second User', 'second@example.com',
  'pbkdf2:sha256:1000000$Dp0JCS3IJojqFMj1$4545b8cba42d2de9f3fc2e89ce00f47639e6191745d92db10f6e7aa200404ab5');

-- Dates are relative to today so the dashboard always has current data.
-- Category ids: 1 Food, 2 Travel, 3 Education, 4 Shopping, 5 Bills, 6 Entertainment,
--               7 Health, 8 Other Expense, 9 Salary, 10 Pocket Money, 11 Scholarship
INSERT INTO Transactions (user_id, category_id, amount, txn_date, description) VALUES
 -- income
 (1, 10, 8000.00,  date_trunc('month', CURRENT_DATE)::date, 'Monthly pocket money'),
 (1, 9,  6000.00,  (date_trunc('month', CURRENT_DATE) + INTERVAL '2 days')::date, 'Part-time job'),
 (1, 10, 8000.00,  (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date, 'Monthly pocket money'),
 (1, 11, 15000.00, (date_trunc('month', CURRENT_DATE) - INTERVAL '2 months')::date, 'Merit scholarship'),
 (1, 10, 8000.00,  (date_trunc('month', CURRENT_DATE) - INTERVAL '2 months')::date, 'Monthly pocket money'),
 -- expenses, this month
 (1, 1, 450.00,  CURRENT_DATE,     'Canteen lunch'),
 (1, 1, 1200.00, CURRENT_DATE - 1, 'Groceries'),
 (1, 2, 600.00,  CURRENT_DATE - 2, 'Bus pass'),
 (1, 3, 2500.00, CURRENT_DATE - 3, 'Reference books'),
 (1, 4, 1800.00, CURRENT_DATE - 4, 'Shoes'),
 (1, 5, 999.00,  CURRENT_DATE - 5, 'Mobile recharge'),
 (1, 6, 350.00,  CURRENT_DATE - 6, 'Movie'),
 (1, 7, 500.00,  CURRENT_DATE - 7, 'Pharmacy'),
 -- expenses, earlier months
 (1, 1, 3200.00, (CURRENT_DATE - INTERVAL '1 month')::date,  'Food for the month'),
 (1, 2, 900.00,  (CURRENT_DATE - INTERVAL '1 month')::date,  'Train tickets'),
 (1, 3, 4000.00, (CURRENT_DATE - INTERVAL '1 month')::date,  'Exam fees'),
 (1, 5, 1500.00, (CURRENT_DATE - INTERVAL '1 month')::date,  'Internet bill'),
 (1, 4, 2200.00, (CURRENT_DATE - INTERVAL '2 months')::date, 'Clothes'),
 (1, 1, 2900.00, (CURRENT_DATE - INTERVAL '2 months')::date, 'Food for the month'),
 (1, 6, 800.00,  (CURRENT_DATE - INTERVAL '2 months')::date, 'Concert'),
 -- second user (proves data isolation)
 (2, 9, 30000.00, CURRENT_DATE, 'Salary'),
 (2, 1, 700.00,   CURRENT_DATE, 'Dinner');

INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit) VALUES
 (1, 1, CURRENT_DATE, 3000.00),
 (1, 2, CURRENT_DATE, 1000.00),
 (1, 3, CURRENT_DATE, 2500.00),
 (1, 4, CURRENT_DATE, 1500.00),
 (1, 5, CURRENT_DATE, 1500.00),
 (1, 6, CURRENT_DATE, 1000.00),
 (2, 1, CURRENT_DATE, 5000.00);

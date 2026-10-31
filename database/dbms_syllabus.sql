-- =====================================================================
--  DBMS syllabus coverage on the Expense Tracker database  |  PostgreSQL 12+
--
--  1. DDL and DML              4. Operators and group functions
--  2. Constraints              5. Subqueries, views and joins
--  3. Single row functions     6. Procedures, functions, cursors and triggers
--
--  Run (after schema.sql):   psql -U postgres -d expense_tracker -f database/dbms_syllabus.sql
--  * Statements marked "DELIBERATE FAILURE" are meant to be rejected; psql prints the
--    error and continues.
--  * Practice tables (demo_*) and practice views are created and dropped inside this
--    file, so the project data is left unchanged. Demo user = user_id 1.
-- =====================================================================


-- #####################################################################
-- 1. DATA DEFINITION LANGUAGE (DDL) AND DATA MANIPULATION LANGUAGE (DML)
-- #####################################################################

-- S1.1. CREATE TABLE
-- Concept: DDL - CREATE TABLE with data types, PRIMARY KEY, FOREIGN KEY and DEFAULT
-- Result: Creates the practice table demo_goal for savings goals.
DROP TABLE IF EXISTS demo_goal CASCADE;
CREATE TABLE demo_goal (
    goal_id       SERIAL PRIMARY KEY,
    user_id       INT NOT NULL REFERENCES Users(user_id) ON DELETE CASCADE,
    title         VARCHAR(60) NOT NULL,
    target_amount NUMERIC(10,2) NOT NULL,
    saved_amount  NUMERIC(10,2) DEFAULT 0
);

-- S1.2. ALTER TABLE - add a column
-- Concept: DDL - ALTER TABLE ... ADD COLUMN
-- Result: demo_goal gets a new nullable column due_date.
ALTER TABLE demo_goal ADD COLUMN due_date DATE;

-- S1.3. ALTER TABLE - change type, rename column, set default
-- Concept: DDL - ALTER COLUMN TYPE, RENAME COLUMN, SET DEFAULT
-- Result: title becomes VARCHAR(100), saved_amount is renamed saved_so_far and due_date defaults to 90 days from today.
ALTER TABLE demo_goal ALTER COLUMN title TYPE VARCHAR(100);
ALTER TABLE demo_goal RENAME COLUMN saved_amount TO saved_so_far;
ALTER TABLE demo_goal ALTER COLUMN due_date SET DEFAULT CURRENT_DATE + 90;

-- S1.4. INSERT - single row and multiple rows
-- Concept: DML - INSERT ... VALUES (column list, DEFAULT values, multi-row insert)
-- Result: Three rows are added; due_date and saved_so_far take their defaults.
INSERT INTO demo_goal (user_id, title, target_amount) VALUES (1, 'Emergency fund', 20000);
INSERT INTO demo_goal (user_id, title, target_amount, saved_so_far) VALUES
    (1, 'Trip', 5000, 1500),
    (1, 'New laptop', 60000, 12000);

-- S1.5. INSERT ... SELECT
-- Concept: DML - inserting rows produced by a query
-- Result: One goal is created for every budget of user 2 (title built with the || operator).
INSERT INTO demo_goal (user_id, title, target_amount)
SELECT b.user_id, 'Stay under ' || c.name || ' budget', b.amount_limit
FROM Budgets b
JOIN Categories c ON c.category_id = b.category_id
WHERE b.user_id = 2;

-- S1.6. UPDATE
-- Concept: DML - UPDATE with WHERE, and UPDATE using a subquery
-- Result: 25% of the target is marked as saved for user 2; the Emergency fund target is set from the largest budget of user 2.
UPDATE demo_goal SET saved_so_far = target_amount * 0.25 WHERE user_id = 2;
UPDATE demo_goal
SET target_amount = (SELECT MAX(amount_limit) FROM Budgets WHERE user_id = 2)
WHERE title LIKE 'Emergency%';

-- S1.7. DELETE and UPSERT
-- Concept: DML - DELETE with WHERE; INSERT ... ON CONFLICT DO NOTHING
-- Result: The Trip goal is removed; re-inserting the existing category Food is silently skipped.
DELETE FROM demo_goal WHERE title = 'Trip';
INSERT INTO Categories (name, type) VALUES ('Food', 'expense') ON CONFLICT (name) DO NOTHING;

-- S1.8. SELECT - view the practice data
-- Concept: DML - SELECT (projection, selection, ordering)
-- Result: Remaining goals with the percentage saved.
SELECT goal_id, user_id, title, target_amount, saved_so_far,
       ROUND(saved_so_far * 100 / target_amount, 1) AS percent_saved
FROM demo_goal
ORDER BY user_id, goal_id;

-- S1.9. ALTER TABLE - drop a column
-- Concept: DDL - ALTER TABLE ... DROP COLUMN
-- Result: due_date no longer exists in demo_goal.
ALTER TABLE demo_goal DROP COLUMN due_date;

-- S1.10. Transaction control: COMMIT, ROLLBACK and SAVEPOINT
-- Concept: TCL - BEGIN, SAVEPOINT, ROLLBACK TO, COMMIT
-- Result: The UPDATE is kept but the DELETE is undone, so the final count equals the number of goals before the DELETE.
BEGIN;
UPDATE demo_goal SET target_amount = target_amount * 2;
SAVEPOINT before_delete;
DELETE FROM demo_goal;
ROLLBACK TO SAVEPOINT before_delete;
COMMIT;
SELECT COUNT(*) AS goals_after_rollback FROM demo_goal;

-- S1.11. TRUNCATE
-- Concept: DDL - TRUNCATE removes all rows quickly and resets the identity counter
-- Result: demo_goal is empty afterwards (count 0).
TRUNCATE TABLE demo_goal RESTART IDENTITY;
SELECT COUNT(*) AS goals_after_truncate FROM demo_goal;

-- S1.12. GRANT and REVOKE
-- Concept: DCL - privileges for a role
-- Result: A read-only role is created, given SELECT on two tables and the privileges are withdrawn again.
DROP ROLE IF EXISTS report_reader;
CREATE ROLE report_reader NOLOGIN;
GRANT SELECT ON Transactions, Categories TO report_reader;
REVOKE SELECT ON Transactions FROM report_reader;
REVOKE ALL ON Categories FROM report_reader;
DROP ROLE report_reader;

-- S1.13. DROP TABLE
-- Concept: DDL - DROP TABLE removes the structure and data
-- Result: demo_goal is deleted; the project tables are untouched.
DROP TABLE demo_goal;


-- #####################################################################
-- 2. CONSTRAINTS
-- #####################################################################

-- S2.1. Table with every kind of constraint
-- Concept: PRIMARY KEY, NOT NULL, UNIQUE, CHECK, DEFAULT, FOREIGN KEY, named constraint
-- Result: Creates the practice table demo_wallet.
DROP TABLE IF EXISTS demo_wallet;
CREATE TABLE demo_wallet (
    wallet_id   INT PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES Users(user_id),
    wallet_name VARCHAR(40) NOT NULL,
    card_no     CHAR(4) UNIQUE,
    balance     NUMERIC(10,2) DEFAULT 0 CHECK (balance >= 0),
    kind        VARCHAR(10) DEFAULT 'cash' CONSTRAINT chk_wallet_kind CHECK (kind IN ('cash', 'bank', 'card'))
);

-- S2.2. A valid row
-- Concept: DEFAULT constraint
-- Result: The row is inserted and kind is filled with its default value cash.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name, card_no, balance)
VALUES (1, 1, 'Pocket', '1234', 500);
SELECT * FROM demo_wallet;

-- S2.3. PRIMARY KEY violation (DELIBERATE FAILURE)
-- Concept: PRIMARY KEY
-- Result: Fails with a duplicate key error because wallet_id 1 already exists.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name) VALUES (1, 1, 'Duplicate id');

-- S2.4. NOT NULL violation (DELIBERATE FAILURE)
-- Concept: NOT NULL
-- Result: Fails because wallet_name cannot be NULL.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name) VALUES (3, 1, NULL);

-- S2.5. UNIQUE violation (DELIBERATE FAILURE)
-- Concept: UNIQUE
-- Result: Fails because card number 1234 is already used by wallet 1.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name, card_no) VALUES (4, 1, 'Same card', '1234');

-- S2.6. CHECK violations (DELIBERATE FAILURE)
-- Concept: CHECK
-- Result: Both statements fail: a negative balance, and a kind that is not cash, bank or card.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name, balance) VALUES (5, 1, 'Negative', -5);
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name, kind) VALUES (6, 1, 'Wrong kind', 'crypto');

-- S2.7. FOREIGN KEY violation (DELIBERATE FAILURE)
-- Concept: FOREIGN KEY (referential integrity)
-- Result: Fails because user 999 does not exist in Users.
INSERT INTO demo_wallet (wallet_id, user_id, wallet_name) VALUES (7, 999, 'No such user');

-- S2.8. Adding and dropping a constraint
-- Concept: ALTER TABLE ... ADD CONSTRAINT / DROP CONSTRAINT
-- Result: A CHECK on the name length is added, then removed again.
ALTER TABLE demo_wallet ADD CONSTRAINT chk_wallet_name_len CHECK (length(wallet_name) >= 3);
ALTER TABLE demo_wallet DROP CONSTRAINT chk_wallet_name_len;

-- S2.9. ON DELETE CASCADE
-- Concept: Foreign key action CASCADE (Transactions.user_id -> Users)
-- Result: Deleting user 2 also deletes that user's transactions; ROLLBACK restores everything.
BEGIN;
DELETE FROM Users WHERE user_id = 2;
SELECT COUNT(*) AS transactions_left_for_user2 FROM Transactions WHERE user_id = 2;
ROLLBACK;

-- S2.10. List the constraints of the project tables
-- Concept: Data dictionary (pg_constraint)
-- Result: Every primary key, foreign key, unique and check constraint of the four core tables.
SELECT conrelid::regclass AS table_name, conname AS constraint_name,
       CASE contype WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
                    WHEN 'u' THEN 'UNIQUE'      WHEN 'c' THEN 'CHECK' END AS constraint_type
FROM pg_constraint
WHERE conrelid IN ('users'::regclass, 'categories'::regclass, 'transactions'::regclass, 'budgets'::regclass)
ORDER BY 1, 3, 2;

-- S2.11. Clean up
-- Concept: DROP TABLE
-- Result: demo_wallet is removed.
DROP TABLE demo_wallet;


-- #####################################################################
-- 3. SINGLE ROW FUNCTIONS
-- #####################################################################

-- S3.1. Character functions (case and length)
-- Concept: UPPER, LOWER, INITCAP, LENGTH
-- Result: One row per user showing the name in upper case, the e-mail in lower case, a title-cased text and the name length.
SELECT full_name, UPPER(full_name) AS upper_name, LOWER(email) AS lower_email,
       INITCAP('monthly pocket money') AS title_case, LENGTH(full_name) AS name_length
FROM Users;

-- S3.2. Character functions (extract and replace)
-- Concept: SPLIT_PART, POSITION, SUBSTRING, REPLACE, LEFT
-- Result: The e-mail is split into user name and domain; the name is shortened, rewritten with underscores and reduced to its initial.
SELECT email, SPLIT_PART(email, '@', 1) AS username, SPLIT_PART(email, '@', 2) AS domain,
       POSITION('@' IN email) AS at_position, SUBSTRING(full_name FROM 1 FOR 4) AS first_four,
       REPLACE(full_name, ' ', '_') AS underscored, LEFT(full_name, 1) AS initial
FROM Users;

-- S3.3. Character functions (trim, pad, concatenate)
-- Concept: TRIM, LPAD, RPAD, CONCAT and the || operator
-- Result: Padded transaction codes such as 000007 and readable text labels for five transactions.
SELECT TRIM('  Food  ') AS trimmed, LPAD(transaction_id::text, 6, '0') AS txn_code,
       RPAD(LEFT(description, 10), 12, '.') AS padded,
       CONCAT('Rs. ', amount) AS label,
       description || ' (' || txn_date || ')' AS full_text
FROM Transactions
WHERE user_id = 1
ORDER BY transaction_id
LIMIT 5;

-- S3.4. Numeric functions
-- Concept: ROUND, CEIL, FLOOR, TRUNC, MOD, POWER, SQRT, SIGN, ABS
-- Result: Each Food amount is divided by 7 and rounded in different ways, plus roots, powers and the distance from 1000.
SELECT amount, ROUND(amount / 7, 2) AS rounded_2, ROUND(amount / 7) AS rounded_0,
       CEIL(amount / 7) AS ceil_value, FLOOR(amount / 7) AS floor_value,
       TRUNC(amount / 7, 1) AS truncated, MOD(amount::int, 7) AS remainder,
       POWER(amount / 1000, 2) AS squared, ROUND(SQRT(amount), 2) AS square_root,
       SIGN(amount - 1000) AS sign_vs_1000, ABS(amount - 1000) AS distance_from_1000
FROM Transactions
WHERE user_id = 1 AND category_id = 1
ORDER BY transaction_id;

-- S3.5. Date functions
-- Concept: EXTRACT, TO_CHAR, DATE_TRUNC, AGE, date subtraction
-- Result: Year, month, weekday, a formatted date, the first day of the month and how many days ago the transaction happened.
SELECT txn_date, EXTRACT(YEAR FROM txn_date) AS yr, EXTRACT(MONTH FROM txn_date) AS mon,
       TO_CHAR(txn_date, 'Day') AS day_name, TO_CHAR(txn_date, 'DD Mon YYYY') AS pretty_date,
       DATE_TRUNC('month', txn_date)::date AS month_start,
       CURRENT_DATE - txn_date AS days_ago, AGE(CURRENT_DATE, txn_date) AS age_text
FROM Transactions
WHERE user_id = 1
ORDER BY txn_date DESC
LIMIT 5;

-- S3.6. Date arithmetic
-- Concept: CURRENT_DATE, NOW(), INTERVAL arithmetic
-- Result: Today, 30 days ahead, the same day next month, the first and last day of the current month.
SELECT CURRENT_DATE AS today,
       CURRENT_DATE + 30 AS in_30_days,
       (CURRENT_DATE + INTERVAL '1 month')::date AS next_month,
       DATE_TRUNC('month', CURRENT_DATE)::date AS month_first_day,
       (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_last_day,
       NOW() AS right_now;

-- S3.7. Conversion functions
-- Concept: TO_CHAR (numbers), TO_DATE, TO_NUMBER, CAST and the :: operator
-- Result: A formatted amount, a parsed date and number, and numbers converted from text.
SELECT TO_CHAR(amount, 'FM999,999,990.00') AS formatted_amount,
       TO_DATE('15-08-2026', 'DD-MM-YYYY') AS parsed_date,
       TO_NUMBER('1,234.50', '9,999.99') AS parsed_number,
       CAST('250.75' AS NUMERIC(10,2)) + 1 AS cast_example,
       '42'::int * 2 AS double_colon_example
FROM Transactions
WHERE user_id = 1
ORDER BY transaction_id
LIMIT 3;

-- S3.8. NULL-handling functions, GREATEST/LEAST and CASE
-- Concept: COALESCE, NULLIF, GREATEST, LEAST, CASE
-- Result: Missing descriptions are replaced; amounts are clamped to 1000 and every expense gets a High, Medium or Low band.
SELECT transaction_id, COALESCE(description, '(no description)') AS shown_description,
       NULLIF(amount, 450) AS null_if_450, GREATEST(amount, 1000) AS at_least_1000,
       LEAST(amount, 1000) AS at_most_1000,
       CASE WHEN amount >= 2000 THEN 'High' WHEN amount >= 500 THEN 'Medium' ELSE 'Low' END AS size_band
FROM Transactions
WHERE user_id = 1
ORDER BY amount DESC
LIMIT 6;

-- S3.9. Single row functions inside GROUP BY
-- Concept: TO_CHAR and EXTRACT used to group rows
-- Result: Total spending for each day of the week, in Monday-to-Sunday order.
SELECT TO_CHAR(t.txn_date, 'Day') AS weekday, EXTRACT(ISODOW FROM t.txn_date)::int AS day_no,
       COUNT(*) AS transactions, SUM(t.amount) AS total_spent
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY 1, 2
ORDER BY 2;


-- #####################################################################
-- 4. OPERATORS AND GROUP FUNCTIONS
-- #####################################################################

-- S4.1. Arithmetic operators
-- Concept: +, -, *, /, % and unary minus
-- Result: Each Food amount with 100 added and subtracted, doubled, quartered, its remainder when divided by 7 and its negative.
SELECT amount, amount + 100 AS plus_100, amount - 100 AS minus_100, amount * 2 AS doubled,
       amount / 4 AS quarter, amount % 7 AS remainder_7, -amount AS negated
FROM Transactions
WHERE user_id = 1 AND category_id = 1
ORDER BY transaction_id;

-- S4.2. Comparison and logical operators
-- Concept: =, <>, >=, AND, OR, NOT with parentheses
-- Result: Expenses that are at least Rs. 1000 or belong to Food, excluding income and excluding the Rs. 450 lunch.
SELECT txn_date, category_id, amount, description
FROM Transactions
WHERE user_id = 1
  AND (amount >= 1000 OR category_id = 1)
  AND NOT (category_id >= 9)
  AND amount <> 450
ORDER BY txn_date DESC;

-- S4.3. BETWEEN, IN, LIKE and IS NOT NULL
-- Concept: Range, list, pattern and NULL operators
-- Result: Expenses of Rs. 500 to 2000 in the first four categories whose description contains the letter o.
SELECT description, amount
FROM Transactions
WHERE user_id = 1
  AND amount BETWEEN 500 AND 2000
  AND category_id IN (1, 2, 3, 4)
  AND description ILIKE '%o%'
  AND description IS NOT NULL;

-- S4.4. Pattern matching with LIKE
-- Concept: % (any characters) and _ (one character)
-- Result: Category names starting with S, ending in ing, or four letters ending in ood (Salary, Shopping, Scholarship, Food, Bills...).
SELECT name FROM Categories
WHERE name LIKE 'S%' OR name LIKE '%ing' OR name LIKE '_ood'
ORDER BY name;

-- S4.5. Set operators
-- Concept: UNION, INTERSECT, EXCEPT
-- Result: Categories used by either user, by both users, and only by user 1.
SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 1)
UNION
SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 2)
ORDER BY name;

SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 1)
INTERSECT
SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 2)
ORDER BY name;

SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 1)
EXCEPT
SELECT name FROM Categories WHERE category_id IN (SELECT category_id FROM Transactions WHERE user_id = 2)
ORDER BY name;

-- S4.6. Group (aggregate) functions
-- Concept: COUNT(*), COUNT(column), COUNT(DISTINCT), SUM, AVG, MIN, MAX
-- Result: One summary row for user 1 showing row counts, distinct categories, total, average, smallest, largest and the spread.
SELECT COUNT(*) AS all_rows, COUNT(description) AS rows_with_description,
       COUNT(DISTINCT category_id) AS categories_used, SUM(amount) AS total_amount,
       ROUND(AVG(amount), 2) AS average_amount, MIN(amount) AS smallest, MAX(amount) AS largest,
       MAX(amount) - MIN(amount) AS spread
FROM Transactions
WHERE user_id = 1;

-- S4.7. Sub-totals with ROLLUP
-- Concept: GROUP BY ROLLUP
-- Result: Totals per category, a sub-total for income and for expense, and a grand total (NULL labels mark the totals).
SELECT c.type, c.name, SUM(t.amount) AS total
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1
GROUP BY ROLLUP (c.type, c.name)
ORDER BY c.type, c.name;

-- S4.8. Conditional counts, string aggregation and standard deviation
-- Concept: COUNT ... FILTER, STRING_AGG, STDDEV, HAVING
-- Result: For expense categories with at least two transactions: how many were Rs. 1000 or more, a list of descriptions and the standard deviation.
SELECT c.name, COUNT(*) AS txns, COUNT(*) FILTER (WHERE t.amount >= 1000) AS big_txns,
       STRING_AGG(t.description, ', ' ORDER BY t.txn_date) AS descriptions,
       ROUND(STDDEV(t.amount), 2) AS std_deviation
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY c.name
HAVING COUNT(*) >= 2
ORDER BY txns DESC;

-- S4.9. HAVING with a subquery
-- Concept: Group function compared with another group function
-- Result: Expense categories whose average expense is higher than the user's overall average expense.
SELECT c.name, ROUND(AVG(t.amount), 2) AS category_average
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY c.name
HAVING AVG(t.amount) > (SELECT AVG(t2.amount) FROM Transactions t2
                        JOIN Categories c2 ON c2.category_id = t2.category_id
                        WHERE t2.user_id = 1 AND c2.type = 'expense')
ORDER BY category_average DESC;


-- #####################################################################
-- 5. SUBQUERIES, VIEWS AND JOINS
-- #####################################################################

-- S5.1. Single-row subquery
-- Concept: Subquery returning one value, used with =
-- Result: The most expensive expense of user 1.
SELECT t.txn_date, t.amount, t.description
FROM Transactions t
WHERE t.user_id = 1
  AND t.amount = (SELECT MAX(t2.amount) FROM Transactions t2
                  JOIN Categories c2 ON c2.category_id = t2.category_id
                  WHERE t2.user_id = 1 AND c2.type = 'expense')
  AND t.category_id < 9;

-- S5.2. Multiple-row subquery with IN
-- Concept: Subquery returning a list
-- Result: Expenses made in categories that have a budget this month.
SELECT t.txn_date, t.category_id, t.amount
FROM Transactions t
WHERE t.user_id = 1
  AND t.category_id IN (SELECT b.category_id FROM Budgets b
                        WHERE b.user_id = 1 AND b.budget_month = DATE_TRUNC('month', CURRENT_DATE)::date)
ORDER BY t.txn_date DESC;

-- S5.3. ANY and ALL
-- Concept: Comparison with a set of values
-- Result: First query: expenses bigger than at least one Food expense. Second query: expenses bigger than every Food expense.
SELECT txn_date, amount FROM Transactions
WHERE user_id = 1 AND category_id < 9
  AND amount > ANY (SELECT amount FROM Transactions WHERE user_id = 1 AND category_id = 1)
ORDER BY amount;

SELECT txn_date, amount FROM Transactions
WHERE user_id = 1 AND category_id < 9
  AND amount > ALL (SELECT amount FROM Transactions WHERE user_id = 1 AND category_id = 1)
ORDER BY amount;

-- S5.4. Correlated subquery
-- Concept: The inner query uses a column of the outer query
-- Result: Expenses that are higher than the average of their own category.
SELECT t.txn_date, c.name AS category, t.amount
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
  AND t.amount > (SELECT AVG(t2.amount) FROM Transactions t2
                  WHERE t2.user_id = t.user_id AND t2.category_id = t.category_id)
ORDER BY t.amount DESC;

-- S5.5. Subquery in the FROM clause (derived table)
-- Concept: Inline view
-- Result: The average of the monthly expense totals.
SELECT ROUND(AVG(m.monthly_total), 2) AS average_monthly_expense
FROM (SELECT TO_CHAR(t.txn_date, 'YYYY-MM') AS ym, SUM(t.amount) AS monthly_total
      FROM Transactions t
      JOIN Categories c ON c.category_id = t.category_id
      WHERE t.user_id = 1 AND c.type = 'expense'
      GROUP BY TO_CHAR(t.txn_date, 'YYYY-MM')) m;

-- S5.6. Scalar subquery in the SELECT list
-- Concept: Subquery that returns one value for every row
-- Result: Each expense category total and its percentage of all expenses.
SELECT c.name, SUM(t.amount) AS total,
       ROUND(SUM(t.amount) * 100 / (SELECT SUM(x.amount) FROM Transactions x
                                    JOIN Categories cx ON cx.category_id = x.category_id
                                    WHERE x.user_id = 1 AND cx.type = 'expense'), 1) AS percent_of_expenses
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY c.name
ORDER BY total DESC;

-- S5.7. Nested subqueries
-- Concept: Subquery inside a subquery
-- Result: Categories where user 1's total is above the average category total.
SELECT name FROM Categories
WHERE category_id IN (
    SELECT category_id FROM Transactions WHERE user_id = 1
    GROUP BY category_id
    HAVING SUM(amount) > (SELECT AVG(cat_total)
                          FROM (SELECT SUM(amount) AS cat_total FROM Transactions
                                WHERE user_id = 1 GROUP BY category_id) s))
ORDER BY name;

-- S5.8. Simple view with CHECK OPTION
-- Concept: CREATE VIEW, WITH CHECK OPTION
-- Result: A view that shows only expense categories.
CREATE OR REPLACE VIEW v_expense_categories AS
SELECT category_id, name, type FROM Categories WHERE type = 'expense'
WITH CHECK OPTION;
SELECT * FROM v_expense_categories;

-- S5.9. Changing data through a view
-- Concept: Updatable view; the CHECK OPTION rejects rows the view cannot show
-- Result: The Gifts category is added through the view (it is visible inside the transaction) and ROLLBACK removes it again.
BEGIN;
INSERT INTO v_expense_categories (name, type) VALUES ('Gifts', 'expense');
SELECT name FROM v_expense_categories ORDER BY name;
ROLLBACK;

-- S5.10. View violating CHECK OPTION (DELIBERATE FAILURE)
-- Concept: WITH CHECK OPTION
-- Result: Fails with "new row violates check option" because the row is income.
INSERT INTO v_expense_categories (name, type) VALUES ('Lottery', 'income');

-- S5.11. Complex view (join and aggregate)
-- Concept: CREATE VIEW over a join with GROUP BY
-- Result: Totals per user and category, filtered for user 1.
CREATE OR REPLACE VIEW v_user_category_totals AS
SELECT t.user_id, c.name AS category, c.type, SUM(t.amount) AS total, COUNT(*) AS txn_count
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
GROUP BY t.user_id, c.name, c.type;
SELECT * FROM v_user_category_totals WHERE user_id = 1 ORDER BY total DESC;

-- S5.12. List and drop views
-- Concept: pg_views, DROP VIEW
-- Result: Shows all views in the database, then removes the two practice views.
SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;
DROP VIEW v_user_category_totals;
DROP VIEW v_expense_categories;

-- S5.13. INNER JOIN with USING
-- Concept: Equi-join on a common column name
-- Result: Five transactions with their category names.
SELECT t.txn_date, name AS category, t.amount
FROM Transactions t
JOIN Categories USING (category_id)
WHERE t.user_id = 1
ORDER BY t.txn_date DESC, t.transaction_id
LIMIT 5;

-- S5.14. LEFT JOIN (anti-join)
-- Concept: LEFT OUTER JOIN with IS NULL to find missing matches
-- Result: Expense categories that user 1 has never used.
SELECT c.name
FROM Categories c
LEFT JOIN Transactions t ON t.category_id = c.category_id AND t.user_id = 1
WHERE c.type = 'expense' AND t.transaction_id IS NULL;

-- S5.15. RIGHT JOIN
-- Concept: RIGHT OUTER JOIN keeps every row of the right table
-- Result: Every category with the number of transactions of user 1 (0 for unused ones).
SELECT c.name, COUNT(t.transaction_id) AS transactions
FROM Transactions t
RIGHT JOIN Categories c ON c.category_id = t.category_id AND t.user_id = 1
GROUP BY c.name
ORDER BY transactions DESC, c.name;

-- S5.16. FULL OUTER JOIN
-- Concept: FULL OUTER JOIN keeps unmatched rows from both sides
-- Result: Budgets and spending of this month side by side; a category with spending but no budget shows NULL as the limit (Health).
SELECT COALESCE(b.category_id, s.category_id) AS category_id, b.amount_limit, s.spent
FROM (SELECT category_id, amount_limit FROM Budgets
      WHERE user_id = 1 AND budget_month = DATE_TRUNC('month', CURRENT_DATE)::date) b
FULL OUTER JOIN
     (SELECT t.category_id, SUM(t.amount) AS spent
      FROM Transactions t JOIN Categories c ON c.category_id = t.category_id
      WHERE t.user_id = 1 AND c.type = 'expense' AND t.txn_date >= DATE_TRUNC('month', CURRENT_DATE)
      GROUP BY t.category_id) s
  ON s.category_id = b.category_id
ORDER BY 1;

-- S5.17. CROSS JOIN
-- Concept: Cartesian product
-- Result: Every user paired with every expense category (2 users x 8 categories = 16 rows), useful as a budget template.
SELECT u.full_name, c.name AS category
FROM Users u
CROSS JOIN Categories c
WHERE c.type = 'expense'
ORDER BY u.full_name, c.name;

-- S5.18. SELF JOIN
-- Concept: A table joined with itself
-- Result: Pairs of transactions of the same user made on the same day.
SELECT a.txn_date, a.description AS first_transaction, b.description AS second_transaction
FROM Transactions a
JOIN Transactions b ON a.user_id = b.user_id AND a.txn_date = b.txn_date
                   AND a.transaction_id < b.transaction_id
WHERE a.user_id = 1
ORDER BY a.txn_date DESC;

-- S5.19. Joining four tables
-- Concept: Multi-table join with a view
-- Result: User name, category, budget limit and amount spent for every budget.
SELECT u.full_name, c.name AS category, b.amount_limit, v.spent
FROM Budgets b
JOIN Users u ON u.user_id = b.user_id
JOIN Categories c ON c.category_id = b.category_id
JOIN v_budget_status v ON v.budget_id = b.budget_id
ORDER BY u.full_name, c.name;


-- #####################################################################
-- 6. HIGH-LEVEL LANGUAGE EXTENSIONS (PL/pgSQL):
--    PROCEDURES, FUNCTIONS, CURSORS AND TRIGGERS
--    (the objects themselves are created in schema.sql, section 4 and 5)
-- #####################################################################

-- S6.1. Calling stored functions
-- Concept: User-defined functions (PL/pgSQL and SQL language)
-- Result: Food spending of this month, the status text for Rs. 2500 of a Rs. 3000 budget, and the balance of user 1.
SELECT fn_month_spent(1, 1, CURRENT_DATE) AS food_spent_this_month,
       fn_budget_status(2500, 3000)       AS status_example,
       fn_user_balance(1)                 AS balance_of_user_1;

-- S6.2. Function used inside a query
-- Concept: A function called once for every row
-- Result: Spending of this month for every expense category.
SELECT c.name, fn_month_spent(1, c.category_id, CURRENT_DATE) AS spent_this_month
FROM Categories c
WHERE c.type = 'expense'
ORDER BY spent_this_month DESC;

-- S6.3. IF / ELSIF logic in a function
-- Concept: Conditional control structure
-- Result: Status for four amounts against a Rs. 1000 budget: OK, NEAR LIMIT, REACHED, EXCEEDED.
SELECT amt AS spent, fn_budget_status(amt, 1000) AS status
FROM (VALUES (500), (850), (1000), (1200)) AS v(amt);

-- S6.4. Calling a stored procedure
-- Concept: CREATE PROCEDURE and CALL (the audit trigger fires as well)
-- Result: A Rs. 120 expense is inserted after validation; the audit log shows the INSERT; the test row is then deleted.
CALL sp_add_transaction(1, 1, 120.00, CURRENT_DATE, 'Tea and snacks');
SELECT transaction_id, action, new_amount FROM AuditLog WHERE user_id = 1 ORDER BY log_id DESC LIMIT 1;
DELETE FROM Transactions WHERE user_id = 1 AND description = 'Tea and snacks';

-- S6.5. Procedure that rejects bad input (DELIBERATE FAILURE)
-- Concept: RAISE EXCEPTION inside a procedure
-- Result: Fails with the message "Category 999 does not exist".
CALL sp_add_transaction(1, 999, 50.00, CURRENT_DATE, 'bad category');

-- S6.6. Procedure that copies budgets
-- Concept: Procedure with GET DIAGNOSTICS and ON CONFLICT
-- Result: A notice reports how many budgets were copied to next month; ROLLBACK undoes them.
BEGIN;
CALL sp_copy_budgets(1, DATE_TRUNC('month', CURRENT_DATE)::date,
                        (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month')::date);
SELECT COUNT(*) AS budgets_inside_transaction FROM Budgets WHERE user_id = 1;
ROLLBACK;

-- S6.7. Function that uses an explicit cursor
-- Concept: CURSOR - DECLARE, OPEN, FETCH, CLOSE inside fn_budget_alerts
-- Result: Only the budgets of this month that are near, reached or exceeded, with their spending.
SELECT * FROM fn_budget_alerts(1, CURRENT_DATE);

-- S6.8. Parameterised cursor in an anonymous block
-- Concept: CURSOR with a parameter, LOOP, EXIT WHEN, RAISE NOTICE
-- Result: Prints the three highest spending categories of user 1 as notices.
DO $$
DECLARE
    cur CURSOR (p_user INT) FOR
        SELECT c.name, SUM(t.amount) AS total
        FROM Transactions t
        JOIN Categories c ON c.category_id = t.category_id
        WHERE t.user_id = p_user AND c.type = 'expense'
        GROUP BY c.name
        ORDER BY total DESC;
    rec    RECORD;
    v_rank INT := 0;
BEGIN
    OPEN cur(1);
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        v_rank := v_rank + 1;
        RAISE NOTICE '% . % - Rs. %', v_rank, rec.name, rec.total;
        EXIT WHEN v_rank >= 3;
    END LOOP;
    CLOSE cur;
END $$;

-- S6.9. WHILE loop with variables
-- Concept: Variables, WHILE loop, SELECT INTO
-- Result: Prints the total expenses of the last three months as notices.
DO $$
DECLARE
    v_month DATE;
    v_total NUMERIC;
    i       INT := 0;
BEGIN
    WHILE i < 3 LOOP
        v_month := (DATE_TRUNC('month', CURRENT_DATE) - (i || ' month')::interval)::date;
        SELECT COALESCE(SUM(t.amount), 0) INTO v_total
        FROM Transactions t
        JOIN Categories c ON c.category_id = t.category_id
        WHERE t.user_id = 1 AND c.type = 'expense' AND DATE_TRUNC('month', t.txn_date) = v_month;
        RAISE NOTICE '% - Rs. %', TO_CHAR(v_month, 'Mon YYYY'), v_total;
        i := i + 1;
    END LOOP;
END $$;

-- S6.10. Exception handling
-- Concept: BEGIN ... EXCEPTION WHEN ... THEN
-- Result: The trigger rejects a negative amount; the block catches the error and prints the message instead of failing.
DO $$
BEGIN
    INSERT INTO Transactions (user_id, category_id, amount, txn_date) VALUES (1, 1, -10, CURRENT_DATE);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Caught error: %', SQLERRM;
END $$;

-- S6.11. Trigger that normalises data
-- Concept: BEFORE INSERT trigger trg_user_normalise
-- Result: The e-mail is saved trimmed and in lower case: test.user@example.com; ROLLBACK removes the test user.
BEGIN;
INSERT INTO Users (full_name, email, password_hash) VALUES ('  Trigger Test ', '  Test.User@EXAMPLE.com ', 'x');
SELECT full_name, email FROM Users WHERE full_name = 'Trigger Test';
ROLLBACK;

-- S6.12. List triggers, functions and procedures
-- Concept: System catalogs pg_trigger and pg_proc
-- Result: Every trigger of the project, then every project function (f) and procedure (p).
SELECT tgrelid::regclass AS table_name, tgname AS trigger_name
FROM pg_trigger
WHERE NOT tgisinternal
ORDER BY 1, 2;

SELECT proname AS routine_name, CASE prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure' END AS kind
FROM pg_proc
WHERE proname LIKE 'fn\_%' OR proname LIKE 'sp\_%'
ORDER BY kind, routine_name;

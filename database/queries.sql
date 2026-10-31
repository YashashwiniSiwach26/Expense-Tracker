-- =====================================================================
--  25 sample queries demonstrating the DBMS concepts  |  PostgreSQL
--  Demo user = user_id 1.   Run:
--      psql -U postgres -d expense_tracker -f database/queries.sql
--  Q16, Q17 and Q19 FAIL ON PURPOSE (they show constraints/triggers rejecting bad data);
--  psql prints the error and carries on with the next query.
-- =====================================================================

-- Q1. All expenses of a user with category names
-- Concept: INNER JOIN, one-to-many relationship
-- Result: One row per expense of user 1, newest first, with the category name instead of its id.
SELECT t.transaction_id, t.txn_date, c.name AS category, t.amount, t.description
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
ORDER BY t.txn_date DESC;

-- Q2. Every expense category with this month's spending (0 if nothing spent)
-- Concept: LEFT JOIN with COALESCE
-- Result: All 8 expense categories appear; unused ones such as Other Expense show 0.
SELECT c.name AS category, COALESCE(SUM(t.amount), 0) AS spent_this_month
FROM Categories c
LEFT JOIN Transactions t ON t.category_id = c.category_id
     AND t.user_id = 1
     AND t.txn_date >= date_trunc('month', CURRENT_DATE)
WHERE c.type = 'expense'
GROUP BY c.category_id, c.name
ORDER BY spent_this_month DESC;

-- Q3. Overall expense statistics
-- Concept: Aggregate functions SUM, AVG, MIN, MAX, COUNT
-- Result: A single row with total, average, smallest and largest expense and the number of expenses.
SELECT SUM(t.amount) AS total_spent, ROUND(AVG(t.amount), 2) AS avg_expense,
       MIN(t.amount) AS smallest, MAX(t.amount) AS largest, COUNT(*) AS no_of_expenses
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense';

-- Q4. Categories on which more than Rs. 2000 was spent
-- Concept: GROUP BY with HAVING
-- Result: Only categories whose total is above 2000 (HAVING filters groups, WHERE filters rows).
SELECT c.name AS category, SUM(t.amount) AS total, COUNT(*) AS txn_count
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY c.category_id, c.name
HAVING SUM(t.amount) > 2000
ORDER BY total DESC;

-- Q5. Expenses larger than the user's average expense
-- Concept: Scalar subquery in WHERE
-- Result: The inner query computes one average; the outer query keeps only bigger expenses.
SELECT t.txn_date, c.name AS category, t.amount
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
  AND t.amount > (SELECT AVG(t2.amount)
                  FROM Transactions t2
                  JOIN Categories c2 ON c2.category_id = t2.category_id
                  WHERE t2.user_id = 1 AND c2.type = 'expense')
ORDER BY t.amount DESC;

-- Q6. Expense categories the user has never used
-- Concept: Subquery with NOT IN
-- Result: Categories that do not appear in any of the user's transactions (e.g. Other Expense).
SELECT name
FROM Categories
WHERE type = 'expense'
  AND category_id NOT IN (SELECT category_id FROM Transactions WHERE user_id = 1);

-- Q7. Monthly income, expense and savings
-- Concept: View (v_monthly_summary)
-- Result: One row per month with totals; net_savings is income minus expense.
SELECT ym, total_income, total_expense, (total_income - total_expense) AS net_savings
FROM v_monthly_summary
WHERE user_id = 1
ORDER BY ym;

-- Q8. Budget versus actual spending with a warning flag
-- Concept: View with correlated subquery, CASE expression
-- Result: Each budget of the current month with percent used and a status (OK, NEAR LIMIT, REACHED, EXCEEDED).
SELECT category, amount_limit, spent,
       ROUND(spent / amount_limit * 100, 1) AS percent_used,
       CASE WHEN spent > amount_limit THEN 'EXCEEDED'
            WHEN spent = amount_limit THEN 'REACHED'
            WHEN spent >= 0.8 * amount_limit THEN 'NEAR LIMIT'
            ELSE 'OK' END AS status
FROM v_budget_status
WHERE user_id = 1 AND ym = to_char(CURRENT_DATE, 'YYYY-MM')
ORDER BY percent_used DESC;

-- Q9. Highest spending category
-- Concept: GROUP BY, ORDER BY, LIMIT
-- Result: A single row with the category on which the most money was spent.
SELECT c.name, SUM(t.amount) AS total
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY c.category_id, c.name
ORDER BY total DESC
LIMIT 1;

-- Q10. Daily report
-- Concept: GROUP BY on a date column, SUM and COUNT
-- Result: One row per day that has expenses, with the day's total and number of transactions.
SELECT t.txn_date, SUM(t.amount) AS daily_total, COUNT(*) AS transactions
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense'
GROUP BY t.txn_date
ORDER BY t.txn_date;

-- Q11. Monthly report
-- Concept: GROUP BY with EXTRACT and a conditional aggregate
-- Result: Income, expense and balance per month.
SELECT EXTRACT(YEAR FROM t.txn_date)::int  AS yr,
       EXTRACT(MONTH FROM t.txn_date)::int AS mon,
       SUM(CASE WHEN c.type = 'income'  THEN t.amount ELSE 0 END) AS income,
       SUM(CASE WHEN c.type = 'expense' THEN t.amount ELSE 0 END) AS expense,
       SUM(CASE WHEN c.type = 'income' THEN t.amount ELSE -t.amount END) AS balance
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1
GROUP BY yr, mon
ORDER BY yr, mon;

-- Q12. Yearly report
-- Concept: GROUP BY year
-- Result: One row per year with total income, total expense and transaction count.
SELECT EXTRACT(YEAR FROM t.txn_date)::int AS yr,
       SUM(CASE WHEN c.type = 'income'  THEN t.amount ELSE 0 END) AS income,
       SUM(CASE WHEN c.type = 'expense' THEN t.amount ELSE 0 END) AS expense,
       COUNT(*) AS transactions
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1
GROUP BY yr
ORDER BY yr;

-- Q13. Filter expenses by date, category and amount
-- Concept: Multi-condition WHERE (uses idx_txn_user_date)
-- Result: Food expenses between Rs. 100 and Rs. 5000 in the last 6 months, newest first.
SELECT t.transaction_id, t.txn_date, t.amount, t.description
FROM Transactions t
WHERE t.user_id = 1
  AND t.txn_date BETWEEN CURRENT_DATE - INTERVAL '6 months' AND CURRENT_DATE
  AND t.category_id = 1
  AND t.amount BETWEEN 100 AND 5000
ORDER BY t.txn_date DESC;

-- Q14. Check that indexes exist and are used
-- Concept: Indexes (EXPLAIN and pg_indexes)
-- Result: The first statement shows the query plan (with a tiny table PostgreSQL may still choose a sequential scan); the second lists every index on Transactions.
EXPLAIN SELECT * FROM Transactions WHERE user_id = 1 AND txn_date >= CURRENT_DATE - 30;
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'transactions' ORDER BY indexname;

-- Q15. Atomic copy of budgets (transaction)
-- Concept: Transactions - BEGIN / COMMIT / ROLLBACK
-- Result: Next month's budgets are created inside a transaction; ROLLBACK undoes all rows together (use COMMIT to keep them).
BEGIN;
  INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit)
  SELECT user_id, category_id, (budget_month + INTERVAL '1 month')::date, amount_limit
  FROM Budgets
  WHERE user_id = 1 AND budget_month = date_trunc('month', CURRENT_DATE)::date
  ON CONFLICT (user_id, category_id, budget_month) DO NOTHING;
  SELECT COUNT(*) AS budgets_inside_transaction FROM Budgets WHERE user_id = 1;
ROLLBACK;
SELECT COUNT(*) AS budgets_after_rollback FROM Budgets WHERE user_id = 1;

-- Q16. Trigger / CHECK validation: negative amount (DELIBERATE FAILURE)
-- Concept: BEFORE INSERT trigger fn_txn_validate
-- Result: Fails with the error "Transaction amount must be greater than zero"; nothing is inserted.
INSERT INTO Transactions (user_id, category_id, amount, txn_date) VALUES (1, 1, -50, CURRENT_DATE);

-- Q17. Trigger validation: budget for an income category (DELIBERATE FAILURE)
-- Concept: BEFORE INSERT trigger fn_budget_validate (cross-table rule a CHECK cannot express)
-- Result: Fails with "Budgets can only be set for expense categories" because category 9 is Salary.
INSERT INTO Budgets (user_id, category_id, budget_month, amount_limit) VALUES (1, 9, CURRENT_DATE, 500);

-- Q18. Audit trigger
-- Concept: AFTER INSERT/UPDATE/DELETE trigger fn_txn_audit
-- Result: Three audit rows (INSERT, UPDATE, DELETE) are written automatically; the last SELECT shows them.
INSERT INTO Transactions (user_id, category_id, amount, txn_date, description) VALUES (1, 1, 100, CURRENT_DATE, 'trigger test');
UPDATE Transactions SET amount = 150 WHERE description = 'trigger test' AND user_id = 1;
DELETE FROM Transactions WHERE description = 'trigger test' AND user_id = 1;
SELECT log_id, transaction_id, action, old_amount, new_amount
FROM AuditLog WHERE user_id = 1 ORDER BY log_id DESC LIMIT 3;

-- Q19. Referential integrity (DELIBERATE FAILURE)
-- Concept: Foreign key with ON DELETE RESTRICT
-- Result: Fails with a foreign key violation because the Food category is used by transactions.
DELETE FROM Categories WHERE category_id = 1;

-- Q20. Categories with spending this month but no budget
-- Concept: Correlated subqueries with EXISTS / NOT EXISTS
-- Result: Categories such as Health where money was spent but no budget was set.
SELECT c.name
FROM Categories c
WHERE c.type = 'expense'
  AND EXISTS (SELECT 1 FROM Transactions t
              WHERE t.user_id = 1 AND t.category_id = c.category_id
                AND t.txn_date >= date_trunc('month', CURRENT_DATE))
  AND NOT EXISTS (SELECT 1 FROM Budgets b
                  WHERE b.user_id = 1 AND b.category_id = c.category_id
                    AND b.budget_month = date_trunc('month', CURRENT_DATE)::date);

-- Q21. Month-over-month change in spending
-- Concept: Window function LAG over a view
-- Result: Each month's expense, the previous month's expense and the difference between them.
SELECT ym, total_expense,
       LAG(total_expense) OVER (ORDER BY ym) AS previous_month,
       total_expense - LAG(total_expense) OVER (ORDER BY ym) AS change
FROM v_monthly_summary
WHERE user_id = 1
ORDER BY ym;

-- Q22. Running balance
-- Concept: Window aggregate SUM() OVER (ORDER BY ...)
-- Result: Every transaction in date order with the cumulative balance after it.
SELECT t.txn_date, c.name AS category, c.type, t.amount,
       SUM(CASE WHEN c.type = 'income' THEN t.amount ELSE -t.amount END)
           OVER (ORDER BY t.txn_date, t.transaction_id) AS running_balance
FROM Transactions t
JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1
ORDER BY t.txn_date, t.transaction_id;

-- Q23. Share of each category in total spending
-- Concept: Common Table Expression (WITH) and window SUM() OVER ()
-- Result: Each category's total and its percentage of all expenses; percentages add up to 100.
WITH cat_totals AS (
    SELECT c.name, SUM(t.amount) AS total
    FROM Transactions t
    JOIN Categories c ON c.category_id = t.category_id
    WHERE t.user_id = 1 AND c.type = 'expense'
    GROUP BY c.name
)
SELECT name, total, ROUND(total * 100.0 / SUM(total) OVER (), 1) AS percent_share
FROM cat_totals
ORDER BY total DESC;

-- Q24. Income and expense totals as two rows
-- Concept: UNION ALL
-- Result: Two rows, Income and Expense, each with its overall total.
SELECT 'Income' AS kind, COALESCE(SUM(t.amount), 0) AS total
FROM Transactions t JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'income'
UNION ALL
SELECT 'Expense', COALESCE(SUM(t.amount), 0)
FROM Transactions t JOIN Categories c ON c.category_id = t.category_id
WHERE t.user_id = 1 AND c.type = 'expense';

-- Q25. Per-user overview (administrator view of all users)
-- Concept: Multi-table LEFT JOIN, GROUP BY, HAVING
-- Result: One row per user who has transactions, with counts, income, expense and balance.
SELECT u.full_name, COUNT(t.transaction_id) AS transactions,
       COALESCE(SUM(CASE WHEN c.type = 'income'  THEN t.amount END), 0) AS income,
       COALESCE(SUM(CASE WHEN c.type = 'expense' THEN t.amount END), 0) AS expense,
       COALESCE(SUM(CASE WHEN c.type = 'income' THEN t.amount ELSE -t.amount END), 0) AS balance
FROM Users u
LEFT JOIN Transactions t ON t.user_id = u.user_id
LEFT JOIN Categories c ON c.category_id = t.category_id
GROUP BY u.user_id, u.full_name
HAVING COUNT(t.transaction_id) > 0
ORDER BY balance DESC;

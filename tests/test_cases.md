# Test cases (manual) — demo account: demo@example.com / Demo@123

| # | Feature | Steps | Expected result |
|---|---------|-------|-----------------|
| 1 | Register | Register with valid name, new email, password `Test@1234` | Success toast, redirected to login; row in `Users` with hashed password |
| 2 | Register – duplicate email | Register again with the same email | Error "account already exists" |
| 3 | Register – weak password | Password `abc` | Error about password rules |
| 4 | Login valid | demo@example.com / Demo@123 | Redirect to dashboard |
| 5 | Login invalid | Wrong password | Error "Invalid email or password" |
| 6 | Access control | Open `/dashboard` while logged out | Redirected to login; `/api/summary` returns 401 |
| 7 | Logout | Click Logout, then press Back and refresh | Login page shown, data not accessible |
| 8 | Dashboard | Open dashboard | Cards show totals, doughnut + bar charts render, budget warnings listed |
| 9 | Add income | Income → Add: Salary, 5000, today | Success toast, new row, totals increase |
| 10 | Add expense | Expenses → Add: Food, 250.50, today | Row appears; audit log shows INSERT |
| 11 | Negative amount | Add expense with amount -10 (bypass HTML min via DevTools) | Backend error "Amount must be greater than zero"; nothing saved |
| 12 | Zero / text amount | Amount 0 or `abc` through API | 400 error |
| 13 | Edit record | Edit an expense amount | Row updated; audit log shows UPDATE with old and new amount |
| 14 | Delete record | Delete an expense, confirm | Row removed; audit log shows DELETE |
| 15 | Filter | Filter expenses by category Food, min 500, date range | Only matching rows; total label updates |
| 16 | Wrong category type | POST an income category id with `type=expense` | 400 "Invalid expense category" |
| 17 | Set budget | Budgets → Food 3000 for a new month | Budget row with 0% used |
| 18 | Duplicate budget | Set the same category + month again | Error "That record already exists" |
| 19 | Budget warning | Budget with limit lower than spending | Red "exceeded" alert and red progress bar; 80–99 % shows amber warning |
| 20 | Budget on income category | POST income category to `/api/budgets` | 400 error (backend validation + PL/pgSQL trigger) |
| 21 | Copy budgets | Pick next month, click Copy from previous month | Budgets copied atomically; second click copies 0 |
| 22 | Reports | Daily, Monthly, Yearly | Tables and chart change; highest category and top-5 list shown |
| 23 | Data isolation | Log in as second@example.com | Sees only own 2 records and 1 budget |
| 24 | Cross-user access | While logged in as user 2, `PUT/DELETE /api/transactions/<id of user 1 record>` | 404 Record not found; record unchanged |
| 25 | SQL injection | Login with email `' OR 1=1 --` | Login fails (parameterised query) |
| 26 | XSS | Description `<script>alert(1)</script>` | Shown as plain text (escaped) |
| 27 | Syllabus script | `psql -U postgres -d expense_tracker -f database/dbms_syllabus.sql` | Runs to the end; errors appear only for scripts marked DELIBERATE FAILURE (S2.3-S2.7, S5.10, S6.5); project data unchanged |
| 28 | Stored function | `SELECT fn_budget_status(1200, 1000);` | Returns EXCEEDED |
| 29 | Stored procedure | `CALL sp_add_transaction(1, 1, 120, CURRENT_DATE, 'test');` | Notice shown; one expense and one INSERT row in AuditLog |
| 30 | Procedure validation | `CALL sp_add_transaction(1, 999, 50, CURRENT_DATE, 'x');` | Error "Category 999 does not exist"; nothing inserted |
| 31 | Cursor function | `SELECT * FROM fn_budget_alerts(1, CURRENT_DATE);` | Only budgets that are near, reached or exceeded are listed |
| 32 | Normalisation trigger | Insert a user with e-mail `  A@B.COM ` | Stored as `a@b.com` |

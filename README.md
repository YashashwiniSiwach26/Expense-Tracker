# Personal Expense & Budget Tracker (PostgreSQL edition)

Flask + PostgreSQL + HTML/CSS/JavaScript DBMS mini project.

## Folder structure
```
expense_tracker/
├── app.py                 Flask routes + JSON API + validation
├── db.py                  PostgreSQL connection helpers (psycopg2)
├── config.py              DB credentials / secret key
├── requirements.txt
├── database/
│   ├── schema.sql         tables, indexes, views, triggers, functions, procedures, cursor, sample data
│   ├── queries.sql        25 project queries (Q1-Q25)
│   └── dbms_syllabus.sql  syllabus scripts S1-S6: DDL/DML, constraints, functions, operators,
│                          subqueries/views/joins, procedures/functions/cursors/triggers
├── templates/             base, login, register, dashboard, transactions, budgets, reports
├── static/css/style.css
├── static/js/app.js
├── docs/                  er_diagram.png + project report (.docx)
└── tests/                 test_cases.md (manual) + test_api.py (pytest)
```

## Setup (Windows / Linux / Mac)
1. Install Python 3.9+ and PostgreSQL 12+ (you already have PostgreSQL).
2. Create the database (enter your postgres password when asked):
   ```
   createdb -U postgres expense_tracker
   psql -U postgres -d expense_tracker -f database/schema.sql
   ```
   If `createdb` / `psql` are not recognised on Windows, add `C:\Program Files\PostgreSQL\<version>\bin` to PATH,
   or run the same SQL from pgAdmin: create a database named `expense_tracker`, open the Query Tool and run `schema.sql`.
3. Install dependencies (virtual environment recommended):
   ```
   python -m venv venv
   venv\Scripts\activate          (Windows)       source venv/bin/activate   (Linux/Mac)
   pip install -r requirements.txt
   ```
4. Put your PostgreSQL password in `config.py` (or set the `DB_PASSWORD` environment variable).
5. Run `python app.py` and open http://127.0.0.1:5000
6. Login with `demo@example.com` / `Demo@123`, or register a new account.

Charts use Chart.js from a CDN, so an internet connection is needed for the charts.

## SQL scripts
```
psql -U postgres -d expense_tracker -f database/queries.sql        # 25 project queries
psql -U postgres -d expense_tracker -f database/dbms_syllabus.sql  # syllabus topics 1-6
```
Statements marked DELIBERATE FAILURE (Q16, Q17, Q19, S2.3-S2.7, S5.10, S6.5) show constraints, triggers and procedures
rejecting bad data; psql prints the error and continues. Procedure and cursor output appears as NOTICE lines.

## Syllabus coverage
| Topic | Where |
|-------|-------|
| 1. DDL and DML | `dbms_syllabus.sql` S1.1-S1.13, `schema.sql` sections 1 and 6 |
| 2. Constraints | `schema.sql` section 1, `dbms_syllabus.sql` S2.1-S2.11 |
| 3. Single row functions | `dbms_syllabus.sql` S3.1-S3.9 |
| 4. Operators and group functions | `dbms_syllabus.sql` S4.1-S4.9, `queries.sql` Q3, Q4, Q9-Q12 |
| 5. Subqueries, views and joins | `dbms_syllabus.sql` S5.1-S5.19, views in `schema.sql` section 3 |
| 6. Procedures, functions, cursors, triggers | `schema.sql` sections 4-5, `dbms_syllabus.sql` S6.1-S6.12 |

## Tests
`pip install pytest` then `pytest -q` (PostgreSQL must be running). Manual cases: `tests/test_cases.md`.

# ⏪ Rewind – Database Time Machine & Recovery System
Bahria University – BS IT – DBA & Management Lab (ITL 327), Spring 2026
Lab Engineer: Muhammad Hanzala Shamsi | Theory: Muhammad Shahzad
Team: Faiza Altaf, Mahnoor Sharif, Hadiqa Mehmood, Abdullah Zia Satti

Tracks every important change in Oracle tables (old value, new value, who, when), shows the full
history, flags suspicious changes and lets an ADMIN restore previous data safely.

## Architecture
| Layer | File | Oracle concept |
|---|---|---|
| Users, roles, profile | `sql/01_users_roles.sql`, `sql/07_security_views.sql` | Access control |
| Tables | `sql/02_tables.sql` | Audit tables, constraints, sequences |
| Audit + suspicious rules | `sql/04_rewind_core.sql`, `sql/05_audit_trigger.sql` | Triggers, packages |
| Recovery API | `sql/06_rewind_pkg.sql` | Procedures, packages, transactions, rollback, autonomous transaction |
| Reports | `sql/07_security_views.sql` | Views, ref cursor |
| GUI | `app/app.py` | Streamlit + python-oracledb |

## Setup
1. Install Oracle Database XE 21c and Python 3.10+.
2. `cd sql`, then as SYSTEM: `sqlplus system/<pwd>@//localhost:1521/XEPDB1 @01_users_roles.sql`
3. As REWIND: `sqlplus rewind/"Rewind#123"@//localhost:1521/XEPDB1 @run_all.sql`
4. Run the tests: `sqlplus /nolog @08_tests.sql`
5. GUI: `cd app && pip install -r requirements.txt && streamlit run app.py`
   Demo logins: `rw_admin / Admin#12345`, `rw_auditor / Auditor#12345`, `rw_hr / Hr#12345`, `rw_guest / Guest#12345`

> The scripts were written without a live Oracle instance, so the first run may show small
> compile errors. Run `SHOW ERRORS` in SQL*Plus, fix on your branch and open a pull request.

## Demo story (for the viva)
1. Login as `rw_hr` → *Simulate Changes* → set Ahmed Khan's salary 80,000 → 800,000.
2. Login as `rw_auditor` → *Suspicious Activity* shows the HIGH alert → *Before vs After*.
3. Login as `rw_admin` → *Record Recovery* → restore → salary is 80,000 again → check *Audit Logs*.

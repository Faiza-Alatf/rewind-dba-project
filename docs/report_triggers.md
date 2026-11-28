# Triggers and Suspicious-Activity Detection

*Mahnoor Sharif - Rewind: Database Time Machine & Recovery System*

## 1. Purpose

Rewind has to know what changed, who changed it and whether the change looks dangerous. This chapter describes
the audit triggers that record every change and the six rules that check each change for suspicious behaviour.
The code is in `sql/04_rewind_core.sql` (package `rewind_core`), `sql/05_audit_trigger.sql` (employees) and
`sql/10_departments_audit.sql` (departments).

## 2. How the audit trigger works

The trigger `trg_employees_audit` is defined as `AFTER INSERT OR UPDATE OR DELETE ON employees FOR EACH ROW`.
It is a **row-level** trigger: it fires once for every affected row, not once for the whole statement. A
statement that deletes 100 employees therefore produces 100 separate audit entries. The departments table has
the same kind of trigger, `trg_departments_audit`, which logs the column `DEPT_NAME`.

Inside the trigger, `:OLD` holds the row before the change and `:NEW` holds the row after it. For every column
(name, job title, salary, department, hire date, status) a small local procedure compares the two values and,
if they differ, calls `rewind_core.log_change` with the table, the record id, the operation and the old and new
value. For an `UPDATE` only the columns that really changed are logged. For an `INSERT` the old value is empty
and for a `DELETE` the new value is empty. All columns of one row share one `change_group`, a `SYS_GUID` value
created once per row. The recovery package uses it to restore a whole row in one step.

`log_change` writes a row into `audit_log` with the Oracle session user, the client host and the time. Two design
decisions protect the audit data:

- **Same transaction.** The trigger runs inside the transaction of the original statement. If the user issues
  `ROLLBACK`, the audit rows disappear together with the change, so the log never describes something that did
  not happen.
- **Internal package.** `rewind_core` is not granted to any user, so nobody can forge an audit entry by calling
  `log_change` directly.

The flag `rewind_core.g_restoring` handles restores. When an ADMIN restores data through `rewind_pkg`, the flag
is `TRUE`. `log_change` then stores the operation as `RESTORE` and skips the detection rules, so a restore never
raises an alert and is never counted as a user change.

## 3. Detection rules

After inserting the audit row, `log_change` calls `check_suspicious`. The current row is already in `audit_log`,
so rules that count rows automatically include the current change. When a rule matches, `flag` adds a row to
`suspicious_activity` with a severity and a reason text.

| # | Rule | Severity |
|---|---|---|
| 1 | Salary raised to 3 times the old value or more, or cut to 30 percent or less | HIGH |
| 2 | Change outside working hours (before 08:00, from 18:00, Saturday or Sunday) | MEDIUM |
| 3 | Change by a user without an HR or ADMIN application role | HIGH |
| 4 | Bulk modification: 10 rows changed by one user within 1 minute | MEDIUM |
| 5 | Same employee's salary changed 2 or more times on the same day | MEDIUM |
| 6 | Mass delete: 5 employees deleted by one user within 1 minute | HIGH |

Several design choices matter for correctness.

- **Once per row.** An audit row exists for every changed column. Rules 2, 3, 4 and 6 are evaluated only for the
  first logged column of a row, otherwise a six-column insert would raise six alerts.
- **One alert per burst.** Rules 4 and 6 count `DISTINCT change_group`, so they count rows and not columns, and
  they raise the alert only when the count is exactly 10 or 5. Each new row increases the count by one, so the
  limit is reached once. With a `>=` comparison a mass delete of 100 employees would raise 96 alerts and hide
  the real alert in noise; Rule 4 had the same problem with 12 rows (three alerts) until it was changed to `= 10`.
- **Employee rules and DEPARTMENTS.** Rules 1, 5 and 6 look only at employee data: Rule 1 reacts to the `SALARY`
  column, which exists only in `EMPLOYEES`, and Rules 5 and 6 filter on `table_name = 'EMPLOYEES'`. Rules 2, 3 and
  4 are generic: a bulk change is suspicious on any table, so department rows are counted by Rule 4.
- **Roles.** Rule 3 reads the table `app_users`. The demo user `RW_GUEST` has Oracle table privileges but no
  application role, which is exactly the case the rule detects.

## 4. Example

An HR user changes the salary of Ahmed Khan from 80,000 to 800,000. The trigger writes one audit row for the
`SALARY` column with the old value `80000.00` and the new value `800000.00`. `check_suspicious` sees that the new
salary is ten times the old one and raises a HIGH alert, *Salary increased by more than 200%*. If the change is
made at night, Rule 2 adds a MEDIUM alert for the same audit row. The auditor sees both alerts in the Suspicious
Activity screen and compares the values in Before vs After. An ADMIN then restores the old salary. The restore
runs with `g_restoring = TRUE`, so it is logged as `RESTORE` and raises no new alert.

## 5. Testing

The script `docs/rules_tests.sql` tests every rule with a positive case (the alert must appear) and a negative
case (it must not appear). Each check records a baseline, makes the change as the right user, checks the
severity and the reason text, prints PASS or FAIL and restores the data. The final run had 21 of 21 checks
passing, including the tests that one burst of 12 changes gives exactly one Rule 4 alert (R4c) and that
department changes do not trigger the employee rules (D1, D2). Rule 2 depends on the database clock, so its
test computes the expected result from the current time.

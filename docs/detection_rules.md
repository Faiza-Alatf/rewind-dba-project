# Suspicious-Activity Detection Rules

Rewind writes every change of an audited table (`EMPLOYEES`, `DEPARTMENTS`) into `audit_log` and then checks
the change against six rules. A rule that matches adds one row to `suspicious_activity` with a **severity**
(`LOW`, `MEDIUM` or `HIGH`) and a **reason** text. The ADMIN and AUDITOR roles see these rows in the view
`v_suspicious_details` and in the Suspicious Activity screen of the GUI.

All six rules are in one place: the procedure `check_suspicious` inside the package `rewind_core`
(`sql/04_rewind_core.sql`). The tests are in [`rules_tests.sql`](rules_tests.sql).

## The six rules

| # | What it checks | Severity | When an alert is raised | Example (reason text) | Procedure |
|---|---|---|---|---|---|
| 1 | Abnormal salary jump or drop | HIGH | An `UPDATE` of `SALARY` where the new value is **3 times the old value or more**, or **30 percent of the old value or less** | `Salary increased by more than 200% (130000.00 -> 400000.00)` or `Salary reduced by more than 70% (90000.00 -> 20000.00)` | `rewind_core.check_suspicious` (Rule 1 block) |
| 2 | Change outside working hours | MEDIUM | Any change (once per changed row) made **before 08:00, from 18:00, or on Saturday or Sunday** (database server time) | `Change made outside working hours` | `rewind_core.check_suspicious` (Rule 2 block) |
| 3 | Change by a user without an HR or ADMIN role | HIGH | Any change (once per changed row) by a user who has **no active HR or ADMIN role in `app_users`** (not listed, inactive, or only AUDITOR) | `Change made by user without HR/ADMIN role (RW_GUEST)` | `rewind_core.check_suspicious` (Rule 3 block), uses `rewind_core.can_edit` |
| 4 | Bulk modification | MEDIUM | **10 rows** changed by one user within **1 minute**. **One alert per burst:** the alert is raised when the count reaches exactly 10 (the 10th row); rows 11, 12, ... of the same burst raise nothing. **DEPARTMENTS rows are counted too.** Restore rows are not counted | `Bulk modification: 10 rows changed by RW_HR within 1 minute` | `rewind_core.check_suspicious` (Rule 4 block) |
| 5 | Same employee's salary changed twice in one day | MEDIUM | An `UPDATE` of `SALARY` of an employee when this is the **2nd or later salary update of that employee today** (the current change is counted) | `Salary of employee 104 changed 2 times today` | `rewind_core.check_suspicious` (Rule 5 block) |
| 6 | Mass delete | HIGH | **5 employees** deleted by one user within **1 minute**. The alert is raised when the count reaches exactly 5 (the 5th delete); further deletes of the same burst raise nothing. Only `EMPLOYEES` rows are counted | `Mass delete: 5+ employees deleted by RW_HR within 1 minute` | `rewind_core.check_suspicious` (Rule 6 block) |

## How a change reaches the rules

1. A user runs `INSERT`, `UPDATE` or `DELETE` on `EMPLOYEES` or `DEPARTMENTS`.
2. The row-level `AFTER` trigger (`trg_employees_audit` or `trg_departments_audit`) fires once for every
   affected row and calls `rewind_core.log_change` for every changed column, with the old and new value.
3. `log_change` inserts the row into `audit_log` (user, host, time, operation, old and new value).
4. Right after the insert, `log_change` calls `check_suspicious`. The current audit row is already in the
   table, so rules that count rows include the current change.
5. A matching rule calls `rewind_core.flag`, which inserts a row into `suspicious_activity`.

When an ADMIN restores data, `rewind_pkg` sets `rewind_core.g_restoring = TRUE`. `log_change` then stores the
operation as `RESTORE` and skips `check_suspicious`, so a restore never raises an alert.

## Details worth knowing

- **Once per row, not once per column.** An audit row is written for every changed column. Rules 2, 3, 4 and 6
  are checked only for the first logged column of a row (`p_first`), so a six-column `INSERT` or `DELETE` does
  not raise six alerts.
- **Rows, not columns.** Rules 4 and 6 count `DISTINCT change_group`. All columns of one row share one
  `change_group`.
- **One alert per burst (Rules 4 and 6).** The conditions are `v_cnt = 10` and `v_cnt = 5`, not `>=`. Every new
  row raises the count by exactly one, so the count reaches the limit only once. With `>=`, a mass delete of
  100 employees would raise 96 alerts and hide the real one.
  Limit of this design: if a user already has more changes than the limit inside the last minute when a new
  burst starts, no new alert is raised until the one-minute window has cleared. The first burst was flagged.
- **Which tables each rule looks at.** Rules 1, 5 and 6 are employee rules: Rule 1 reacts only to the `SALARY`
  column (which exists only in `EMPLOYEES`), and Rules 5 and 6 filter on `table_name = 'EMPLOYEES'`.
  Rules 2, 3 and 4 are generic and also see `DEPARTMENTS` changes.
- **Rule 2 depends on the clock.** The same change is flagged at night or on a weekend and not flagged on a
  weekday between 08:00 and 18:00.
- **Rule 5 counts the whole day.** It counts the employee's `UPDATE` rows of `SALARY` since midnight, including
  changes that were restored later.
- **Rule 3 and `RW_GUEST`.** `RW_GUEST` has the Oracle privileges of `rewind_hr_role` but is not listed in
  `app_users`. It can change data, and every change is flagged by Rule 3. This is what the rule detects.

## Where to find each part

| Part | Location |
|---|---|
| Rules, `flag`, `log_change` | `sql/04_rewind_core.sql` (package `rewind_core`) |
| Employees audit trigger | `sql/05_audit_trigger.sql` (`trg_employees_audit`) |
| Departments audit trigger | `sql/10_departments_audit.sql` (`trg_departments_audit`) |
| Table for alerts | `suspicious_activity` (`sql/02_tables.sql`); view `v_suspicious_details` |
| Tests | `docs/rules_tests.sql` |

-- =====================================================================
-- REWIND - docs/rules_tests.sql   (Day 5: unit tests for EVERY rule)
-- Rules in sql/04_rewind_core.sql (check_suspicious):
--   Rule 1  salary jump x3 or more / drop to 30 percent or less   HIGH
--   Rule 2  change outside working hours (08-18, Mon-Fri)         MEDIUM
--   Rule 3  change by a user without HR/ADMIN application role    HIGH
--   Rule 4  bulk modification, 10+ rows by one user in 1 minute   MEDIUM
--   Rule 5  same employee salary changed 2+ times on one day      MEDIUM
--   Rule 6  mass delete, 5+ employees by one user in 1 minute     HIGH
-- Every test has a positive case (flag must appear) and a negative case
-- (flag must NOT appear). Each check prints PASS or FAIL.
--
-- How to run (from the repo root, after scripts 01-07, 09 and 10):
--   sqlplus /nolog @docs\rules_tests.sql
-- Takes about 5 minutes: the 1-minute rules (4 and 6) need idle gaps.
--
-- Test data: temporary employees (ids derived from the audit sequence, so
-- they are new in every run) and employees 231-239, 241-250, 261-264,
-- 271-276 from the sample data. All data is restored or removed at the end.
-- Departments 91-95 are used only for the DEPARTMENTS check; departments
-- 60 and 70 (other team members' tests) are never touched.
-- Only rows created after a baseline id are checked, so older runs and
-- older flags never disturb the results.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK ON
COLUMN test      FORMAT A52
COLUMN expected  FORMAT 999
COLUMN actual    FORMAT 999
COLUMN result    FORMAT A6
COLUMN severity  FORMAT A8
COLUMN reason    FORMAT A62
COLUMN operation FORMAT A9
COLUMN changed_by FORMAT A10
COLUMN base_sus   NEW_VALUE base_sus   NOPRINT
COLUMN base_aud   NEW_VALUE base_aud   NOPRINT
COLUMN tbase      NEW_VALUE tbase      NOPRINT
COLUMN emp_before NEW_VALUE emp_before NOPRINT
SPOOL rules_tests_output.txt

-- =====================================================================
-- PART A: Rules 1, 2, 3, 5 and the DEPARTMENTS check (no waiting)
-- =====================================================================
PROMPT
PROMPT ===== PART A - SETUP: baselines, 4 temporary employees =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DELETE FROM rewind.departments WHERE dept_id BETWEEN 91 AND 95;
COMMIT;
SELECT NVL(MAX(sus_id), 0)   AS base_sus   FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud   FROM rewind.audit_log;
SELECT 100000 + NVL(MAX(audit_id), 0) AS tbase FROM rewind.audit_log;
SELECT COUNT(*) AS emp_before FROM rewind.employees;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
INSERT INTO rewind.employees(emp_id, emp_name, job_title, salary, dept_id)
  VALUES (&tbase + 1, 'Rule Test E1', 'Test Employee', 100000, 10);
INSERT INTO rewind.employees(emp_id, emp_name, job_title, salary, dept_id)
  VALUES (&tbase + 2, 'Rule Test E2', 'Test Employee', 100000, 10);
INSERT INTO rewind.employees(emp_id, emp_name, job_title, salary, dept_id)
  VALUES (&tbase + 3, 'Rule Test E3', 'Test Employee', 100000, 10);
INSERT INTO rewind.employees(emp_id, emp_name, job_title, salary, dept_id)
  VALUES (&tbase + 4, 'Rule Test E4', 'Test Employee', 100000, 10);
COMMIT;

PROMPT -- E1 salary 100000 -> 350000 (x3.5), E2 -> 20000 (to 20 percent), E3 -> 110000 (+10 percent)
PROMPT -- E4 salary 100000 -> 101000 (1st salary change of the day)
UPDATE rewind.employees SET salary = 350000 WHERE emp_id = &tbase + 1;
UPDATE rewind.employees SET salary = 20000  WHERE emp_id = &tbase + 2;
UPDATE rewind.employees SET salary = 110000 WHERE emp_id = &tbase + 3;
UPDATE rewind.employees SET salary = 101000 WHERE emp_id = &tbase + 4;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT
PROMPT ===== RULE 1 - salary jump / drop =====
PROMPT -- R1a POSITIVE: 100000 -> 350000 must raise HIGH Salary increased
SELECT 'R1a salary x3.5 -> HIGH increase flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 1
   AND s.severity = 'HIGH' AND s.reason LIKE 'Salary increased by more than 200%';

PROMPT -- R1b POSITIVE: 100000 -> 20000 must raise HIGH Salary reduced
SELECT 'R1b salary to 20 percent -> HIGH drop flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 2
   AND s.severity = 'HIGH' AND s.reason LIKE 'Salary reduced by more than 70%';

PROMPT -- R1c NEGATIVE: 100000 -> 110000 (+10 percent) must NOT raise a Rule 1 flag
SELECT 'R1c salary +10 percent -> no Rule 1 flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 3
   AND s.reason LIKE 'Salary % by more than %';

PROMPT
PROMPT ===== RULE 5 - same employee salary changed twice in one day =====
PROMPT -- R5a NEGATIVE: E1, E2, E3 each changed ONCE today -> no times today flag
SELECT 'R5a one salary change -> no Rule 5 flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES'
   AND a.record_id IN (&tbase + 1, &tbase + 2, &tbase + 3)
   AND s.reason LIKE '%times today';

PROMPT -- R5b NEGATIVE: E4 first salary change of the day -> no flag yet
SELECT 'R5b E4 1st salary change -> no flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 4
   AND s.reason LIKE '%times today';

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- E4 2nd salary change (101000 -> 102000), E1 job title change by HR (for Rule 2 and 3)
UPDATE rewind.employees SET salary = 102000 WHERE emp_id = &tbase + 4;
UPDATE rewind.employees SET job_title = 'HR Edit' WHERE emp_id = &tbase + 1;
COMMIT;

CONNECT rw_guest/"Guest#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- E1 job title change by RW_GUEST (has table privileges but no application role)
UPDATE rewind.employees SET job_title = 'Guest Edit' WHERE emp_id = &tbase + 1;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- R5c POSITIVE: E4 2nd salary change must raise ONE MEDIUM flag
SELECT 'R5c E4 2nd salary change -> MEDIUM flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 4
   AND s.severity = 'MEDIUM' AND s.reason = 'Salary of employee ' || (&tbase + 4) || ' changed 2 times today';

PROMPT
PROMPT ===== RULE 2 - change outside working hours =====
PROMPT -- Depends on the clock: flag expected only at night, Sat or Sun. Run once at night
PROMPT -- (positive case) and once on a weekday 08-18 (negative case) to see both.
SELECT 'R2 HR change: flag only outside 08-18 Mon-Fri' AS test,
       CASE WHEN TO_NUMBER(TO_CHAR(SYSDATE, 'HH24')) < 8 OR TO_NUMBER(TO_CHAR(SYSDATE, 'HH24')) >= 18
                 OR TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN')
            THEN 1 ELSE 0 END AS expected,
       COUNT(*) AS actual,
       CASE WHEN COUNT(*) = CASE WHEN TO_NUMBER(TO_CHAR(SYSDATE, 'HH24')) < 8 OR TO_NUMBER(TO_CHAR(SYSDATE, 'HH24')) >= 18
                 OR TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT', 'SUN')
            THEN 1 ELSE 0 END THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 1
   AND a.column_name = 'JOB_TITLE' AND a.changed_by = 'RW_HR'
   AND s.severity = 'MEDIUM' AND s.reason = 'Change made outside working hours';

PROMPT
PROMPT ===== RULE 3 - user without HR/ADMIN application role =====
PROMPT -- R3a POSITIVE: RW_GUEST change must raise HIGH flag naming RW_GUEST
SELECT 'R3a RW_GUEST change -> HIGH no-role flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES' AND a.record_id = &tbase + 1
   AND a.changed_by = 'RW_GUEST' AND s.severity = 'HIGH'
   AND s.reason = 'Change made by user without HR/ADMIN role (RW_GUEST)';

PROMPT -- R3b NEGATIVE: none of the RW_HR changes may carry a no-role flag
SELECT 'R3b RW_HR changes -> no no-role flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'EMPLOYEES'
   AND a.record_id BETWEEN &tbase + 1 AND &tbase + 4
   AND a.changed_by = 'RW_HR' AND s.reason LIKE 'Change made by user without HR/ADMIN role%';

PROMPT
PROMPT ===== DEPARTMENTS audit rows must NOT count as employee activity =====
PROMPT -- ADMIN adds departments 91-95, renames 91 twice, deletes all five within seconds
INSERT INTO rewind.departments VALUES (91, 'Rule Test A');
INSERT INTO rewind.departments VALUES (92, 'Rule Test B');
INSERT INTO rewind.departments VALUES (93, 'Rule Test C');
INSERT INTO rewind.departments VALUES (94, 'Rule Test D');
INSERT INTO rewind.departments VALUES (95, 'Rule Test E');
UPDATE rewind.departments SET dept_name = 'Rule Test A1' WHERE dept_id = 91;
UPDATE rewind.departments SET dept_name = 'Rule Test A2' WHERE dept_id = 91;
DELETE FROM rewind.departments WHERE dept_id BETWEEN 91 AND 95;
COMMIT;

PROMPT -- D1 NEGATIVE: 5 department deletes must NOT raise Mass delete (employees only)
SELECT 'D1 5 dept deletes -> no Mass delete flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'DEPARTMENTS' AND s.reason LIKE 'Mass delete%';

PROMPT -- D2 NEGATIVE: 2 renames of one department must NOT raise Rule 5 or Rule 1
SELECT 'D2 dept renamed twice -> no Rule 5 / Rule 1' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus AND a.table_name = 'DEPARTMENTS'
   AND (s.reason LIKE '%times today' OR s.reason LIKE 'Salary %');

PROMPT
PROMPT ===== PART A DETAILS: every flag raised above (severity and reason) =====
SELECT s.sus_id, a.table_name, a.record_id, a.changed_by, s.severity, s.reason
  FROM rewind.suspicious_activity s JOIN rewind.audit_log a ON a.audit_id = s.audit_id
 WHERE s.sus_id > &base_sus
 ORDER BY s.sus_id;

PROMPT -- Cleanup of Part A: HR deletes the 4 temporary employees
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DELETE FROM rewind.employees WHERE emp_id BETWEEN &tbase + 1 AND &tbase + 4;
COMMIT;

-- =====================================================================
-- PART B: Rule 4 (bulk modification)
-- =====================================================================
PROMPT
PROMPT ===== RULE 4 - bulk modification (10+ rows in 1 minute) =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- Waiting 61 seconds so earlier changes leave the 1-minute window
EXEC DBMS_SESSION.SLEEP(61)
SELECT NVL(MAX(sus_id), 0)   AS base_sus FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- R4a NEGATIVE case: HR changes the job title of 9 employees (231-239)
UPDATE rewind.employees SET job_title = SUBSTR(job_title || ' T', 1, 50) WHERE emp_id BETWEEN 231 AND 239;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT 'R4a 9 rows in 1 minute -> no Bulk flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.reason LIKE 'Bulk modification%';

PROMPT -- Cleanup: ADMIN restores the 9 job titles
BEGIN
  FOR r IN (SELECT audit_id FROM rewind.audit_log
             WHERE table_name = 'EMPLOYEES' AND record_id BETWEEN 231 AND 239
               AND operation = 'UPDATE' AND column_name = 'JOB_TITLE'
               AND is_restored = 'N' AND audit_id > &base_aud
             ORDER BY audit_id DESC) LOOP
    rewind.rewind_pkg.restore_value(r.audit_id);
  END LOOP;
END;
/
PROMPT -- Waiting 61 seconds before the positive case
EXEC DBMS_SESSION.SLEEP(61)
SELECT NVL(MAX(sus_id), 0)   AS base_sus FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- R4b POSITIVE case: HR changes the job title of 10 employees (241-250)
UPDATE rewind.employees SET job_title = SUBSTR(job_title || ' T', 1, 50) WHERE emp_id BETWEEN 241 AND 250;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT 'R4b 10 rows in 1 minute -> ONE MEDIUM Bulk flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.severity = 'MEDIUM'
   AND s.reason = 'Bulk modification: 10 rows changed by RW_HR within 1 minute';

PROMPT -- Details of the Rule 4 flag
SELECT s.sus_id, s.severity, s.reason
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.reason LIKE 'Bulk modification%';

PROMPT -- Cleanup: ADMIN restores the 10 job titles
BEGIN
  FOR r IN (SELECT audit_id FROM rewind.audit_log
             WHERE table_name = 'EMPLOYEES' AND record_id BETWEEN 241 AND 250
               AND operation = 'UPDATE' AND column_name = 'JOB_TITLE'
               AND is_restored = 'N' AND audit_id > &base_aud
             ORDER BY audit_id DESC) LOOP
    rewind.rewind_pkg.restore_value(r.audit_id);
  END LOOP;
END;
/

-- =====================================================================
-- PART C: Rule 6 (mass delete)
-- =====================================================================
PROMPT
PROMPT ===== RULE 6 - mass delete (5+ employees in 1 minute) =====
PROMPT -- Waiting 61 seconds so earlier changes leave the 1-minute window
EXEC DBMS_SESSION.SLEEP(61)
SELECT NVL(MAX(sus_id), 0)   AS base_sus FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- R6a NEGATIVE case: HR deletes 4 employees (261-264)
DELETE FROM rewind.employees WHERE emp_id BETWEEN 261 AND 264;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT 'R6a 4 deletes in 1 minute -> no Mass flag' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.reason LIKE 'Mass delete%';

PROMPT -- Cleanup: ADMIN restores employees 261-264
BEGIN
  FOR g IN (SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) AS change_group
              FROM rewind.audit_log
             WHERE table_name = 'EMPLOYEES' AND operation = 'DELETE'
               AND is_restored = 'N' AND record_id BETWEEN 261 AND 264
               AND audit_id > &base_aud
             GROUP BY record_id) LOOP
    rewind.rewind_pkg.restore_deleted(g.change_group);
  END LOOP;
END;
/
PROMPT -- Waiting 61 seconds before the positive case
EXEC DBMS_SESSION.SLEEP(61)
SELECT NVL(MAX(sus_id), 0)   AS base_sus FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- R6b POSITIVE case: HR deletes 6 employees (271-276)
DELETE FROM rewind.employees WHERE emp_id BETWEEN 271 AND 276;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT 'R6b 6 deletes in 1 minute -> ONE HIGH Mass flag' AS test, 1 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.severity = 'HIGH' AND s.reason LIKE 'Mass delete%';

PROMPT -- Details of the Rule 6 flag
SELECT s.sus_id, s.severity, s.reason
  FROM rewind.suspicious_activity s
 WHERE s.sus_id > &base_sus AND s.reason LIKE 'Mass delete%';

PROMPT -- R6c: employees deleted before the flag was raised (expect 4)
SELECT 'R6c deleted before the flag' AS test, 4 AS expected, COUNT(DISTINCT a.record_id) AS actual,
       CASE WHEN COUNT(DISTINCT a.record_id) = 4 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.audit_log a
 WHERE a.operation = 'DELETE' AND a.table_name = 'EMPLOYEES'
   AND a.record_id BETWEEN 271 AND 276 AND a.is_restored = 'N'
   AND a.audit_id > &base_aud
   AND a.audit_id < (SELECT MAX(s.audit_id) FROM rewind.suspicious_activity s
                      WHERE s.reason LIKE 'Mass delete%' AND s.sus_id > &base_sus);

PROMPT -- Cleanup: ADMIN restores employees 271-276
BEGIN
  FOR g IN (SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) AS change_group
              FROM rewind.audit_log
             WHERE table_name = 'EMPLOYEES' AND operation = 'DELETE'
               AND is_restored = 'N' AND record_id BETWEEN 271 AND 276
               AND audit_id > &base_aud
             GROUP BY record_id) LOOP
    rewind.rewind_pkg.restore_deleted(g.change_group);
  END LOOP;
END;
/

-- =====================================================================
-- FINAL: all test data must be back to normal
-- =====================================================================
PROMPT
PROMPT ===== FINAL CHECKS =====
SELECT 'F1 employees count same as before the tests' AS test, &emp_before AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = &emp_before THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.employees;
SELECT 'F2 test departments 91-95 removed' AS test, 0 AS expected, COUNT(*) AS actual,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
  FROM rewind.departments WHERE dept_id BETWEEN 91 AND 95;
SPOOL OFF

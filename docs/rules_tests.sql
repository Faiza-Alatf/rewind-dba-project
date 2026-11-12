-- =====================================================================
-- REWIND - docs/rules_tests.sql   (v2, after review)
-- Tests for the two new suspicious-activity rules:
--   Rule 5: same employee's salary changed 2+ times in one day  (MEDIUM)
--   Rule 6: mass delete, 5+ employees by one user in 1 minute   (HIGH, ONE flag)
-- Run from the repo root AFTER 01-07 and 09:
--   sqlplus /nolog @docs/rules_tests.sql
-- Flags/audit rows of earlier runs are ignored: every check only looks at rows
-- created after a baseline id taken at the start of each test.
-- Note: Rule 5 counts salary updates of the WHOLE day. If this script is run
-- again on the same day, employee 104 already has salary updates from the
-- earlier run, so the 1st change of a re-run can be flagged too. The LAST
-- Rule 5 flag (2nd change) is the one that is checked.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK ON
COLUMN reason FORMAT A60
COLUMN severity FORMAT A8
COLUMN changed_by FORMAT A10
COLUMN first_reason FORMAT A60
COLUMN base_sus NEW_VALUE base_sus NOPRINT
COLUMN base_aud NEW_VALUE base_aud NOPRINT
SPOOL rules_tests_output.txt

-- ---------------------------------------------------------------------
PROMPT ===== TEST 9 (Rule 5): salary of employee 104 changed twice today =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT NVL(MAX(sus_id), 0) AS base_sus FROM rewind.suspicious_activity;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- 1st salary change (95000 -> 96000)
UPDATE rewind.employees SET salary = 96000 WHERE emp_id = 104;
COMMIT;

PROMPT -- 2nd salary change (96000 -> 97000): must raise the MEDIUM Rule 5 flag
UPDATE rewind.employees SET salary = 97000 WHERE emp_id = 104;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- All Rule 5 flags of THIS run for employee 104
SELECT sus_id, severity, reason, changed_by
  FROM rewind.v_suspicious_details
 WHERE record_id = 104 AND reason LIKE '%times today%' AND sus_id > &base_sus
 ORDER BY sus_id;

PROMPT -- LATEST Rule 5 flag (belongs to the 2nd change, expect MEDIUM)
SELECT sus_id, severity, reason, changed_by
  FROM rewind.v_suspicious_details
 WHERE record_id = 104 AND reason LIKE '%times today%' AND sus_id > &base_sus
 ORDER BY sus_id DESC
 FETCH FIRST 1 ROW ONLY;

PROMPT -- Cleanup: ADMIN restores both changes (latest first)
DECLARE
  v_sal NUMBER;
BEGIN
  FOR r IN (SELECT audit_id FROM rewind.audit_log
             WHERE record_id = 104 AND table_name = 'EMPLOYEES'
               AND column_name = 'SALARY' AND operation = 'UPDATE'
               AND is_restored = 'N'
             ORDER BY audit_id DESC) LOOP
    rewind.rewind_pkg.restore_value(r.audit_id);
  END LOOP;
  SELECT salary INTO v_sal FROM rewind.employees WHERE emp_id = 104;
  DBMS_OUTPUT.PUT_LINE('Salary of employee 104 after restore = ' || v_sal || '  (expected 95000) -> '
                       || CASE WHEN v_sal = 95000 THEN 'PASS' ELSE 'FAIL' END);
END;
/

-- ---------------------------------------------------------------------
PROMPT ===== TEST 10 (Rule 6): HR deletes employees 201-300 in one go =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT NVL(MAX(sus_id), 0)   AS base_sus FROM rewind.suspicious_activity;
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

PROMPT -- Waiting 61 seconds so deletes of any earlier run are outside the 1-minute window
EXEC DBMS_SESSION.SLEEP(61)

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
PROMPT -- Employees 201-300 before delete (expect 100)
SELECT COUNT(*) AS emp_201_300_before FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;

DELETE FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- Employees 201-300 after delete (expect 0)
SELECT COUNT(*) AS emp_201_300_after FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;

PROMPT -- Mass delete flags of THIS run (expect exactly 1, severity HIGH)
SELECT severity, COUNT(*) AS mass_delete_flags, MAX(reason) AS first_reason
  FROM rewind.suspicious_activity
 WHERE reason LIKE 'Mass delete%' AND sus_id > &base_sus
 GROUP BY severity;

PROMPT -- Employees deleted before the flag was raised (expect 4)
SELECT COUNT(DISTINCT a.record_id) AS deleted_before_flag
  FROM rewind.audit_log a
 WHERE a.operation = 'DELETE'
   AND a.table_name = 'EMPLOYEES'
   AND a.record_id BETWEEN 201 AND 300
   AND a.is_restored = 'N'
   AND a.audit_id > &base_aud
   AND a.audit_id < (
       SELECT MAX(s.audit_id)
         FROM rewind.suspicious_activity s
        WHERE s.reason LIKE 'Mass delete%'
          AND s.sus_id > &base_sus
   );

-- ---------------------------------------------------------------------
PROMPT ===== CLEANUP: ADMIN restores all deleted employees 201-300 =====
DECLARE
  v_cnt NUMBER;
BEGIN
  -- latest un-restored DELETE group of every employee 201-300
  FOR g IN (SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) AS change_group
              FROM rewind.audit_log
             WHERE table_name = 'EMPLOYEES' AND operation = 'DELETE'
               AND is_restored = 'N' AND record_id BETWEEN 201 AND 300
             GROUP BY record_id) LOOP
    rewind.rewind_pkg.restore_deleted(g.change_group);
  END LOOP;
  SELECT COUNT(*) INTO v_cnt FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;
  DBMS_OUTPUT.PUT_LINE('Employees 201-300 after restore = ' || v_cnt || '  (expected 100) -> '
                       || CASE WHEN v_cnt = 100 THEN 'PASS' ELSE 'FAIL' END);
END;
/

SPOOL OFF

-- =====================================================================
-- REWIND - docs/rules_tests.sql
-- Tests for the two new suspicious-activity rules:
--   Rule 5: same employee's salary changed 2+ times in one day  (MEDIUM)
--   Rule 6: mass delete, 5+ employees by one user in 1 minute   (HIGH)
-- Run AFTER 01-07 and 09 (employees 201-300 must exist).
-- Edit the connect strings if your service name is different.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200
COLUMN reason FORMAT A70
COLUMN severity FORMAT A8

-- ---------------------------------------------------------------------
PROMPT ===== TEST 9: salary of employee 104 changed twice today -> 2nd change flagged =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- 1st salary change (95000 -> 96000): must NOT trigger Rule 5
UPDATE rewind.employees SET salary = 96000 WHERE emp_id = 104;
COMMIT;

PROMPT -- 2nd salary change (96000 -> 97000): must trigger Rule 5 (MEDIUM)
UPDATE rewind.employees SET salary = 97000 WHERE emp_id = 104;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- Flags for employee 104 (expect: 'changed 2 times today', MEDIUM)
SELECT sus_id, severity, reason, changed_by
  FROM rewind.v_suspicious_details
 WHERE record_id = 104 AND reason LIKE '%times today%'
 ORDER BY sus_id;

PROMPT -- Cleanup: ADMIN restores both changes (latest first) so salary goes back to 95000
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
  DBMS_OUTPUT.PUT_LINE('Salary of 104 after restore = ' || v_sal || '  (expected 95000)');
END;
/

-- ---------------------------------------------------------------------
PROMPT ===== TEST 10: HR deletes employees 201-300 in one go -> mass delete flagged =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- Employees before delete (expect 100)
SELECT COUNT(*) AS emp_201_300_before FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;

DELETE FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

PROMPT -- Employees after delete (expect 0)
SELECT COUNT(*) AS emp_201_300_after FROM rewind.employees WHERE emp_id BETWEEN 201 AND 300;

PROMPT -- Mass delete flags (expect: first flag at the 5th deleted employee, severity HIGH)
SELECT severity, COUNT(*) AS flags, MIN(reason) AS first_reason
  FROM rewind.v_suspicious_details
 WHERE reason LIKE 'Mass delete%'
 GROUP BY severity;

PROMPT -- Rows 1-4 must NOT have a mass-delete flag (expect 4 distinct employees without flag)
SELECT COUNT(DISTINCT a.record_id) AS deleted_without_flag
  FROM rewind.audit_log a
 WHERE a.operation = 'DELETE' AND a.table_name = 'EMPLOYEES'
   AND a.record_id BETWEEN 201 AND 300 AND a.is_restored = 'N'
   AND NOT EXISTS (SELECT 1 FROM rewind.suspicious_activity s
                    JOIN rewind.audit_log b ON b.audit_id = s.audit_id
                   WHERE b.record_id = a.record_id AND b.operation = 'DELETE'
                     AND s.reason LIKE 'Mass delete%');

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
  DBMS_OUTPUT.PUT_LINE('Employees 201-300 after restore = ' || v_cnt || '  (expected 100)');
END;
/

-- =====================================================================
-- REWIND - 08_tests.sql
-- Run from the sql/ folder:   sqlplus /nolog @08_tests.sql
-- Edit the connect strings if your service name is different.
-- Output is spooled to 08_tests_output.log (attach it to the PR).
--
-- TEST OVERVIEW AND EXPECTED RESULTS
--  1  HR sets salary 80000 -> 800000 (emp 101)       -> change recorded, HIGH flag
--  2  HR calls restore_value                          -> ORA-20001 (denied)
--  3  ADMIN restore_value                             -> salary = 80000
--  4  HR deletes emp 115, ADMIN restore_deleted       -> employee is back
--  5  Unregistered RW_GUEST updates data              -> flagged HIGH
--  6  AUDITOR sees latest 10 flags, cannot restore    -> ORA-20001
--  7  Latest 10 history rows of emp 101               -> list of audit rows
--  8  HR inserts, ADMIN restore_inserted              -> 0 rows, flag Y, SUCCESS
--  9  HR calls restore_inserted                       -> ORA-20001
-- 10  restore_change_group on UPDATE group (2 cols)   -> both columns restored
-- 11  restore_change_group on INSERT group            -> employee removed
-- 12  restore_change_group on DELETE group            -> employee is back
-- 13  Unknown change group                            -> ORA-20010 + 1 FAILED row
-- 14  Atomicity: FK error during UPDATE-group restore -> ORA-02291, nothing
--     half-restored, 2 rows still 'N', 0 RESTORE rows, exactly 1 FAILED row
-- 15  Restoring an already-restored INSERT group      -> ORA-20004, exactly 1
--     new FAILED row
-- 16  Caller ROLLBACK after a successful group restore -> data, audit flags,
--     RESTORE rows and recovery_log all return to the pre-restore state;
--     the group can still be restored afterwards
--
-- REPEATABILITY: Tests 14, 15 and 16 use FIXED test IDs (emp 197/198/199,
-- dept 99), look only at audit rows newer than a baseline audit_id, and
-- clean up only rows matching BOTH the test ID and the test name.
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET VERIFY OFF
COLUMN reason FORMAT A70
SPOOL 08_tests_output.log

PROMPT ===== TEST 1: HR makes a mistake (salary 80,000 -> 800,000) =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

UPDATE rewind.employees
SET salary = 800000
WHERE emp_id = 101;

COMMIT;


PROMPT ===== TEST 2: HR tries to restore -> must be DENIED (ORA-20001) =====

BEGIN
  rewind.rewind_pkg.restore_value(1);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/


PROMPT ===== TEST 3: ADMIN restores the old salary =====

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_id  NUMBER;
  v_sal NUMBER;
BEGIN
  SELECT MAX(audit_id)
    INTO v_id
    FROM rewind.audit_log
   WHERE record_id = 101
     AND column_name = 'SALARY'
     AND operation = 'UPDATE'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_value(v_id);

  SELECT salary
    INTO v_sal
    FROM rewind.employees
   WHERE emp_id = 101;

  DBMS_OUTPUT.PUT_LINE(
    'Salary after restore = ' || v_sal || ' (expected 80000)'
  );
END;
/


PROMPT ===== TEST 4: HR deletes an employee, ADMIN brings it back =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DELETE FROM rewind.employees
WHERE emp_id = 115;

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_group VARCHAR2(32);
  v_name  VARCHAR2(80);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE record_id = 115
     AND operation = 'DELETE'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_deleted(v_group);

  SELECT emp_name
    INTO v_name
    FROM rewind.employees
   WHERE emp_id = 115;

  DBMS_OUTPUT.PUT_LINE('Employee 115 is back: ' || v_name);
END;
/


PROMPT ===== TEST 5: unregistered user (RW_GUEST) changes data -> flagged =====

CONNECT rw_guest/"Guest#12345"@//localhost:1521/XEPDB1

UPDATE rewind.employees
SET job_title = 'Temp Title'
WHERE emp_id = 102;

COMMIT;


PROMPT ===== TEST 6: AUDITOR reviews latest 10 suspicious flags and tries to restore =====

CONNECT rw_auditor/"Auditor#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

SELECT sus_id, severity, reason, changed_by
FROM rewind.v_suspicious_details
ORDER BY sus_id DESC
FETCH FIRST 10 ROWS ONLY;

BEGIN
  rewind.rewind_pkg.restore_value(1);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/


PROMPT ===== TEST 7: latest 10 history rows of employee 101 =====

SELECT audit_id,
       operation,
       column_name,
       old_value,
       new_value,
       changed_by,
       TO_CHAR(changed_on, 'YYYY-MM-DD HH24:MI:SS') AS changed_on
FROM rewind.v_change_history
WHERE record_id = 101
  AND table_name = 'EMPLOYEES'
ORDER BY audit_id DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT ===== TEST 8: HR inserts a new employee, ADMIN undoes the INSERT =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

-- Pick the next free employee ID.
COLUMN new_id NEW_VALUE v_new_id NOPRINT

SELECT NVL(MAX(emp_id), 0) + 1 AS new_id
FROM rewind.employees;

INSERT INTO rewind.employees
VALUES (
  &v_new_id,
  'Test Person',
  'Tester',
  50000,
  30,
  SYSDATE,
  'ACTIVE'
);

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_group  VARCHAR2(32);
  v_cnt    NUMBER;
  v_flag   VARCHAR2(1);
  v_status VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE record_id = &v_new_id
     AND operation = 'INSERT'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_inserted(v_group);

  SELECT COUNT(*)
    INTO v_cnt
    FROM rewind.employees
   WHERE emp_id = &v_new_id;

  DBMS_OUTPUT.PUT_LINE(
    'Employee ' || &v_new_id ||
    ' rows after undo = ' || v_cnt || ' (expected 0)'
  );

  -- All audit rows of the INSERT group must be flagged as restored.
  SELECT MIN(is_restored)
    INTO v_flag
    FROM rewind.audit_log
   WHERE change_group = v_group
     AND operation = 'INSERT';

  DBMS_OUTPUT.PUT_LINE(
    'audit_log.is_restored = ' || v_flag || ' (expected Y)'
  );

  -- Newest recovery_log row of this group must be SUCCESS.
  SELECT status
    INTO v_status
    FROM (
      SELECT status
      FROM rewind.recovery_log
      WHERE change_group = v_group
      ORDER BY recovery_id DESC
    )
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE(
    'recovery_log.status = ' || v_status || ' (expected SUCCESS)'
  );
END;
/


PROMPT ===== TEST 9: HR tries restore_inserted -> must be DENIED (ORA-20001) =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

BEGIN
  -- Admin check runs first, so any group ID is enough here.
  rewind.rewind_pkg.restore_inserted('DUMMY_GROUP');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/


PROMPT ===== TEST 10: restore_change_group on an UPDATE group (2 columns) =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

-- Employee 103 starts as Accountant / 70000 (sample data).
UPDATE rewind.employees
SET salary = 71000,
    job_title = 'Senior Accountant'
WHERE emp_id = 103;

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_group   VARCHAR2(32);
  v_sal     NUMBER;
  v_title   VARCHAR2(50);
  v_pending NUMBER;
  v_status  VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE record_id = 103
     AND operation = 'UPDATE'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT salary, job_title
    INTO v_sal, v_title
    FROM rewind.employees
   WHERE emp_id = 103;

  DBMS_OUTPUT.PUT_LINE(
    'Employee 103 salary = ' || v_sal || ' (expected 70000)'
  );

  DBMS_OUTPUT.PUT_LINE(
    'Employee 103 job_title = ' || v_title || ' (expected Accountant)'
  );

  SELECT COUNT(*)
    INTO v_pending
    FROM rewind.audit_log
   WHERE change_group = v_group
     AND is_restored = 'N';

  DBMS_OUTPUT.PUT_LINE(
    'audit_log rows not restored = ' || v_pending || ' (expected 0)'
  );

  SELECT status
    INTO v_status
    FROM (
      SELECT status
      FROM rewind.recovery_log
      WHERE change_group = v_group
      ORDER BY recovery_id DESC
    )
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE(
    'recovery_log.status = ' || v_status || ' (expected SUCCESS)'
  );
END;
/

-- restore_change_group leaves transaction control to its caller.
COMMIT;


PROMPT ===== TEST 11: restore_change_group on an INSERT group =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

COLUMN ins_id NEW_VALUE v_ins_id NOPRINT

SELECT NVL(MAX(emp_id), 0) + 1 AS ins_id
FROM rewind.employees;

INSERT INTO rewind.employees
VALUES (
  &v_ins_id,
  'Group Insert Test',
  'Tester',
  50000,
  30,
  SYSDATE,
  'ACTIVE'
);

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_group   VARCHAR2(32);
  v_cnt     NUMBER;
  v_pending NUMBER;
  v_status  VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE record_id = &v_ins_id
     AND operation = 'INSERT'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT COUNT(*)
    INTO v_cnt
    FROM rewind.employees
   WHERE emp_id = &v_ins_id;

  DBMS_OUTPUT.PUT_LINE(
    'Employee ' || &v_ins_id ||
    ' rows after undo = ' || v_cnt || ' (expected 0)'
  );

  SELECT COUNT(*)
    INTO v_pending
    FROM rewind.audit_log
   WHERE change_group = v_group
     AND is_restored = 'N';

  DBMS_OUTPUT.PUT_LINE(
    'audit_log rows not restored = ' || v_pending || ' (expected 0)'
  );

  SELECT status
    INTO v_status
    FROM (
      SELECT status
      FROM rewind.recovery_log
      WHERE change_group = v_group
      ORDER BY recovery_id DESC
    )
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE(
    'recovery_log.status = ' || v_status || ' (expected SUCCESS)'
  );
END;
/

-- Commit the successful group restoration.
COMMIT;


PROMPT ===== TEST 12: restore_change_group on a DELETE group =====

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

-- Employee 112 is Nida Hassan / 48000 (sample data).
DELETE FROM rewind.employees
WHERE emp_id = 112;

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_group   VARCHAR2(32);
  v_name    VARCHAR2(80);
  v_sal     NUMBER;
  v_pending NUMBER;
  v_status  VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE record_id = 112
     AND operation = 'DELETE'
     AND is_restored = 'N';

  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT emp_name, salary
    INTO v_name, v_sal
    FROM rewind.employees
   WHERE emp_id = 112;

  DBMS_OUTPUT.PUT_LINE(
    'Employee 112 is back: ' || v_name || ' / ' || v_sal ||
    ' (expected Nida Hassan / 48000)'
  );

  SELECT COUNT(*)
    INTO v_pending
    FROM rewind.audit_log
   WHERE change_group = v_group
     AND is_restored = 'N';

  DBMS_OUTPUT.PUT_LINE(
    'audit_log rows not restored = ' || v_pending || ' (expected 0)'
  );

  SELECT status
    INTO v_status
    FROM (
      SELECT status
      FROM rewind.recovery_log
      WHERE change_group = v_group
      ORDER BY recovery_id DESC
    )
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE(
    'recovery_log.status = ' || v_status || ' (expected SUCCESS)'
  );
END;
/

-- Commit the successful group restoration.
COMMIT;


PROMPT ===== TEST 13: unknown change group -> ORA-20010 and a FAILED row =====

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DECLARE
  v_status VARCHAR2(10);
BEGIN
  BEGIN
    rewind.rewind_pkg.restore_change_group('NO_SUCH_GROUP');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
  END;

  SELECT status
    INTO v_status
    FROM (
      SELECT status
      FROM rewind.recovery_log
      WHERE change_group = 'NO_SUCH_GROUP'
      ORDER BY recovery_id DESC
    )
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE(
    'recovery_log.status = ' || v_status || ' (expected FAILED)'
  );
END;
/


PROMPT ===== TEST 14: atomicity - FK error while restoring an UPDATE group =====

-- Fixed test IDs: employee 198, department 99.
-- A dedicated department is created, the employee is moved out of it by an
-- UPDATE, then the department is deleted. Restoring the old dept_id must
-- fail with ORA-02291 without partially restoring any column.

DEFINE t14_emp  = 198
DEFINE t14_dept = 99

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

-- Pre-cleanup: only rows that match BOTH the test id and the test name.
DELETE FROM rewind.employees
 WHERE emp_id = &t14_emp AND emp_name = 'Atomicity Test';

DELETE FROM rewind.departments
 WHERE dept_id = &t14_dept AND dept_name = 'Test Dept 14 Atomicity';

COMMIT;

-- Baseline: only audit rows created after this point belong to this run.
COLUMN base_aud NEW_VALUE v_base_aud NOPRINT
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

INSERT INTO rewind.departments
VALUES (&t14_dept, 'Test Dept 14 Atomicity');

COMMIT;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

INSERT INTO rewind.employees
VALUES (&t14_emp, 'Atomicity Test', 'Tester', 50000, &t14_dept, SYSDATE, 'ACTIVE');

COMMIT;

-- One UPDATE group with two audit rows: SALARY and DEPT_ID.
UPDATE rewind.employees
   SET salary  = 55000,
       dept_id = 30
 WHERE emp_id = &t14_emp;

COMMIT;

-- Delete the original department to create the FK failure.
CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON

DELETE FROM rewind.departments
 WHERE dept_id = &t14_dept
   AND dept_name = 'Test Dept 14 Atomicity';

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

DECLARE
  v_group        VARCHAR2(32);
  v_sal          NUMBER;
  v_dept         NUMBER;
  v_not_restored NUMBER;
  v_restore_rows NUMBER;
  v_failed       NUMBER;
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE table_name  = 'EMPLOYEES'
     AND record_id   = &t14_emp
     AND operation   = 'UPDATE'
     AND is_restored = 'N'
     AND audit_id    > &v_base_aud;

  BEGIN
    rewind.rewind_pkg.restore_change_group(v_group);
    DBMS_OUTPUT.PUT_LINE('ERROR: restore unexpectedly succeeded');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
  END;

  SELECT salary, dept_id INTO v_sal, v_dept
    FROM rewind.employees WHERE emp_id = &t14_emp;

  DBMS_OUTPUT.PUT_LINE('salary = ' || v_sal || ' (expected 55000, NOT back to 50000)');
  DBMS_OUTPUT.PUT_LINE('dept_id = ' || v_dept || ' (expected 30)');

  SELECT COUNT(*) INTO v_not_restored
    FROM rewind.audit_log
   WHERE change_group = v_group AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('audit_log rows still not restored = ' || v_not_restored || ' (expected 2)');

  SELECT COUNT(*) INTO v_restore_rows
    FROM rewind.audit_log
   WHERE table_name = 'EMPLOYEES'
     AND record_id  = &t14_emp
     AND operation  = 'RESTORE'
     AND audit_id   > &v_base_aud;
  DBMS_OUTPUT.PUT_LINE('new RESTORE rows = ' || v_restore_rows || ' (expected 0)');

  SELECT COUNT(*) INTO v_failed
    FROM rewind.recovery_log
   WHERE change_group = v_group AND status = 'FAILED';
  DBMS_OUTPUT.PUT_LINE('FAILED rows for this group = ' || v_failed || ' (expected exactly 1)');
END;
/

PROMPT --- Test 14 cleanup (only the test employee / department) ---

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1

DELETE FROM rewind.employees
 WHERE emp_id = &t14_emp AND emp_name = 'Atomicity Test';

DELETE FROM rewind.departments
 WHERE dept_id = &t14_dept AND dept_name = 'Test Dept 14 Atomicity';

COMMIT;


PROMPT ===== TEST 15: already-restored INSERT group -> ORA-20004 and exactly ONE new FAILED row =====

-- Self-contained: HR inserts employee 199, ADMIN undoes the INSERT, then
-- undoes it a second time (must fail with ORA-20004).

DEFINE t15_emp = 199

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

DELETE FROM rewind.employees
 WHERE emp_id = &t15_emp AND emp_name = 'Test15 Person';
COMMIT;

COLUMN base_aud NEW_VALUE v_base_aud NOPRINT
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

INSERT INTO rewind.employees (emp_id, emp_name, job_title, salary, dept_id, hire_date, status)
VALUES (&t15_emp, 'Test15 Person', 'Tester', 40000, 30, SYSDATE, 'ACTIVE');

COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

DECLARE
  v_group  VARCHAR2(32);
  v_exists NUMBER;
  v_before NUMBER;
  v_after  NUMBER;
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id)
    INTO v_group
    FROM rewind.audit_log
   WHERE table_name  = 'EMPLOYEES'
     AND record_id   = &t15_emp
     AND operation   = 'INSERT'
     AND is_restored = 'N'
     AND audit_id    > &v_base_aud;

  -- First undo: must succeed.
  rewind.rewind_pkg.restore_change_group(v_group);
  COMMIT;

  SELECT COUNT(*) INTO v_exists FROM rewind.employees WHERE emp_id = &t15_emp;
  DBMS_OUTPUT.PUT_LINE('1st undo: employee rows left = ' || v_exists || ' (expected 0)');

  SELECT COUNT(*) INTO v_before
    FROM rewind.recovery_log
   WHERE change_group = v_group AND status = 'FAILED';

  -- Second undo of the same group: must fail.
  BEGIN
    rewind.rewind_pkg.restore_change_group(v_group);
    DBMS_OUTPUT.PUT_LINE('ERROR: 2nd undo unexpectedly succeeded');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
  END;

  SELECT COUNT(*) INTO v_after
    FROM rewind.recovery_log
   WHERE change_group = v_group AND status = 'FAILED';

  DBMS_OUTPUT.PUT_LINE('new FAILED rows = ' || (v_after - v_before) || ' (expected exactly 1)');
END;
/

PROMPT --- Test 15 cleanup (safety net, normally nothing left) ---

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1

DELETE FROM rewind.employees
 WHERE emp_id = &t15_emp AND emp_name = 'Test15 Person';

COMMIT;


PROMPT ===== TEST 16: restore_change_group succeeds, then the CALLER does ROLLBACK =====

-- restore_change_group does not commit on success. After ROLLBACK, the data,
-- the is_restored flags, the RESTORE audit rows and the recovery_log row must
-- all be back in the pre-restore state, and the group must still be restorable.

DEFINE t16_emp = 197

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

DELETE FROM rewind.employees
 WHERE emp_id = &t16_emp AND emp_name = 'Rollback Test';
COMMIT;

COLUMN base_aud NEW_VALUE v_base_aud NOPRINT
SELECT NVL(MAX(audit_id), 0) AS base_aud FROM rewind.audit_log;

CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

INSERT INTO rewind.employees (emp_id, emp_name, job_title, salary, dept_id, hire_date, status)
VALUES (&t16_emp, 'Rollback Test', 'Tester', 50000, 30, SYSDATE, 'ACTIVE');
COMMIT;

-- One UPDATE group with two audit rows: SALARY and JOB_TITLE.
UPDATE rewind.employees
   SET salary    = 61000,
       job_title = 'Senior Tester'
 WHERE emp_id = &t16_emp;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF

COLUMN t16_grp NEW_VALUE v_t16_grp NOPRINT
SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) AS t16_grp
  FROM rewind.audit_log
 WHERE table_name  = 'EMPLOYEES'
   AND record_id   = &t16_emp
   AND operation   = 'UPDATE'
   AND is_restored = 'N'
   AND audit_id    > &v_base_aud;

PROMPT -- Step 1: restore succeeds inside the caller's open transaction
DECLARE
  v_sal     NUMBER;
  v_title   VARCHAR2(50);
  v_pending NUMBER;
  v_rest    NUMBER;
  v_ok      NUMBER;
BEGIN
  rewind.rewind_pkg.restore_change_group('&v_t16_grp');

  SELECT salary, job_title INTO v_sal, v_title
    FROM rewind.employees WHERE emp_id = &t16_emp;
  DBMS_OUTPUT.PUT_LINE('before ROLLBACK: salary = ' || v_sal || ' (expected 50000)');
  DBMS_OUTPUT.PUT_LINE('before ROLLBACK: job_title = ' || v_title || ' (expected Tester)');

  SELECT COUNT(*) INTO v_pending FROM rewind.audit_log
   WHERE change_group = '&v_t16_grp' AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('before ROLLBACK: rows not restored = ' || v_pending || ' (expected 0)');

  SELECT COUNT(*) INTO v_rest FROM rewind.audit_log
   WHERE table_name = 'EMPLOYEES' AND record_id = &t16_emp
     AND operation = 'RESTORE' AND audit_id > &v_base_aud;
  DBMS_OUTPUT.PUT_LINE('before ROLLBACK: RESTORE audit rows = ' || v_rest || ' (expected 2)');

  SELECT COUNT(*) INTO v_ok FROM rewind.recovery_log
   WHERE change_group = '&v_t16_grp' AND status = 'SUCCESS';
  DBMS_OUTPUT.PUT_LINE('before ROLLBACK: SUCCESS rows = ' || v_ok || ' (expected 1)');
END;
/

PROMPT -- Step 2: the caller rolls everything back
ROLLBACK;

PROMPT -- Step 3: everything must be back to the pre-restore state
DECLARE
  v_sal     NUMBER;
  v_title   VARCHAR2(50);
  v_pending NUMBER;
  v_rest    NUMBER;
  v_ok      NUMBER;
BEGIN
  SELECT salary, job_title INTO v_sal, v_title
    FROM rewind.employees WHERE emp_id = &t16_emp;
  DBMS_OUTPUT.PUT_LINE('after ROLLBACK: salary = ' || v_sal || ' (expected 61000)');
  DBMS_OUTPUT.PUT_LINE('after ROLLBACK: job_title = ' || v_title || ' (expected Senior Tester)');

  SELECT COUNT(*) INTO v_pending FROM rewind.audit_log
   WHERE change_group = '&v_t16_grp' AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('after ROLLBACK: rows not restored = ' || v_pending || ' (expected 2)');

  SELECT COUNT(*) INTO v_rest FROM rewind.audit_log
   WHERE table_name = 'EMPLOYEES' AND record_id = &t16_emp
     AND operation = 'RESTORE' AND audit_id > &v_base_aud;
  DBMS_OUTPUT.PUT_LINE('after ROLLBACK: RESTORE audit rows = ' || v_rest || ' (expected 0)');

  SELECT COUNT(*) INTO v_ok FROM rewind.recovery_log
   WHERE change_group = '&v_t16_grp' AND status = 'SUCCESS';
  DBMS_OUTPUT.PUT_LINE('after ROLLBACK: SUCCESS rows = ' || v_ok || ' (expected 0)');
END;
/

PROMPT -- Step 4: the same group can still be restored (and committed) afterwards
DECLARE
  v_sal     NUMBER;
  v_pending NUMBER;
BEGIN
  rewind.rewind_pkg.restore_change_group('&v_t16_grp');
  COMMIT;

  SELECT salary INTO v_sal FROM rewind.employees WHERE emp_id = &t16_emp;
  DBMS_OUTPUT.PUT_LINE('after 2nd restore + COMMIT: salary = ' || v_sal || ' (expected 50000)');

  SELECT COUNT(*) INTO v_pending FROM rewind.audit_log
   WHERE change_group = '&v_t16_grp' AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('after 2nd restore + COMMIT: rows not restored = ' || v_pending || ' (expected 0)');
END;
/

PROMPT --- Test 16 cleanup (only the test employee) ---

CONNECT rewind/"Rewind#123"@//localhost:1521/XEPDB1

DELETE FROM rewind.employees
 WHERE emp_id = &t16_emp AND emp_name = 'Rollback Test';

COMMIT;

-- =====================================================================
-- END OF TESTS
-- =====================================================================
SPOOL OFF
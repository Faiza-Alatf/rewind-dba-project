-- =====================================================================
-- REWIND - 08_tests.sql   (run from SQL*Plus / SQLcl as any user)
-- Edit the connect string below if your service name is different.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
COLUMN reason FORMAT A70

PROMPT ===== TEST 1: HR makes a mistake (salary 80,000 -> 800,000) =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
UPDATE rewind.employees SET salary = 800000 WHERE emp_id = 101;
COMMIT;

PROMPT ===== TEST 2: HR tries to restore -> must be DENIED (ORA-20001) =====
BEGIN
  rewind.rewind_pkg.restore_value(1);
EXCEPTION WHEN OTHERS THEN
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
  SELECT MAX(audit_id) INTO v_id FROM rewind.audit_log
   WHERE record_id = 101 AND column_name = 'SALARY' AND operation = 'UPDATE' AND is_restored = 'N';
  rewind.rewind_pkg.restore_value(v_id);
  SELECT salary INTO v_sal FROM rewind.employees WHERE emp_id = 101;
  DBMS_OUTPUT.PUT_LINE('Salary after restore = ' || v_sal || '  (expected 80000)');
END;
/

PROMPT ===== TEST 4: HR deletes an employee, ADMIN brings it back =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DELETE FROM rewind.employees WHERE emp_id = 115;
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DECLARE
  v_group VARCHAR2(32);
  v_name  VARCHAR2(80);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log WHERE record_id = 115 AND operation = 'DELETE' AND is_restored = 'N';
  rewind.rewind_pkg.restore_deleted(v_group);
  SELECT emp_name INTO v_name FROM rewind.employees WHERE emp_id = 115;
  DBMS_OUTPUT.PUT_LINE('Employee 115 is back: ' || v_name);
END;
/

PROMPT ===== TEST 5: unregistered user (RW_GUEST) changes data -> flagged =====
CONNECT rw_guest/"Guest#12345"@//localhost:1521/XEPDB1
UPDATE rewind.employees SET job_title = 'Temp Title' WHERE emp_id = 102;
COMMIT;

PROMPT ===== TEST 6: AUDITOR reviews suspicious activity and tries to restore =====
CONNECT rw_auditor/"Auditor#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SELECT sus_id, severity, reason, changed_by FROM rewind.v_suspicious_details ORDER BY sus_id;
BEGIN
  rewind.rewind_pkg.restore_value(1);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

PROMPT ===== TEST 7: full history of employee 101 =====
SELECT audit_id, operation, column_name, old_value, new_value, changed_by,
       TO_CHAR(changed_on,'YYYY-MM-DD HH24:MI:SS') AS changed_on
  FROM rewind.v_change_history WHERE record_id = 101 ORDER BY audit_id;


PROMPT ===== TEST 8: HR inserts a new employee, ADMIN undoes the INSERT =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF
-- Pick the next free employee ID so the test can be re-run safely
COLUMN new_id NEW_VALUE v_new_id NOPRINT
SELECT NVL(MAX(emp_id), 0) + 1 AS new_id FROM rewind.employees;
INSERT INTO rewind.employees VALUES (&v_new_id, 'Test Person', 'Tester', 50000, 30, SYSDATE, 'ACTIVE');
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DECLARE
  v_group  VARCHAR2(32);
  v_cnt    NUMBER;
  v_flag   VARCHAR2(1);
  v_status VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log
   WHERE record_id = &v_new_id AND operation = 'INSERT' AND is_restored = 'N';
  rewind.rewind_pkg.restore_inserted(v_group);

  SELECT COUNT(*) INTO v_cnt FROM rewind.employees WHERE emp_id = &v_new_id;
  DBMS_OUTPUT.PUT_LINE('Employee ' || &v_new_id || ' rows after undo = ' || v_cnt || '  (expected 0)');

  -- all audit rows of the INSERT group must be flagged as restored
  SELECT MIN(is_restored) INTO v_flag
    FROM rewind.audit_log
   WHERE change_group = v_group AND operation = 'INSERT';
  DBMS_OUTPUT.PUT_LINE('audit_log.is_restored = ' || v_flag || '  (expected Y)');

  -- newest recovery_log row of this group must be SUCCESS
  SELECT status INTO v_status
    FROM (SELECT status FROM rewind.recovery_log
           WHERE change_group = v_group ORDER BY recovery_id DESC)
   WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('recovery_log.status = ' || v_status || '  (expected SUCCESS)');
END;
/

PROMPT ===== TEST 9: HR tries restore_inserted -> must be DENIED (ORA-20001) =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
BEGIN
  -- the admin check runs first, so any group id is enough here
  rewind.rewind_pkg.restore_inserted('DUMMY_GROUP');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

PROMPT ===== TEST 10: restore_change_group on an UPDATE group (2 columns) =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
-- employee 103 starts as Accountant / 70000 (sample data)
UPDATE rewind.employees SET salary = 71000, job_title = 'Senior Accountant' WHERE emp_id = 103;
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
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log
   WHERE record_id = 103 AND operation = 'UPDATE' AND is_restored = 'N';
  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT salary, job_title INTO v_sal, v_title FROM rewind.employees WHERE emp_id = 103;
  DBMS_OUTPUT.PUT_LINE('Employee 103 salary = ' || v_sal || '  (expected 70000)');
  DBMS_OUTPUT.PUT_LINE('Employee 103 job_title = ' || v_title || '  (expected Accountant)');

  SELECT COUNT(*) INTO v_pending
    FROM rewind.audit_log WHERE change_group = v_group AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('audit_log rows not restored = ' || v_pending || '  (expected 0)');

  SELECT status INTO v_status
    FROM (SELECT status FROM rewind.recovery_log
           WHERE change_group = v_group ORDER BY recovery_id DESC)
   WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('recovery_log.status = ' || v_status || '  (expected SUCCESS)');
END;
/

PROMPT ===== TEST 11: restore_change_group on an INSERT group =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
SET VERIFY OFF
COLUMN ins_id NEW_VALUE v_ins_id NOPRINT
SELECT NVL(MAX(emp_id), 0) + 1 AS ins_id FROM rewind.employees;
INSERT INTO rewind.employees VALUES (&v_ins_id, 'Group Insert Test', 'Tester', 50000, 30, SYSDATE, 'ACTIVE');
COMMIT;

CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DECLARE
  v_group   VARCHAR2(32);
  v_cnt     NUMBER;
  v_pending NUMBER;
  v_status  VARCHAR2(10);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log
   WHERE record_id = &v_ins_id AND operation = 'INSERT' AND is_restored = 'N';
  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT COUNT(*) INTO v_cnt FROM rewind.employees WHERE emp_id = &v_ins_id;
  DBMS_OUTPUT.PUT_LINE('Employee ' || &v_ins_id || ' rows after undo = ' || v_cnt || '  (expected 0)');

  SELECT COUNT(*) INTO v_pending
    FROM rewind.audit_log WHERE change_group = v_group AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('audit_log rows not restored = ' || v_pending || '  (expected 0)');

  SELECT status INTO v_status
    FROM (SELECT status FROM rewind.recovery_log
           WHERE change_group = v_group ORDER BY recovery_id DESC)
   WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('recovery_log.status = ' || v_status || '  (expected SUCCESS)');
END;
/

PROMPT ===== TEST 12: restore_change_group on a DELETE group =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
-- employee 112 is Nida Hassan / 48000 (sample data)
DELETE FROM rewind.employees WHERE emp_id = 112;
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
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log
   WHERE record_id = 112 AND operation = 'DELETE' AND is_restored = 'N';
  rewind.rewind_pkg.restore_change_group(v_group);

  SELECT emp_name, salary INTO v_name, v_sal FROM rewind.employees WHERE emp_id = 112;
  DBMS_OUTPUT.PUT_LINE('Employee 112 is back: ' || v_name || ' / ' || v_sal || '  (expected Nida Hassan / 48000)');

  SELECT COUNT(*) INTO v_pending
    FROM rewind.audit_log WHERE change_group = v_group AND is_restored = 'N';
  DBMS_OUTPUT.PUT_LINE('audit_log rows not restored = ' || v_pending || '  (expected 0)');

  SELECT status INTO v_status
    FROM (SELECT status FROM rewind.recovery_log
           WHERE change_group = v_group ORDER BY recovery_id DESC)
   WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('recovery_log.status = ' || v_status || '  (expected SUCCESS)');
END;
/

PROMPT ===== TEST 13: unknown change group -> ORA-20010 and a FAILED row =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DECLARE
  v_status VARCHAR2(10);
BEGIN
  BEGIN
    rewind.rewind_pkg.restore_change_group('NO_SUCH_GROUP');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
  END;
  SELECT status INTO v_status
    FROM (SELECT status FROM rewind.recovery_log
           WHERE change_group = 'NO_SUCH_GROUP' ORDER BY recovery_id DESC)
   WHERE ROWNUM = 1;
  DBMS_OUTPUT.PUT_LINE('recovery_log.status = ' || v_status || '  (expected FAILED)');
END;
/

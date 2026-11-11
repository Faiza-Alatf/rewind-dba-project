-- =====================================================================
-- REWIND - 10_departments_audit_tests.sql  (run after 10_departments_audit.sql)
-- Edit the connect strings if your service name is different.
-- =====================================================================
SET SERVEROUTPUT ON
SET LINESIZE 200

PROMPT ===== D1: ADMIN renames department 50 -> audit row is written =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
UPDATE rewind.departments SET dept_name = 'Ops Temp' WHERE dept_id = 50;
COMMIT;
SELECT audit_id, operation, old_value, new_value, changed_by FROM rewind.v_department_history WHERE dept_id = 50;

PROMPT ===== D2: AUDITOR tries to restore -> must be DENIED (ORA-20001) =====
CONNECT rw_auditor/"Auditor#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
BEGIN
  rewind.restore_dept_name(1);
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

PROMPT ===== D3: ADMIN restores the old department name =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
DECLARE
  v_id   NUMBER;
  v_name VARCHAR2(50);
BEGIN
  SELECT MAX(audit_id) INTO v_id FROM rewind.audit_log
   WHERE table_name = 'DEPARTMENTS' AND record_id = 50 AND operation = 'UPDATE' AND is_restored = 'N';
  rewind.restore_dept_name(v_id);
  SELECT dept_name INTO v_name FROM rewind.departments WHERE dept_id = 50;
  DBMS_OUTPUT.PUT_LINE('Department 50 name after restore = ' || v_name || '  (expected Operations)');
END;
/

PROMPT ===== D4: ADMIN adds department 70, deletes it, then restores it =====
INSERT INTO rewind.departments VALUES (70, 'Legal');
COMMIT;
DELETE FROM rewind.departments WHERE dept_id = 70;
COMMIT;
DECLARE
  v_group VARCHAR2(32);
  v_name  VARCHAR2(50);
BEGIN
  SELECT MAX(change_group) KEEP (DENSE_RANK LAST ORDER BY audit_id) INTO v_group
    FROM rewind.audit_log
   WHERE table_name = 'DEPARTMENTS' AND record_id = 70 AND operation = 'DELETE' AND is_restored = 'N';
  rewind.restore_dept_deleted(v_group);
  SELECT dept_name INTO v_name FROM rewind.departments WHERE dept_id = 70;
  DBMS_OUTPUT.PUT_LINE('Department 70 is back: ' || v_name || '  (expected Legal)');
END;
/

PROMPT ===== D5: HR tries to rename a department -> must fail (no UPDATE privilege) =====
CONNECT rw_hr/"Hr#12345"@//localhost:1521/XEPDB1
SET SERVEROUTPUT ON
BEGIN
  EXECUTE IMMEDIATE 'UPDATE rewind.departments SET dept_name = ''X'' WHERE dept_id = 10';
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('Expected error: ' || SQLERRM);
END;
/

PROMPT ===== CLEANUP: remove test department 70 =====
CONNECT rw_admin/"Admin#12345"@//localhost:1521/XEPDB1
DELETE FROM rewind.departments WHERE dept_id = 70;
COMMIT;

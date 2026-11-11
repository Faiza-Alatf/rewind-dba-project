-- =====================================================================
-- REWIND - 10_departments_audit.sql   (run as REWIND, after 01-07)
-- Extends auditing to the DEPARTMENTS table:
--   * trigger that logs INSERT / UPDATE / DELETE of department names
--   * restore procedures for a renamed or deleted department
--   * history view + privileges
-- It does not change REWIND_PKG, so it cannot clash with other branches.
-- =====================================================================

-- ---------- failure logging (autonomous: survives the rollback) ----------
CREATE OR REPLACE PROCEDURE rewind_log_failure(p_audit_id NUMBER, p_group VARCHAR2, p_msg VARCHAR2) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO recovery_log(recovery_id, audit_id, change_group, restored_by, status, message)
  VALUES (rec_seq.NEXTVAL, p_audit_id, p_group,
          SYS_CONTEXT('USERENV', 'SESSION_USER'), 'FAILED', SUBSTR(p_msg, 1, 500));
  COMMIT;
END;
/

-- ---------- audit trigger ----------
CREATE OR REPLACE TRIGGER trg_departments_audit
AFTER INSERT OR UPDATE OR DELETE ON departments
FOR EACH ROW
DECLARE
  v_group VARCHAR2(32) := RAWTOHEX(SYS_GUID());
  v_op    VARCHAR2(10);
BEGIN
  IF INSERTING THEN
    v_op := 'INSERT';
  ELSIF UPDATING THEN
    v_op := 'UPDATE';
  ELSE
    v_op := 'DELETE';
  END IF;

  IF v_op <> 'UPDATE' OR :OLD.dept_name <> :NEW.dept_name THEN
    rewind_core.log_change(v_group, 'DEPARTMENTS', NVL(:NEW.dept_id, :OLD.dept_id),
                           v_op, 'DEPT_NAME', :OLD.dept_name, :NEW.dept_name);
  END IF;
END;
/

-- ---------- restore a renamed department ----------
CREATE OR REPLACE PROCEDURE restore_dept_name(p_audit_id NUMBER) IS
  r      audit_log%ROWTYPE;
  v_user VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_rows NUMBER;
BEGIN
  IF NOT rewind_core.is_admin(v_user) THEN
    rewind_log_failure(p_audit_id, NULL, 'Access denied for ' || v_user);
    RAISE_APPLICATION_ERROR(-20001, 'Access denied: only ADMIN users can restore data');
  END IF;

  BEGIN
    SELECT * INTO r FROM audit_log WHERE audit_id = p_audit_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20002, 'Audit record ' || p_audit_id || ' not found');
  END;

  IF r.table_name <> 'DEPARTMENTS' OR r.operation <> 'UPDATE' THEN
    RAISE_APPLICATION_ERROR(-20003, 'Only UPDATE entries of DEPARTMENTS can be restored here');
  END IF;
  IF r.is_restored = 'Y' THEN
    RAISE_APPLICATION_ERROR(-20004, 'This change was already restored');
  END IF;

  SAVEPOINT before_restore;
  BEGIN
    rewind_core.g_restoring := TRUE;
    UPDATE departments SET dept_name = r.old_value WHERE dept_id = r.record_id;
    v_rows := SQL%ROWCOUNT;
    IF v_rows = 0 THEN
      RAISE_APPLICATION_ERROR(-20006, 'Department ' || r.record_id || ' no longer exists');
    END IF;
    rewind_core.g_restoring := FALSE;

    UPDATE audit_log SET is_restored = 'Y' WHERE audit_id = p_audit_id;
    INSERT INTO recovery_log(recovery_id, audit_id, change_group, restored_by,
                             value_before_restore, restored_value, status, message)
    VALUES (rec_seq.NEXTVAL, p_audit_id, r.change_group, v_user, r.new_value, r.old_value, 'SUCCESS',
            'Restored name of department ' || r.record_id);
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      rewind_core.g_restoring := FALSE;
      ROLLBACK TO before_restore;
      rewind_log_failure(p_audit_id, r.change_group, SQLERRM);
      RAISE;
  END;
END restore_dept_name;
/

-- ---------- restore a deleted department ----------
CREATE OR REPLACE PROCEDURE restore_dept_deleted(p_change_group VARCHAR2) IS
  v_user  VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  v_cnt   NUMBER;
  v_id    NUMBER;
  v_first NUMBER;
  v_name  VARCHAR2(50);
BEGIN
  IF NOT rewind_core.is_admin(v_user) THEN
    rewind_log_failure(NULL, p_change_group, 'Access denied for ' || v_user);
    RAISE_APPLICATION_ERROR(-20001, 'Access denied: only ADMIN users can restore data');
  END IF;

  SELECT COUNT(*), MIN(record_id), MIN(audit_id), MAX(old_value)
    INTO v_cnt, v_id, v_first, v_name
    FROM audit_log
   WHERE change_group = p_change_group AND operation = 'DELETE'
     AND table_name = 'DEPARTMENTS' AND is_restored = 'N';

  IF v_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20007, 'No restorable deleted department found for this change group');
  END IF;

  SAVEPOINT before_restore;
  BEGIN
    rewind_core.g_restoring := TRUE;
    INSERT INTO departments(dept_id, dept_name) VALUES (v_id, v_name);
    rewind_core.g_restoring := FALSE;

    UPDATE audit_log SET is_restored = 'Y'
     WHERE change_group = p_change_group AND operation = 'DELETE';
    INSERT INTO recovery_log(recovery_id, audit_id, change_group, restored_by,
                             restored_value, status, message)
    VALUES (rec_seq.NEXTVAL, v_first, p_change_group, v_user, v_name, 'SUCCESS',
            'Restored deleted department ' || v_id || ' (' || v_name || ')');
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      rewind_core.g_restoring := FALSE;
      ROLLBACK TO before_restore;
      rewind_log_failure(v_first, p_change_group, SQLERRM);
      RAISE;
  END;
END restore_dept_deleted;
/

-- ---------- history view ----------
CREATE OR REPLACE VIEW v_department_history AS
SELECT a.audit_id, a.record_id AS dept_id,
       (SELECT d.dept_name FROM departments d WHERE d.dept_id = a.record_id) AS current_name,
       a.operation, a.old_value, a.new_value, a.changed_by, a.changed_on, a.is_restored
  FROM audit_log a
 WHERE a.table_name = 'DEPARTMENTS';

-- ---------- privileges ----------
-- Script 07 gave every role only SELECT on DEPARTMENTS; only ADMIN may edit departments.
GRANT INSERT, UPDATE, DELETE ON departments TO rewind_admin_role;
GRANT SELECT ON v_department_history TO rewind_admin_role, rewind_auditor_role;
GRANT EXECUTE ON restore_dept_name    TO rewind_admin_role, rewind_auditor_role, rewind_hr_role;
GRANT EXECUTE ON restore_dept_deleted TO rewind_admin_role, rewind_auditor_role, rewind_hr_role;
-- (authorization is checked again inside each procedure)

SHOW ERRORS

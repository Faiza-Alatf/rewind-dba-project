-- =====================================================================
-- REWIND - 05_audit_trigger.sql  (run as REWIND, after 04)
-- Row-level trigger: captures old/new value of every column, the user,
-- the time and the operation. It runs in the SAME transaction as the DML,
-- so if the user rolls back, the audit rows disappear with it.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_employees_audit
AFTER INSERT OR UPDATE OR DELETE ON employees
FOR EACH ROW
DECLARE
  v_group VARCHAR2(32) := RAWTOHEX(SYS_GUID());
  v_op    VARCHAR2(10);
  v_id    NUMBER;

  PROCEDURE chg(p_col VARCHAR2, p_old VARCHAR2, p_new VARCHAR2) IS
  BEGIN
    IF v_op <> 'UPDATE'
       OR (p_old IS NULL AND p_new IS NOT NULL)
       OR (p_old IS NOT NULL AND p_new IS NULL)
       OR (p_old <> p_new) THEN
      rewind_core.log_change(v_group, 'EMPLOYEES', v_id, v_op, p_col, p_old, p_new);
    END IF;
  END;
BEGIN
  IF INSERTING THEN
    v_op := 'INSERT';
  ELSIF UPDATING THEN
    v_op := 'UPDATE';
  ELSE
    v_op := 'DELETE';
  END IF;
  v_id := NVL(:NEW.emp_id, :OLD.emp_id);

  chg('EMP_NAME',  :OLD.emp_name,  :NEW.emp_name);
  chg('JOB_TITLE', :OLD.job_title, :NEW.job_title);
  chg('SALARY',    rewind_core.num2str(:OLD.salary), rewind_core.num2str(:NEW.salary));
  chg('DEPT_ID',   TO_CHAR(:OLD.dept_id), TO_CHAR(:NEW.dept_id));
  chg('HIRE_DATE', TO_CHAR(:OLD.hire_date, 'YYYY-MM-DD HH24:MI:SS'),
                   TO_CHAR(:NEW.hire_date, 'YYYY-MM-DD HH24:MI:SS'));
  chg('STATUS',    :OLD.status,    :NEW.status);
END;
/
SHOW ERRORS

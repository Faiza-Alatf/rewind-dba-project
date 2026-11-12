
-- =====================================================================
-- REWIND - 06_rewind_pkg.sql (run as REWIND)
-- PUBLIC API package: history, restore, review, reports.
-- Group restoration is atomic and caller-controlled.
-- =====================================================================

CREATE OR REPLACE PACKAGE rewind_pkg AS

  FUNCTION my_role RETURN VARCHAR2;

  PROCEDURE restore_value(p_audit_id NUMBER);
  PROCEDURE restore_deleted(p_change_group VARCHAR2);
  PROCEDURE restore_inserted(p_change_group VARCHAR2);
  PROCEDURE restore_change_group(p_change_group VARCHAR2);
  PROCEDURE review_suspicious(p_sus_id NUMBER);

  FUNCTION activity_report(p_from DATE, p_to DATE)
    RETURN SYS_REFCURSOR;

END rewind_pkg;
/

-- =====================================================================
-- PACKAGE BODY
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY rewind_pkg AS

  -- Failed attempts survive the caller's rollback.
  PROCEDURE log_failure(
    p_audit_id NUMBER,
    p_group    VARCHAR2,
    p_msg      VARCHAR2
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO recovery_log(
      recovery_id, audit_id, change_group,
      restored_by, status, message
    )
    VALUES (
      rec_seq.NEXTVAL, p_audit_id, p_group,
      SYS_CONTEXT('USERENV', 'SESSION_USER'),
      'FAILED', SUBSTR(p_msg, 1, 500)
    );

    COMMIT;
  END log_failure;


  FUNCTION my_role RETURN VARCHAR2 IS
    v_role app_users.app_role%TYPE;
  BEGIN
    SELECT app_role
      INTO v_role
      FROM app_users
     WHERE username = UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'))
       AND is_active = 'Y';

    RETURN v_role;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN 'NONE';
  END my_role;


  -- ===================================================================
  -- RESTORE ONE UPDATE AUDIT RECORD
  -- ===================================================================

  PROCEDURE restore_value(p_audit_id NUMBER) IS
    r      audit_log%ROWTYPE;
    v_user VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_rows NUMBER;
  BEGIN
    IF NOT rewind_core.is_admin(v_user) THEN
      log_failure(p_audit_id, NULL, 'Access denied for ' || v_user);
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN users can restore data'
      );
    END IF;

    BEGIN
      SELECT *
        INTO r
        FROM audit_log
       WHERE audit_id = p_audit_id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
          -20002,
          'Audit record ' || p_audit_id || ' not found'
        );
    END;

    IF r.operation <> 'UPDATE' THEN
      RAISE_APPLICATION_ERROR(
        -20003,
        'Only UPDATE entries can be restored here (use restore_deleted for deleted rows)'
      );
    END IF;

    IF r.is_restored = 'Y' THEN
      RAISE_APPLICATION_ERROR(
        -20004,
        'This change was already restored'
      );
    END IF;

    SAVEPOINT before_restore;

    BEGIN
      rewind_core.g_restoring := TRUE;

      CASE r.column_name
        WHEN 'SALARY' THEN
          UPDATE employees
             SET salary = rewind_core.str2num(r.old_value)
           WHERE emp_id = r.record_id;

        WHEN 'EMP_NAME' THEN
          UPDATE employees
             SET emp_name = r.old_value
           WHERE emp_id = r.record_id;

        WHEN 'JOB_TITLE' THEN
          UPDATE employees
             SET job_title = r.old_value
           WHERE emp_id = r.record_id;

        WHEN 'DEPT_ID' THEN
          UPDATE employees
             SET dept_id = TO_NUMBER(r.old_value)
           WHERE emp_id = r.record_id;

        WHEN 'STATUS' THEN
          UPDATE employees
             SET status = r.old_value
           WHERE emp_id = r.record_id;

        WHEN 'HIRE_DATE' THEN
          UPDATE employees
             SET hire_date = TO_DATE(
               r.old_value,
               'YYYY-MM-DD HH24:MI:SS'
             )
           WHERE emp_id = r.record_id;

        ELSE
          RAISE_APPLICATION_ERROR(
            -20005,
            'Column ' || r.column_name || ' cannot be restored'
          );
      END CASE;

      v_rows := SQL%ROWCOUNT;

      IF v_rows = 0 THEN
        RAISE_APPLICATION_ERROR(
          -20006,
          'Employee ' || r.record_id || ' no longer exists'
        );
      END IF;

      rewind_core.g_restoring := FALSE;

      UPDATE audit_log
         SET is_restored = 'Y'
       WHERE audit_id = p_audit_id;

      INSERT INTO recovery_log(
        recovery_id, audit_id, change_group, restored_by,
        value_before_restore, restored_value, status, message
      )
      VALUES (
        rec_seq.NEXTVAL, p_audit_id, r.change_group, v_user,
        r.new_value, r.old_value, 'SUCCESS',
        'Restored ' || r.column_name ||
        ' of employee ' || r.record_id
      );

      COMMIT;

    EXCEPTION
      WHEN OTHERS THEN
        rewind_core.g_restoring := FALSE;
        ROLLBACK TO before_restore;
        log_failure(p_audit_id, r.change_group, SQLERRM);
        RAISE;
    END;
  END restore_value;


  -- ===================================================================
  -- INTERNAL IMPLEMENTATION: RESTORE DELETED EMPLOYEE
  -- p_commit = TRUE  -> standalone public call
  -- p_commit = FALSE -> called inside restore_change_group
  -- ===================================================================

  PROCEDURE restore_deleted_impl(
    p_change_group VARCHAR2,
    p_commit       BOOLEAN
  ) IS
    v_user  VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_emp   employees%ROWTYPE;
    v_cnt   NUMBER;
    v_first NUMBER;
  BEGIN
    IF NOT rewind_core.is_admin(v_user) THEN
      log_failure(NULL, p_change_group, 'Access denied for ' || v_user);
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN users can restore data'
      );
    END IF;

    SELECT COUNT(*), MIN(audit_id), MIN(record_id)
      INTO v_cnt, v_first, v_emp.emp_id
      FROM audit_log
     WHERE change_group = p_change_group
       AND operation = 'DELETE'
       AND table_name = 'EMPLOYEES'
       AND is_restored = 'N';

    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(
        -20007,
        'No restorable deleted record found for this change group'
      );
    END IF;

    FOR c IN (
      SELECT column_name, old_value
        FROM audit_log
       WHERE change_group = p_change_group
         AND operation = 'DELETE'
         AND table_name = 'EMPLOYEES'
    ) LOOP
      CASE c.column_name
        WHEN 'EMP_NAME' THEN
          v_emp.emp_name := c.old_value;

        WHEN 'JOB_TITLE' THEN
          v_emp.job_title := c.old_value;

        WHEN 'SALARY' THEN
          v_emp.salary := rewind_core.str2num(c.old_value);

        WHEN 'DEPT_ID' THEN
          v_emp.dept_id := TO_NUMBER(c.old_value);

        WHEN 'HIRE_DATE' THEN
          v_emp.hire_date := TO_DATE(
            c.old_value,
            'YYYY-MM-DD HH24:MI:SS'
          );

        WHEN 'STATUS' THEN
          v_emp.status := c.old_value;

        ELSE
          NULL;
      END CASE;
    END LOOP;

    SAVEPOINT before_restore;

    BEGIN
      rewind_core.g_restoring := TRUE;

      INSERT INTO employees VALUES v_emp;

      rewind_core.g_restoring := FALSE;

      UPDATE audit_log
         SET is_restored = 'Y'
       WHERE change_group = p_change_group
         AND operation = 'DELETE'
         AND table_name = 'EMPLOYEES';

      INSERT INTO recovery_log(
        recovery_id, audit_id, change_group, restored_by,
        value_before_restore, restored_value, status, message
      )
      VALUES (
        rec_seq.NEXTVAL, v_first, p_change_group, v_user,
        NULL, 'Employee ' || v_emp.emp_id, 'SUCCESS',
        'Restored deleted employee ' || v_emp.emp_id ||
        ' (' || v_emp.emp_name || ')'
      );

      IF p_commit THEN
        COMMIT;
      END IF;

    EXCEPTION
      WHEN OTHERS THEN
        rewind_core.g_restoring := FALSE;
        ROLLBACK TO before_restore;
        log_failure(v_first, p_change_group, SQLERRM);
        RAISE;
    END;
  END restore_deleted_impl;


  -- Public standalone API: preserves its original COMMIT behaviour.
  PROCEDURE restore_deleted(p_change_group VARCHAR2) IS
  BEGIN
    restore_deleted_impl(p_change_group, TRUE);
  END restore_deleted;


  -- ===================================================================
  -- INTERNAL IMPLEMENTATION: UNDO INSERTED EMPLOYEE
  -- ===================================================================

  PROCEDURE restore_inserted_impl(
    p_change_group VARCHAR2,
    p_commit       BOOLEAN
  ) IS
    v_user  VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_cnt   NUMBER;
    v_first NUMBER;
    v_emp   NUMBER;
  BEGIN
    IF NOT rewind_core.is_admin(v_user) THEN
      log_failure(NULL, p_change_group, 'Access denied for ' || v_user);
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN users can restore data'
      );
    END IF;

    SELECT COUNT(*), MIN(audit_id), MIN(record_id)
      INTO v_cnt, v_first, v_emp
      FROM audit_log
     WHERE change_group = p_change_group
       AND operation = 'INSERT'
       AND table_name = 'EMPLOYEES'
       AND is_restored = 'N';

    IF v_cnt = 0 THEN
      RAISE_APPLICATION_ERROR(
        -20009,
        'No restorable inserted record found for this change group'
      );
    END IF;

    SAVEPOINT before_restore;

    BEGIN
      rewind_core.g_restoring := TRUE;

      DELETE FROM employees
       WHERE emp_id = v_emp;

      IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(
          -20006,
          'Employee ' || v_emp || ' no longer exists'
        );
      END IF;

      rewind_core.g_restoring := FALSE;

      UPDATE audit_log
         SET is_restored = 'Y'
       WHERE change_group = p_change_group
         AND operation = 'INSERT'
         AND table_name = 'EMPLOYEES'
         AND record_id = v_emp;

      INSERT INTO recovery_log(
        recovery_id, audit_id, change_group, restored_by,
        value_before_restore, restored_value, status, message
      )
      VALUES (
        rec_seq.NEXTVAL, v_first, p_change_group, v_user,
        'Employee ' || v_emp, NULL, 'SUCCESS',
        'Undid INSERT of employee ' || v_emp
      );

      IF p_commit THEN
        COMMIT;
      END IF;

    EXCEPTION
      WHEN OTHERS THEN
        rewind_core.g_restoring := FALSE;
        ROLLBACK TO before_restore;
        log_failure(v_first, p_change_group, SQLERRM);
        RAISE;
    END;
  END restore_inserted_impl;


  -- Public standalone API: preserves its original COMMIT behaviour.
  PROCEDURE restore_inserted(p_change_group VARCHAR2) IS
  BEGIN
    restore_inserted_impl(p_change_group, TRUE);
  END restore_inserted;


  -- ===================================================================
  -- RESTORE A COMPLETE CHANGE GROUP
  --
  -- UPDATE: all columns restored in one UPDATE.
  -- INSERT: internal non-committing helper.
  -- DELETE: internal non-committing helper.
  --
  -- Success: caller controls COMMIT / ROLLBACK.
  -- Failure: rollback to before_group and log one FAILED row.
  -- ===================================================================

  PROCEDURE restore_change_group(p_change_group VARCHAR2) IS
    v_user      VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_cnt       NUMBER;
    v_op_min    VARCHAR2(10);
    v_op_max    VARCHAR2(10);
    v_first     NUMBER;
    v_rec_id    NUMBER;
    v_pending   NUMBER;
    v_emp       employees%ROWTYPE;
    v_err       VARCHAR2(500);
    v_delegated BOOLEAN := FALSE;
  BEGIN
    IF NOT rewind_core.is_admin(v_user) THEN
      log_failure(NULL, p_change_group, 'Access denied for ' || v_user);
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN users can restore data'
      );
    END IF;

    SELECT COUNT(*),
           MIN(operation),
           MAX(operation),
           MIN(audit_id),
           MIN(record_id)
      INTO v_cnt, v_op_min, v_op_max, v_first, v_rec_id
      FROM audit_log
     WHERE change_group = p_change_group
       AND table_name = 'EMPLOYEES';

    SAVEPOINT before_group;

    BEGIN
      IF v_cnt = 0 THEN
        RAISE_APPLICATION_ERROR(
          -20010,
          'Change group not found: ' || p_change_group
        );
      END IF;

      IF v_op_min <> v_op_max THEN
        RAISE_APPLICATION_ERROR(
          -20011,
          'Change group contains mixed operations'
        );
      END IF;

      CASE v_op_min

        -- -------------------------------------------------------------
        -- UPDATE GROUP
        -- -------------------------------------------------------------

        WHEN 'UPDATE' THEN

          SELECT COUNT(*)
            INTO v_pending
            FROM audit_log
           WHERE change_group = p_change_group
             AND operation = 'UPDATE'
             AND table_name = 'EMPLOYEES'
             AND is_restored = 'N';

          IF v_pending = 0 THEN
            RAISE_APPLICATION_ERROR(
              -20004,
              'This change group was already restored'
            );
          END IF;

          BEGIN
            SELECT *
              INTO v_emp
              FROM employees
             WHERE emp_id = v_rec_id
             FOR UPDATE;
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              RAISE_APPLICATION_ERROR(
                -20006,
                'Employee ' || v_rec_id || ' no longer exists'
              );
          END;

          rewind_core.g_restoring := TRUE;

          FOR c IN (
            SELECT column_name, old_value
              FROM audit_log
             WHERE change_group = p_change_group
               AND operation = 'UPDATE'
               AND table_name = 'EMPLOYEES'
               AND is_restored = 'N'
             ORDER BY audit_id
          ) LOOP

            CASE c.column_name
              WHEN 'EMP_NAME' THEN
                v_emp.emp_name := c.old_value;

              WHEN 'JOB_TITLE' THEN
                v_emp.job_title := c.old_value;

              WHEN 'SALARY' THEN
                v_emp.salary := rewind_core.str2num(c.old_value);

              WHEN 'DEPT_ID' THEN
                v_emp.dept_id := TO_NUMBER(c.old_value);

              WHEN 'HIRE_DATE' THEN
                v_emp.hire_date := TO_DATE(
                  c.old_value,
                  'YYYY-MM-DD HH24:MI:SS'
                );

              WHEN 'STATUS' THEN
                v_emp.status := c.old_value;

              ELSE
                RAISE_APPLICATION_ERROR(
                  -20005,
                  'Column ' || c.column_name || ' cannot be restored'
                );
            END CASE;

          END LOOP;

          -- Restore all changed columns in one UPDATE.
          UPDATE employees
             SET ROW = v_emp
           WHERE emp_id = v_rec_id;

          rewind_core.g_restoring := FALSE;

          UPDATE audit_log
             SET is_restored = 'Y'
           WHERE change_group = p_change_group
             AND operation = 'UPDATE'
             AND table_name = 'EMPLOYEES'
             AND record_id = v_rec_id;

          INSERT INTO recovery_log(
            recovery_id, audit_id, change_group, restored_by,
            value_before_restore, restored_value, status, message
          )
          VALUES (
            rec_seq.NEXTVAL, v_first, p_change_group, v_user,
            NULL, NULL, 'SUCCESS',
            'Restored ' || v_pending ||
            ' column(s) of employee ' || v_rec_id ||
            ' (change group)'
          );

          -- Intentionally NO COMMIT here.
          -- Transaction remains under caller control.


        -- -------------------------------------------------------------
        -- INSERT GROUP
        -- -------------------------------------------------------------

        WHEN 'INSERT' THEN

          SELECT COUNT(*)
            INTO v_pending
            FROM audit_log
           WHERE change_group = p_change_group
             AND operation = 'INSERT'
             AND table_name = 'EMPLOYEES'
             AND is_restored = 'N';

          IF v_pending = 0 THEN
            RAISE_APPLICATION_ERROR(
              -20004,
              'This change group was already restored'
            );
          END IF;

          v_delegated := TRUE;

          -- FALSE prevents the helper from committing the parent
          -- transaction. Helper logs its own failure if it fails.
          restore_inserted_impl(p_change_group, FALSE);


        -- -------------------------------------------------------------
        -- DELETE GROUP
        -- -------------------------------------------------------------

        WHEN 'DELETE' THEN

          SELECT COUNT(*)
            INTO v_pending
            FROM audit_log
           WHERE change_group = p_change_group
             AND operation = 'DELETE'
             AND table_name = 'EMPLOYEES'
             AND is_restored = 'N';

          IF v_pending = 0 THEN
            RAISE_APPLICATION_ERROR(
              -20004,
              'This change group was already restored'
            );
          END IF;

          v_delegated := TRUE;

          restore_deleted_impl(p_change_group, FALSE);


        ELSE
          RAISE_APPLICATION_ERROR(
            -20011,
            'Operation ' || v_op_min || ' cannot be restored'
          );

      END CASE;

    EXCEPTION
      WHEN OTHERS THEN
        v_err := SUBSTR(SQLERRM, 1, 500);

        rewind_core.g_restoring := FALSE;

        ROLLBACK TO before_group;

        IF NOT v_delegated THEN
          log_failure(
            v_first,
            p_change_group,
            'restore_change_group: ' || v_err
          );
        END IF;

        RAISE;
    END;

  END restore_change_group;


  -- ===================================================================
  -- REVIEW SUSPICIOUS ACTIVITY
  -- ===================================================================

  PROCEDURE review_suspicious(p_sus_id NUMBER) IS
    v_user VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
  BEGIN
    IF NOT rewind_core.is_auditor_or_admin(v_user) THEN
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN or AUDITOR can review'
      );
    END IF;

    UPDATE suspicious_activity
       SET reviewed = 'Y',
           reviewed_by = v_user
     WHERE sus_id = p_sus_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(
        -20008,
        'Suspicious entry ' || p_sus_id || ' not found'
      );
    END IF;

    COMMIT;
  END review_suspicious;


  -- ===================================================================
  -- ACTIVITY REPORT
  -- ===================================================================

  FUNCTION activity_report(
    p_from DATE,
    p_to   DATE
  ) RETURN SYS_REFCURSOR IS
    c SYS_REFCURSOR;
  BEGIN
    IF NOT rewind_core.is_auditor_or_admin(
      SYS_CONTEXT('USERENV', 'SESSION_USER')
    ) THEN
      RAISE_APPLICATION_ERROR(
        -20001,
        'Access denied: only ADMIN or AUDITOR can run reports'
      );
    END IF;

    OPEN c FOR
      SELECT changed_by,
             operation,
             COUNT(DISTINCT change_group) AS changes
        FROM audit_log
       WHERE changed_on >= p_from
         AND changed_on < p_to + 1
       GROUP BY changed_by, operation
       ORDER BY changed_by, operation;

    RETURN c;
  END activity_report;

END rewind_pkg;
/

SHOW ERRORS

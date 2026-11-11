-- =====================================================================
-- REWIND - 04_rewind_core.sql  (run as REWIND)
-- INTERNAL package: used by triggers only. It is NOT granted to any user,
-- so nobody can forge audit entries by calling log_change directly.
-- =====================================================================
CREATE OR REPLACE PACKAGE rewind_core AS
  g_restoring BOOLEAN := FALSE;   -- set by rewind_pkg while a restore is running

  FUNCTION num2str(p_num NUMBER)     RETURN VARCHAR2;
  FUNCTION str2num(p_str VARCHAR2)   RETURN NUMBER;
  FUNCTION is_admin(p_user VARCHAR2)            RETURN BOOLEAN;
  FUNCTION is_auditor_or_admin(p_user VARCHAR2) RETURN BOOLEAN;
  FUNCTION can_edit(p_user VARCHAR2)            RETURN BOOLEAN;

  PROCEDURE log_change(p_group     VARCHAR2,
                       p_table     VARCHAR2,
                       p_record_id NUMBER,
                       p_op        VARCHAR2,
                       p_col       VARCHAR2,
                       p_old       VARCHAR2,
                       p_new       VARCHAR2);
END rewind_core;
/

CREATE OR REPLACE PACKAGE BODY rewind_core AS
  g_last_group VARCHAR2(32);

  -- ---------- helpers ----------
  FUNCTION num2str(p_num NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(p_num, 'FM9999999990D00', 'NLS_NUMERIC_CHARACTERS=''.,''');
  END;

  FUNCTION str2num(p_str VARCHAR2) RETURN NUMBER IS
  BEGIN
    RETURN TO_NUMBER(p_str, '9999999990D99', 'NLS_NUMERIC_CHARACTERS=''.,''');
  END;

  FUNCTION has_role(p_user VARCHAR2, p_r1 VARCHAR2, p_r2 VARCHAR2 DEFAULT NULL) RETURN BOOLEAN IS
    v_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_cnt
      FROM app_users
     WHERE username = UPPER(p_user)
       AND is_active = 'Y'
       AND app_role IN (p_r1, NVL(p_r2, p_r1));
    RETURN v_cnt > 0;
  END;

  FUNCTION is_admin(p_user VARCHAR2)            RETURN BOOLEAN IS BEGIN RETURN has_role(p_user, 'ADMIN'); END;
  FUNCTION is_auditor_or_admin(p_user VARCHAR2) RETURN BOOLEAN IS BEGIN RETURN has_role(p_user, 'ADMIN', 'AUDITOR'); END;
  FUNCTION can_edit(p_user VARCHAR2)            RETURN BOOLEAN IS BEGIN RETURN has_role(p_user, 'ADMIN', 'HR'); END;

  -- ---------- suspicious activity detection ----------
  PROCEDURE flag(p_audit_id NUMBER, p_reason VARCHAR2, p_sev VARCHAR2) IS
  BEGIN
    INSERT INTO suspicious_activity(sus_id, audit_id, reason, severity)
    VALUES (sus_seq.NEXTVAL, p_audit_id, SUBSTR(p_reason, 1, 300), p_sev);
  END;

  PROCEDURE check_suspicious(p_audit_id NUMBER, p_first BOOLEAN, p_op VARCHAR2,
                             p_col VARCHAR2, p_old VARCHAR2, p_new VARCHAR2, p_user VARCHAR2,
                             p_table VARCHAR2, p_record_id NUMBER) IS
    v_old  NUMBER;
    v_new  NUMBER;
    v_cnt  NUMBER;
    v_hour NUMBER;
    v_day  VARCHAR2(3);
  BEGIN
    -- Rule 1: abnormal salary jump / drop
    IF p_op = 'UPDATE' AND p_col = 'SALARY' THEN
      v_old := str2num(p_old);
      v_new := str2num(p_new);
      IF v_old > 0 AND v_new >= v_old * 3 THEN
        flag(p_audit_id, 'Salary increased by more than 200% (' || p_old || ' -> ' || p_new || ')', 'HIGH');
      ELSIF v_old > 0 AND v_new <= v_old * 0.3 THEN
        flag(p_audit_id, 'Salary reduced by more than 70% (' || p_old || ' -> ' || p_new || ')', 'HIGH');
      END IF;
    END IF;

    -- Rule 5: same employee's salary changed 2+ times on the same day
    -- (log_change has already inserted the current audit row, so the current change is counted too)
    IF p_op = 'UPDATE' AND p_col = 'SALARY' AND p_table = 'EMPLOYEES' THEN
      SELECT COUNT(*) INTO v_cnt
        FROM audit_log
       WHERE table_name  = 'EMPLOYEES'
         AND record_id   = p_record_id
         AND column_name = 'SALARY'
         AND operation   = 'UPDATE'
         AND changed_on >= TRUNC(SYSDATE);
      IF v_cnt >= 2 THEN
        flag(p_audit_id, 'Salary of employee ' || p_record_id || ' changed ' || v_cnt || ' times today', 'MEDIUM');
      END IF;
    END IF;

    -- Rules 2-4 are checked once per changed row (first column logged)
    IF p_first THEN
      -- Rule 2: outside working hours (08:00-18:00, Mon-Fri)
      v_hour := TO_NUMBER(TO_CHAR(SYSDATE, 'HH24'));
      v_day  := TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH');
      IF v_hour < 8 OR v_hour >= 18 OR v_day IN ('SAT', 'SUN') THEN
        flag(p_audit_id, 'Change made outside working hours', 'MEDIUM');
      END IF;

      -- Rule 3: user has no HR/ADMIN application role
      IF NOT can_edit(p_user) THEN
        flag(p_audit_id, 'Change made by user without HR/ADMIN role (' || p_user || ')', 'HIGH');
      END IF;

      -- Rule 4: bulk modification (10+ rows by one user within 1 minute)
      SELECT COUNT(DISTINCT change_group) INTO v_cnt
        FROM audit_log
       WHERE changed_by = p_user
         AND operation <> 'RESTORE'
         AND changed_on > SYSTIMESTAMP - INTERVAL '1' MINUTE;
      IF v_cnt >= 10 THEN
        flag(p_audit_id, 'Bulk modification: ' || v_cnt || ' rows changed by ' || p_user || ' within 1 minute', 'MEDIUM');
      END IF;
    END IF;
  END;

  -- ---------- main logging procedure (called by the trigger) ----------
  PROCEDURE log_change(p_group VARCHAR2, p_table VARCHAR2, p_record_id NUMBER,
                       p_op VARCHAR2, p_col VARCHAR2, p_old VARCHAR2, p_new VARCHAR2) IS
    v_op       VARCHAR2(10) := p_op;
    v_user     VARCHAR2(30) := SYS_CONTEXT('USERENV', 'SESSION_USER');
    v_audit_id NUMBER;
    v_first    BOOLEAN;
  BEGIN
    IF g_restoring THEN
      v_op := 'RESTORE';
    END IF;

    v_first      := (g_last_group IS NULL OR g_last_group <> p_group);
    g_last_group := p_group;

    INSERT INTO audit_log(audit_id, change_group, table_name, record_id, operation,
                          column_name, old_value, new_value, changed_by, client_host)
    VALUES (audit_seq.NEXTVAL, p_group, p_table, p_record_id, v_op,
            p_col, p_old, p_new, v_user, SYS_CONTEXT('USERENV', 'HOST'))
    RETURNING audit_id INTO v_audit_id;

    IF v_op <> 'RESTORE' THEN
      check_suspicious(v_audit_id, v_first, v_op, p_col, p_old, p_new, v_user, p_table, p_record_id);
    END IF;
  END;
END rewind_core;
/
SHOW ERRORS

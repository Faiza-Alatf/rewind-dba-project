-- =====================================================================
-- REWIND - uninstall.sql   (run as SYSTEM)
-- Removes EVERYTHING created by scripts 01-10.
-- WARNING: deletes all REWIND data. Test database only!
-- Safe to run repeatedly (missing objects are skipped).
-- =====================================================================
SET SERVEROUTPUT ON
SET VERIFY OFF
SET LINESIZE 200
WHENEVER SQLERROR CONTINUE
SPOOL uninstall_output.log

ALTER SESSION SET CONTAINER = XEPDB1;

DECLARE
  PROCEDURE run_ddl(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('OK    : ' || p_sql);
  EXCEPTION
    WHEN OTHERS THEN
      -- 1918 user, 1919 role, 2380 profile: does not exist
      IF SQLCODE IN (-1918, -1919, -2380) THEN
        DBMS_OUTPUT.PUT_LINE('SKIP  : ' || p_sql || '  (does not exist)');
      ELSE
        DBMS_OUTPUT.PUT_LINE('ERROR : ' || p_sql || '  -> ' || SQLERRM);
      END IF;
  END;
BEGIN
  -- Connected sessions block DROP USER (ORA-01940), so end them first
  FOR s IN (SELECT sid, serial# FROM v$session
             WHERE username IN ('REWIND','RW_ADMIN','RW_AUDITOR','RW_HR','RW_GUEST')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('WARN  : could not kill session ' || s.sid || ' - close it manually');
    END;
  END LOOP;
  DBMS_SESSION.SLEEP(2);

  run_ddl('DROP USER rewind CASCADE');
  run_ddl('DROP USER rw_admin CASCADE');
  run_ddl('DROP USER rw_auditor CASCADE');
  run_ddl('DROP USER rw_hr CASCADE');
  run_ddl('DROP USER rw_guest CASCADE');
  run_ddl('DROP ROLE rewind_admin_role');
  run_ddl('DROP ROLE rewind_auditor_role');
  run_ddl('DROP ROLE rewind_hr_role');
  run_ddl('DROP PROFILE rewind_profile CASCADE');
END;
/

PROMPT ===== Check: all three numbers must be 0 =====
SELECT (SELECT COUNT(*) FROM dba_users
         WHERE username IN ('REWIND','RW_ADMIN','RW_AUDITOR','RW_HR','RW_GUEST')) AS leftover_users,
       (SELECT COUNT(*) FROM dba_roles WHERE role LIKE 'REWIND%')                  AS leftover_roles,
       (SELECT COUNT(*) FROM dba_profiles WHERE profile = 'REWIND_PROFILE')        AS leftover_profile
  FROM dual;
SPOOL OFF
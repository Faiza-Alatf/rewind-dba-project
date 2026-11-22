-- =====================================================================
-- REWIND - install_all.sql   (run as REWIND, from the sql folder)
-- Prerequisite: 01_users_roles.sql already run as SYSTEM.
-- Runs 02-07, then 09 (more sample data) and 10 (DEPARTMENTS audit).
-- For a clean start run uninstall.sql + 01 first (this script is NOT re-runnable).
-- =====================================================================
SET SERVEROUTPUT ON
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 100
COLUMN object_name FORMAT A30
COLUMN trigger_name FORMAT A30
COLUMN status FORMAT A10
WHENEVER SQLERROR CONTINUE
SPOOL install_all_output.log

PROMPT >>> 02 tables
@@02_tables.sql
PROMPT >>> 03 sample data
@@03_sample_data.sql
PROMPT >>> 04 rewind_core
@@04_rewind_core.sql
PROMPT >>> 05 audit trigger
@@05_audit_trigger.sql
PROMPT >>> 06 rewind_pkg
@@06_rewind_pkg.sql
PROMPT >>> 07 security views
@@07_security_views.sql
PROMPT >>> 09 more sample data
@@09_more_sample_data.sql
PROMPT >>> 10 departments audit
@@10_departments_audit.sql

PROMPT ===== CHECK 1: INVALID objects (must return no rows) =====
SELECT object_type, object_name, status FROM user_objects WHERE status <> 'VALID';

PROMPT ===== CHECK 2: counts (expect employees 115, departments 5, app_users 3, audit_log 0) =====
SELECT (SELECT COUNT(*) FROM employees)   AS employees,
       (SELECT COUNT(*) FROM departments) AS departments,
       (SELECT COUNT(*) FROM app_users)   AS app_users,
       (SELECT COUNT(*) FROM audit_log)   AS audit_rows
  FROM dual;

PROMPT ===== CHECK 3: both triggers must be ENABLED =====
SELECT trigger_name, status FROM user_triggers ORDER BY trigger_name;
SPOOL OFF
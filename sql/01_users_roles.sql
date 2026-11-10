-- =====================================================================
-- REWIND - 01_users_roles.sql
-- Run as SYSTEM.  Oracle XE 21c uses a pluggable DB, so switch first.
-- (If you use a non-CDB database, delete the ALTER SESSION line below.)
-- =====================================================================
ALTER SESSION SET CONTAINER = XEPDB1;

-- Security profile: lock account after 5 failed logins, passwords expire in 90 days
CREATE PROFILE rewind_profile LIMIT
  FAILED_LOGIN_ATTEMPTS 5
  PASSWORD_LOCK_TIME    1/24
  PASSWORD_LIFE_TIME    90;

-- Schema owner (owns tables, triggers, packages)
CREATE USER rewind IDENTIFIED BY "Rewind#123"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users PROFILE rewind_profile;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER TO rewind;

-- Roles (object privileges are granted later by script 06)
CREATE ROLE rewind_admin_role;
CREATE ROLE rewind_auditor_role;
CREATE ROLE rewind_hr_role;
GRANT CREATE SESSION TO rewind_admin_role, rewind_auditor_role, rewind_hr_role;

-- Demo users
CREATE USER rw_admin   IDENTIFIED BY "Admin#12345"   PROFILE rewind_profile;
CREATE USER rw_auditor IDENTIFIED BY "Auditor#12345" PROFILE rewind_profile;
CREATE USER rw_hr      IDENTIFIED BY "Hr#12345"      PROFILE rewind_profile;
-- rw_guest is NOT registered in APP_USERS (demo of unauthorized changes)
CREATE USER rw_guest   IDENTIFIED BY "Guest#12345"   PROFILE rewind_profile;

GRANT rewind_admin_role   TO rw_admin;
GRANT rewind_auditor_role TO rw_auditor;
GRANT rewind_hr_role      TO rw_hr;
GRANT rewind_hr_role      TO rw_guest;

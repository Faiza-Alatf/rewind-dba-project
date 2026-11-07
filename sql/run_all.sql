-- Run from the sql/ folder.  Step 1 as SYSTEM, the rest as REWIND:
--   sqlplus system/<password>@//localhost:1521/XEPDB1 @01_users_roles.sql
--   sqlplus rewind/"Rewind#123"@//localhost:1521/XEPDB1 @run_all.sql
@02_tables.sql
@03_sample_data.sql
@04_rewind_core.sql
@05_audit_trigger.sql
@06_rewind_pkg.sql
@07_security_views.sql

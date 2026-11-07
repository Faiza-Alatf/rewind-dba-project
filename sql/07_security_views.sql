-- =====================================================================
-- REWIND - 07_security_views.sql  (run as REWIND, after 06)
-- Reporting views + object privileges for the three Oracle roles.
-- Nobody (except the owner) gets DML on AUDIT_LOG -> the log cannot be tampered with.
-- =====================================================================
CREATE OR REPLACE VIEW v_change_history AS
SELECT a.audit_id, a.change_group, a.table_name, a.record_id, a.operation,
       a.column_name, a.old_value, a.new_value, a.changed_by, a.client_host,
       a.changed_on, a.is_restored,
       CASE WHEN EXISTS (SELECT 1
                           FROM suspicious_activity s JOIN audit_log b ON b.audit_id = s.audit_id
                          WHERE b.change_group = a.change_group)
            THEN 'Y' ELSE 'N' END AS is_suspicious
  FROM audit_log a;

CREATE OR REPLACE VIEW v_activity_by_user AS
SELECT changed_by,
       COUNT(DISTINCT change_group)                                        AS total_changes,
       COUNT(DISTINCT CASE WHEN operation = 'UPDATE'  THEN change_group END) AS updates,
       COUNT(DISTINCT CASE WHEN operation = 'INSERT'  THEN change_group END) AS inserts,
       COUNT(DISTINCT CASE WHEN operation = 'DELETE'  THEN change_group END) AS deletes,
       COUNT(DISTINCT CASE WHEN operation = 'RESTORE' THEN change_group END) AS restores,
       MIN(changed_on) AS first_change,
       MAX(changed_on) AS last_change
  FROM audit_log
 GROUP BY changed_by;

CREATE OR REPLACE VIEW v_daily_activity AS
SELECT TRUNC(CAST(changed_on AS DATE)) AS activity_day,
       COUNT(DISTINCT change_group)    AS changes
  FROM audit_log
 GROUP BY TRUNC(CAST(changed_on AS DATE));

CREATE OR REPLACE VIEW v_suspicious_details AS
SELECT s.sus_id, s.reason, s.severity, s.detected_on, s.reviewed, s.reviewed_by,
       a.audit_id, a.change_group, a.record_id, a.column_name,
       a.old_value, a.new_value, a.changed_by, a.changed_on
  FROM suspicious_activity s JOIN audit_log a ON a.audit_id = s.audit_id;

-- ---------- privileges ----------
GRANT SELECT ON departments TO rewind_admin_role, rewind_auditor_role, rewind_hr_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON employees TO rewind_admin_role, rewind_hr_role;
GRANT SELECT ON employees TO rewind_auditor_role;

GRANT SELECT ON audit_log            TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON recovery_log         TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON suspicious_activity  TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON v_change_history     TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON v_activity_by_user   TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON v_daily_activity     TO rewind_admin_role, rewind_auditor_role;
GRANT SELECT ON v_suspicious_details TO rewind_admin_role, rewind_auditor_role;

-- Public API (authorization is checked again inside the package)
GRANT EXECUTE ON rewind_pkg TO rewind_admin_role, rewind_auditor_role, rewind_hr_role;

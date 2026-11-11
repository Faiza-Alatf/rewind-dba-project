# Data Dictionary – Rewind (Oracle)

Schema owner: `REWIND`. 6 tables, 6 primary keys, 2 declared foreign keys.
Audited tables: `EMPLOYEES` and `DEPARTMENTS`.
ER diagram: `docs/er_diagram.png` (editable: `docs/er_diagram.drawio`).

## Relationships
| From | To | Type | Enforced? |
|---|---|---|---|
| `EMPLOYEES.DEPT_ID` | `DEPARTMENTS.DEPT_ID` | many-to-one | ✅ declared FK |
| `SUSPICIOUS_ACTIVITY.AUDIT_ID` | `AUDIT_LOG.AUDIT_ID` | many-to-one | ✅ declared FK |
| `RECOVERY_LOG.AUDIT_ID` | `AUDIT_LOG.AUDIT_ID` | logical | ❌ no FK (kept so failed attempts can be logged) |
| `AUDIT_LOG.RECORD_ID` | `EMPLOYEES.EMP_ID` or `DEPARTMENTS.DEPT_ID` (depends on `TABLE_NAME`) | logical | ❌ no FK (audit rows must survive after the record is deleted; one column serves two tables) |
| `AUDIT_LOG.CHANGED_BY` | `APP_USERS.USERNAME` | logical | ❌ no FK (changes by unregistered users must still be logged) |

## DEPARTMENTS – company departments (has the audit trigger)
| Column | Type | Key | Description |
|---|---|---|---|
| DEPT_ID | NUMBER | PK | Department number |
| DEPT_NAME | VARCHAR2(50) | | Department name (NOT NULL). Changes are audited as column `DEPT_NAME` |

## EMPLOYEES – monitored business table (has the audit trigger)
| Column | Type | Key | Description |
|---|---|---|---|
| EMP_ID | NUMBER | PK | Employee number |
| EMP_NAME | VARCHAR2(80) | | Full name (NOT NULL) |
| JOB_TITLE | VARCHAR2(50) | | Job title |
| SALARY | NUMBER(10,2) | | Monthly salary in Rs. (CHECK >= 0) |
| DEPT_ID | NUMBER | FK | Department of the employee |
| HIRE_DATE | DATE | | Joining date (default SYSDATE) |
| STATUS | VARCHAR2(10) | | `ACTIVE` or `INACTIVE` |

## APP_USERS – application roles used for authorization inside PL/SQL
| Column | Type | Key | Description |
|---|---|---|---|
| USERNAME | VARCHAR2(30) | PK | Oracle username in capitals (e.g. `RW_ADMIN`) |
| APP_ROLE | VARCHAR2(10) | | `ADMIN`, `AUDITOR` or `HR` |
| IS_ACTIVE | CHAR(1) | | `Y` = account can act, `N` = disabled |

## AUDIT_LOG – one row per changed column (written only by the triggers)
| Column | Type | Key | Description |
|---|---|---|---|
| AUDIT_ID | NUMBER | PK | Unique id from `AUDIT_SEQ` |
| CHANGE_GROUP | VARCHAR2(32) | | GUID shared by all columns changed in one row operation |
| TABLE_NAME | VARCHAR2(30) | | Table that was changed: `EMPLOYEES` or `DEPARTMENTS` |
| RECORD_ID | NUMBER | | Primary key of the changed row (EMP_ID or DEPT_ID, depending on `TABLE_NAME`) |
| OPERATION | VARCHAR2(10) | | `INSERT`, `UPDATE`, `DELETE` or `RESTORE` |
| COLUMN_NAME | VARCHAR2(30) | | Column that changed |
| OLD_VALUE | VARCHAR2(4000) | | Value before the change |
| NEW_VALUE | VARCHAR2(4000) | | Value after the change |
| CHANGED_BY | VARCHAR2(30) | | Oracle user who made the change |
| CLIENT_HOST | VARCHAR2(100) | | Computer name of the session |
| CHANGED_ON | TIMESTAMP | | Date and time of the change |
| IS_RESTORED | CHAR(1) | | `Y` once an admin has restored this change |

> Tip for queries and the GUI: always filter with `WHERE table_name = 'EMPLOYEES'` (or `'DEPARTMENTS'`),
> because both tables write into the same `AUDIT_LOG`.

## SUSPICIOUS_ACTIVITY – changes flagged by the detection rules
| Column | Type | Key | Description |
|---|---|---|---|
| SUS_ID | NUMBER | PK | Unique id from `SUS_SEQ` |
| AUDIT_ID | NUMBER | FK | The audit row that triggered the alert |
| REASON | VARCHAR2(300) | | Why it was flagged (e.g. salary increased by more than 200%) |
| SEVERITY | VARCHAR2(10) | | `LOW`, `MEDIUM` or `HIGH` |
| DETECTED_ON | TIMESTAMP | | When the alert was created |
| REVIEWED | CHAR(1) | | `Y` after an ADMIN/AUDITOR reviewed it |
| REVIEWED_BY | VARCHAR2(30) | | Who reviewed it |

## RECOVERY_LOG – every restore attempt (successful or failed)
| Column | Type | Key | Description |
|---|---|---|---|
| RECOVERY_ID | NUMBER | PK | Unique id from `REC_SEQ` |
| AUDIT_ID | NUMBER | | Audit row that was being restored |
| CHANGE_GROUP | VARCHAR2(32) | | Change group that was being restored |
| RESTORED_BY | VARCHAR2(30) | | User who ran the restore |
| RESTORED_ON | TIMESTAMP | | Date and time of the attempt |
| VALUE_BEFORE_RESTORE | VARCHAR2(4000) | | Wrong value that was in the table |
| RESTORED_VALUE | VARCHAR2(4000) | | Value put back |
| STATUS | VARCHAR2(10) | | `SUCCESS` or `FAILED` |
| MESSAGE | VARCHAR2(500) | | Details / error message |

## Other database objects
| Object | Name | Purpose |
|---|---|---|
| Sequences | `AUDIT_SEQ`, `SUS_SEQ`, `REC_SEQ` | Ids for the three log tables |
| Trigger | `TRG_EMPLOYEES_AUDIT` | Logs every INSERT/UPDATE/DELETE on EMPLOYEES |
| Trigger | `TRG_DEPARTMENTS_AUDIT` | Logs every INSERT/UPDATE/DELETE of department names |
| Package (internal) | `REWIND_CORE` | Logging + suspicious-activity rules (not granted to users) |
| Package (public) | `REWIND_PKG` | `my_role`, `restore_value`, `restore_deleted`, `restore_inserted`, `review_suspicious`, `activity_report` |
| Procedures | `RESTORE_DEPT_NAME`, `RESTORE_DEPT_DELETED` | Restore a renamed or deleted department (ADMIN only) |
| Procedure (internal) | `REWIND_LOG_FAILURE` | Autonomous transaction: writes a `FAILED` row to `RECOVERY_LOG` that survives the rollback |
| Views | `V_CHANGE_HISTORY`, `V_ACTIVITY_BY_USER`, `V_DAILY_ACTIVITY`, `V_SUSPICIOUS_DETAILS`, `V_DEPARTMENT_HISTORY` | Reports and GUI screens |
| Roles | `REWIND_ADMIN_ROLE`, `REWIND_AUDITOR_ROLE`, `REWIND_HR_ROLE` | Object privileges. Only ADMIN may edit `DEPARTMENTS` |
| Profile | `REWIND_PROFILE` | Account lock after 5 failed logins, password expiry |
-- =====================================================================
-- REWIND - 02_tables.sql   (run as REWIND)
-- =====================================================================
CREATE TABLE departments (
  dept_id    NUMBER        PRIMARY KEY,
  dept_name  VARCHAR2(50)  NOT NULL
);

CREATE TABLE employees (
  emp_id     NUMBER         PRIMARY KEY,
  emp_name   VARCHAR2(80)   NOT NULL,
  job_title  VARCHAR2(50),
  salary     NUMBER(10,2)   CHECK (salary >= 0),
  dept_id    NUMBER         REFERENCES departments(dept_id),
  hire_date  DATE           DEFAULT SYSDATE,
  status     VARCHAR2(10)   DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- Application-level roles (Oracle roles grant privileges; this table drives authorization inside PL/SQL)
CREATE TABLE app_users (
  username   VARCHAR2(30) PRIMARY KEY,
  app_role   VARCHAR2(10) NOT NULL CHECK (app_role IN ('ADMIN','AUDITOR','HR')),
  is_active  CHAR(1)      DEFAULT 'Y' CHECK (is_active IN ('Y','N'))
);

CREATE SEQUENCE audit_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE sus_seq   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE rec_seq   START WITH 1 INCREMENT BY 1 NOCACHE;

-- One row per changed COLUMN. All columns of one row-change share the same change_group.
CREATE TABLE audit_log (
  audit_id     NUMBER         PRIMARY KEY,
  change_group VARCHAR2(32)   NOT NULL,
  table_name   VARCHAR2(30)   NOT NULL,
  record_id    NUMBER         NOT NULL,
  operation    VARCHAR2(10)   NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE','RESTORE')),
  column_name  VARCHAR2(30),
  old_value    VARCHAR2(4000),
  new_value    VARCHAR2(4000),
  changed_by   VARCHAR2(30)   NOT NULL,
  client_host  VARCHAR2(100),
  changed_on   TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  is_restored  CHAR(1)        DEFAULT 'N' CHECK (is_restored IN ('Y','N'))
);
CREATE INDEX ix_audit_record ON audit_log(table_name, record_id);
CREATE INDEX ix_audit_user   ON audit_log(changed_by, changed_on);
CREATE INDEX ix_audit_group  ON audit_log(change_group);

CREATE TABLE recovery_log (
  recovery_id          NUMBER        PRIMARY KEY,
  audit_id             NUMBER,
  change_group         VARCHAR2(32),
  restored_by          VARCHAR2(30)  NOT NULL,
  restored_on          TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  value_before_restore VARCHAR2(4000),
  restored_value       VARCHAR2(4000),
  status               VARCHAR2(10)  CHECK (status IN ('SUCCESS','FAILED')),
  message              VARCHAR2(500)
);

CREATE TABLE suspicious_activity (
  sus_id       NUMBER        PRIMARY KEY,
  audit_id     NUMBER        NOT NULL REFERENCES audit_log(audit_id),
  reason       VARCHAR2(300) NOT NULL,
  severity     VARCHAR2(10)  CHECK (severity IN ('LOW','MEDIUM','HIGH')),
  detected_on  TIMESTAMP     DEFAULT SYSTIMESTAMP,
  reviewed     CHAR(1)       DEFAULT 'N' CHECK (reviewed IN ('Y','N')),
  reviewed_by  VARCHAR2(30)
);

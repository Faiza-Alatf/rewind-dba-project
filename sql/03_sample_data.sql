-- =====================================================================
-- REWIND - 03_sample_data.sql  (run as REWIND, BEFORE the audit trigger exists)
-- =====================================================================
INSERT INTO departments VALUES (10, 'Human Resources');
INSERT INTO departments VALUES (20, 'Finance');
INSERT INTO departments VALUES (30, 'IT');
INSERT INTO departments VALUES (40, 'Sales');
INSERT INTO departments VALUES (50, 'Operations');

INSERT INTO employees VALUES (101, 'Ahmed Khan',    'HR Manager',        80000,  10, DATE '2019-03-15', 'ACTIVE');
INSERT INTO employees VALUES (102, 'Sara Ali',      'HR Officer',        55000,  10, DATE '2021-07-01', 'ACTIVE');
INSERT INTO employees VALUES (103, 'Bilal Ahmed',   'Accountant',        70000,  20, DATE '2020-01-10', 'ACTIVE');
INSERT INTO employees VALUES (104, 'Hina Raza',     'Finance Manager',   95000,  20, DATE '2018-05-22', 'ACTIVE');
INSERT INTO employees VALUES (105, 'Usman Tariq',   'Software Engineer', 120000, 30, DATE '2020-09-09', 'ACTIVE');
INSERT INTO employees VALUES (106, 'Ayesha Noor',   'DBA',               130000, 30, DATE '2019-11-30', 'ACTIVE');
INSERT INTO employees VALUES (107, 'Zain Malik',    'Network Engineer',  90000,  30, DATE '2022-02-14', 'ACTIVE');
INSERT INTO employees VALUES (108, 'Maria Iqbal',   'Sales Executive',   60000,  40, DATE '2021-04-19', 'ACTIVE');
INSERT INTO employees VALUES (109, 'Hamza Sheikh',  'Sales Manager',     100000, 40, DATE '2017-08-08', 'ACTIVE');
INSERT INTO employees VALUES (110, 'Fatima Zahra',  'Sales Executive',   58000,  40, DATE '2023-01-23', 'ACTIVE');
INSERT INTO employees VALUES (111, 'Kamran Yousuf', 'Operations Lead',   85000,  50, DATE '2018-12-12', 'ACTIVE');
INSERT INTO employees VALUES (112, 'Nida Hassan',   'Coordinator',       48000,  50, DATE '2022-06-06', 'ACTIVE');
INSERT INTO employees VALUES (113, 'Omar Farooq',   'Support Engineer',  65000,  30, DATE '2023-03-03', 'ACTIVE');
INSERT INTO employees VALUES (114, 'Rabia Anwar',   'Auditor',           75000,  20, DATE '2020-10-10', 'ACTIVE');
INSERT INTO employees VALUES (115, 'Danish Butt',   'Clerk',             42000,  50, DATE '2024-05-05', 'ACTIVE');

-- Application roles (must match the Oracle users created in script 01)
INSERT INTO app_users VALUES ('RW_ADMIN',   'ADMIN',   'Y');
INSERT INTO app_users VALUES ('RW_AUDITOR', 'AUDITOR', 'Y');
INSERT INTO app_users VALUES ('RW_HR',      'HR',      'Y');
-- RW_GUEST is intentionally missing -> its changes are flagged as unauthorized
COMMIT;

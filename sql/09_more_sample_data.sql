-- =====================================================================
-- REWIND - 09_more_sample_data.sql   (run as REWIND, after 01-07)
-- Adds 100 more employees (IDs 201-300) so reports and charts have enough data.
-- IDs 116-200 are intentionally left free for the test scripts.
-- The audit trigger is disabled during the load so these initial records
-- do not flood AUDIT_LOG / SUSPICIOUS_ACTIVITY as "bulk changes".
-- Run this script only ONCE (primary keys would clash on a second run).
-- =====================================================================
ALTER TRIGGER trg_employees_audit DISABLE;

INSERT INTO employees VALUES (201, 'Hussain Anwar', 'Marketing Officer', 79000, 40, DATE '2018-03-07', 'ACTIVE');
INSERT INTO employees VALUES (202, 'Laiba Iqbal', 'Accountant', 66000, 20, DATE '2017-04-07', 'ACTIVE');
INSERT INTO employees VALUES (203, 'Hussain Khan', 'Operations Officer', 59000, 50, DATE '2019-08-09', 'ACTIVE');
INSERT INTO employees VALUES (204, 'Hassan Khan', 'DBA', 152000, 30, DATE '2025-07-26', 'ACTIVE');
INSERT INTO employees VALUES (205, 'Talha Tariq', 'HR Executive', 48000, 10, DATE '2019-02-06', 'ACTIVE');
INSERT INTO employees VALUES (206, 'Mahnoor Ahmed', 'HR Executive', 54000, 10, DATE '2019-09-25', 'ACTIVE');
INSERT INTO employees VALUES (207, 'Saba Raza', 'Account Manager', 80000, 40, DATE '2024-09-07', 'ACTIVE');
INSERT INTO employees VALUES (208, 'Saba Butt', 'Software Engineer', 109000, 30, DATE '2023-07-15', 'ACTIVE');
INSERT INTO employees VALUES (209, 'Komal Hussain', 'Marketing Officer', 74000, 40, DATE '2024-07-20', 'ACTIVE');
INSERT INTO employees VALUES (210, 'Talha Sheikh', 'Recruiter', 55000, 10, DATE '2023-02-16', 'ACTIVE');
INSERT INTO employees VALUES (211, 'Hira Hashmi', 'Recruiter', 42000, 10, DATE '2020-03-22', 'ACTIVE');
INSERT INTO employees VALUES (212, 'Maria Malik', 'Operations Officer', 62000, 50, DATE '2018-01-23', 'ACTIVE');
INSERT INTO employees VALUES (213, 'Usman Chaudhry', 'Support Engineer', 65000, 30, DATE '2018-04-02', 'ACTIVE');
INSERT INTO employees VALUES (214, 'Bilal Farooq', 'Accounts Clerk', 48000, 20, DATE '2017-11-03', 'ACTIVE');
INSERT INTO employees VALUES (215, 'Amna Sheikh', 'Network Engineer', 104000, 30, DATE '2016-01-02', 'ACTIVE');
INSERT INTO employees VALUES (216, 'Hamza Yousuf', 'Account Manager', 77000, 40, DATE '2021-04-26', 'ACTIVE');
INSERT INTO employees VALUES (217, 'Zain Siddiqui', 'Account Manager', 78000, 40, DATE '2017-09-02', 'ACTIVE');
INSERT INTO employees VALUES (218, 'Waqas Siddiqui', 'Operations Officer', 63000, 50, DATE '2024-05-02', 'ACTIVE');
INSERT INTO employees VALUES (219, 'Saba Khan', 'Account Manager', 84000, 40, DATE '2020-06-01', 'ACTIVE');
INSERT INTO employees VALUES (220, 'Saba Anwar', 'Operations Officer', 79000, 50, DATE '2016-08-18', 'ACTIVE');
INSERT INTO employees VALUES (221, 'Hina Chaudhry', 'HR Executive', 42000, 10, DATE '2021-11-09', 'ACTIVE');
INSERT INTO employees VALUES (222, 'Zain Tariq', 'Operations Officer', 57000, 50, DATE '2021-02-25', 'ACTIVE');
INSERT INTO employees VALUES (223, 'Mahnoor Chaudhry', 'DBA', 137000, 30, DATE '2018-01-13', 'ACTIVE');
INSERT INTO employees VALUES (224, 'Laiba Tariq', 'DBA', 123000, 30, DATE '2023-08-04', 'ACTIVE');
INSERT INTO employees VALUES (225, 'Haris Ali', 'Account Manager', 73000, 40, DATE '2023-09-06', 'ACTIVE');
INSERT INTO employees VALUES (226, 'Kashif Hussain', 'Accountant', 65000, 20, DATE '2024-05-16', 'ACTIVE');
INSERT INTO employees VALUES (227, 'Ahmed Mirza', 'Recruiter', 46000, 10, DATE '2025-10-02', 'ACTIVE');
INSERT INTO employees VALUES (228, 'Mehwish Iqbal', 'Operations Officer', 68000, 50, DATE '2016-03-20', 'ACTIVE');
INSERT INTO employees VALUES (229, 'Sana Butt', 'Support Engineer', 75000, 30, DATE '2018-08-06', 'ACTIVE');
INSERT INTO employees VALUES (230, 'Fatima Iqbal', 'Account Manager', 71000, 40, DATE '2021-07-23', 'ACTIVE');
INSERT INTO employees VALUES (231, 'Fatima Tariq', 'Coordinator', 59000, 50, DATE '2021-11-22', 'ACTIVE');
INSERT INTO employees VALUES (232, 'Fatima Hussain', 'Sales Executive', 70000, 40, DATE '2022-02-07', 'ACTIVE');
INSERT INTO employees VALUES (233, 'Fatima Hashmi', 'Accounts Clerk', 50000, 20, DATE '2016-03-11', 'ACTIVE');
INSERT INTO employees VALUES (234, 'Iqra Sheikh', 'Network Engineer', 96000, 30, DATE '2024-05-18', 'ACTIVE');
INSERT INTO employees VALUES (235, 'Hussain Hashmi', 'HR Executive', 43000, 10, DATE '2017-09-01', 'ACTIVE');
INSERT INTO employees VALUES (236, 'Sana Anwar', 'Store Keeper', 43000, 50, DATE '2017-10-02', 'ACTIVE');
INSERT INTO employees VALUES (237, 'Adeel Shah', 'Coordinator', 43000, 50, DATE '2021-09-11', 'ACTIVE');
INSERT INTO employees VALUES (238, 'Rabia Raza', 'Accountant', 74000, 20, DATE '2021-07-12', 'ACTIVE');
INSERT INTO employees VALUES (239, 'Ali Butt', 'Accountant', 77000, 20, DATE '2019-02-03', 'ACTIVE');
INSERT INTO employees VALUES (240, 'Iqra Khan', 'Clerk', 37000, 50, DATE '2023-12-21', 'ACTIVE');
INSERT INTO employees VALUES (241, 'Ahmed Qureshi', 'Account Manager', 95000, 40, DATE '2018-09-07', 'ACTIVE');
INSERT INTO employees VALUES (242, 'Mahnoor Anwar', 'Network Engineer', 96000, 30, DATE '2024-07-16', 'ACTIVE');
INSERT INTO employees VALUES (243, 'Saad Qureshi', 'Coordinator', 56000, 50, DATE '2020-02-13', 'ACTIVE');
INSERT INTO employees VALUES (244, 'Hussain Iqbal', 'Accountant', 77000, 20, DATE '2025-02-02', 'ACTIVE');
INSERT INTO employees VALUES (245, 'Hamza Qureshi', 'Network Engineer', 95000, 30, DATE '2025-01-13', 'ACTIVE');
INSERT INTO employees VALUES (246, 'Laiba Sheikh', 'Support Engineer', 69000, 30, DATE '2017-10-13', 'ACTIVE');
INSERT INTO employees VALUES (247, 'Imran Iqbal', 'Marketing Officer', 63000, 40, DATE '2023-10-21', 'ACTIVE');
INSERT INTO employees VALUES (248, 'Junaid Yousuf', 'Support Engineer', 63000, 30, DATE '2019-05-14', 'ACTIVE');
INSERT INTO employees VALUES (249, 'Anum Ali', 'Sales Executive', 60000, 40, DATE '2022-02-19', 'ACTIVE');
INSERT INTO employees VALUES (250, 'Zain Chaudhry', 'Accountant', 75000, 20, DATE '2019-12-07', 'ACTIVE');
INSERT INTO employees VALUES (251, 'Anum Tariq', 'HR Officer', 62000, 10, DATE '2020-02-25', 'ACTIVE');
INSERT INTO employees VALUES (252, 'Fahad Tariq', 'DBA', 145000, 30, DATE '2020-05-12', 'ACTIVE');
INSERT INTO employees VALUES (253, 'Fatima Malik', 'Support Engineer', 67000, 30, DATE '2017-10-24', 'ACTIVE');
INSERT INTO employees VALUES (254, 'Danish Tariq', 'Store Keeper', 41000, 50, DATE '2017-10-04', 'ACTIVE');
INSERT INTO employees VALUES (255, 'Ayesha Yousuf', 'Network Engineer', 99000, 30, DATE '2021-08-22', 'ACTIVE');
INSERT INTO employees VALUES (256, 'Anum Khan', 'Clerk', 47000, 50, DATE '2025-04-17', 'ACTIVE');
INSERT INTO employees VALUES (257, 'Ayesha Qureshi', 'Software Engineer', 111000, 30, DATE '2022-06-07', 'ACTIVE');
INSERT INTO employees VALUES (258, 'Haris Qureshi', 'Sales Executive', 68000, 40, DATE '2021-01-17', 'ACTIVE');
INSERT INTO employees VALUES (259, 'Noor Tariq', 'Accounts Clerk', 50000, 20, DATE '2017-09-03', 'ACTIVE');
INSERT INTO employees VALUES (260, 'Hussain Ahmed', 'HR Officer', 51000, 10, DATE '2018-09-19', 'ACTIVE');
INSERT INTO employees VALUES (261, 'Hussain Qureshi', 'Accounts Clerk', 52000, 20, DATE '2021-06-15', 'ACTIVE');
INSERT INTO employees VALUES (262, 'Talha Nawaz', 'Sales Executive', 64000, 40, DATE '2017-05-09', 'ACTIVE');
INSERT INTO employees VALUES (263, 'Nida Malik', 'Marketing Officer', 78000, 40, DATE '2018-04-18', 'ACTIVE');
INSERT INTO employees VALUES (264, 'Saba Mirza', 'Accounts Clerk', 52000, 20, DATE '2021-01-21', 'ACTIVE');
INSERT INTO employees VALUES (265, 'Yasir Siddiqui', 'Sales Executive', 57000, 40, DATE '2016-01-13', 'ACTIVE');
INSERT INTO employees VALUES (266, 'Maria Iqbal', 'HR Officer', 60000, 10, DATE '2018-07-06', 'ACTIVE');
INSERT INTO employees VALUES (267, 'Hira Chaudhry', 'Accounts Clerk', 42000, 20, DATE '2019-07-11', 'ACTIVE');
INSERT INTO employees VALUES (268, 'Laiba Butt', 'Marketing Officer', 59000, 40, DATE '2021-06-19', 'ACTIVE');
INSERT INTO employees VALUES (269, 'Rida Malik', 'Sales Executive', 63000, 40, DATE '2017-10-23', 'ACTIVE');
INSERT INTO employees VALUES (270, 'Amna Siddiqui', 'Account Manager', 96000, 40, DATE '2019-02-22', 'ACTIVE');
INSERT INTO employees VALUES (271, 'Yasir Nawaz', 'Network Engineer', 100000, 30, DATE '2021-01-10', 'ACTIVE');
INSERT INTO employees VALUES (272, 'Ali Farooq', 'Account Manager', 99000, 40, DATE '2024-09-28', 'ACTIVE');
INSERT INTO employees VALUES (273, 'Noor Qureshi', 'Sales Executive', 71000, 40, DATE '2023-03-06', 'ACTIVE');
INSERT INTO employees VALUES (274, 'Saad Khan', 'Account Manager', 85000, 40, DATE '2021-07-28', 'ACTIVE');
INSERT INTO employees VALUES (275, 'Hussain Shah', 'Support Engineer', 69000, 30, DATE '2020-02-25', 'ACTIVE');
INSERT INTO employees VALUES (276, 'Fatima Mirza', 'Store Keeper', 48000, 50, DATE '2024-08-21', 'ACTIVE');
INSERT INTO employees VALUES (277, 'Faisal Mirza', 'Finance Analyst', 99000, 20, DATE '2018-02-11', 'ACTIVE');
INSERT INTO employees VALUES (278, 'Mahnoor Siddiqui', 'Account Manager', 72000, 40, DATE '2023-05-15', 'ACTIVE');
INSERT INTO employees VALUES (279, 'Amna Hashmi', 'Finance Analyst', 93000, 20, DATE '2023-11-15', 'ACTIVE');
INSERT INTO employees VALUES (280, 'Adeel Sheikh', 'Sales Executive', 63000, 40, DATE '2023-10-16', 'ACTIVE');
INSERT INTO employees VALUES (281, 'Sara Ali', 'Accounts Clerk', 51000, 20, DATE '2024-03-06', 'ACTIVE');
INSERT INTO employees VALUES (282, 'Noor Khan', 'Network Engineer', 97000, 30, DATE '2024-05-28', 'ACTIVE');
INSERT INTO employees VALUES (283, 'Talha Ahmed', 'Marketing Officer', 79000, 40, DATE '2022-10-24', 'ACTIVE');
INSERT INTO employees VALUES (284, 'Bilal Sheikh', 'Account Manager', 99000, 40, DATE '2017-02-02', 'ACTIVE');
INSERT INTO employees VALUES (285, 'Rabia Hussain', 'Clerk', 43000, 50, DATE '2025-01-16', 'ACTIVE');
INSERT INTO employees VALUES (286, 'Hamza Shah', 'HR Officer', 49000, 10, DATE '2022-04-19', 'ACTIVE');
INSERT INTO employees VALUES (287, 'Usman Qureshi', 'Store Keeper', 44000, 50, DATE '2020-09-25', 'ACTIVE');
INSERT INTO employees VALUES (288, 'Danish Raza', 'Marketing Officer', 72000, 40, DATE '2017-02-16', 'ACTIVE');
INSERT INTO employees VALUES (289, 'Haris Mirza', 'Sales Executive', 59000, 40, DATE '2024-07-21', 'ACTIVE');
INSERT INTO employees VALUES (290, 'Mehwish Sheikh', 'HR Executive', 47000, 10, DATE '2019-07-21', 'ACTIVE');
INSERT INTO employees VALUES (291, 'Danish Nawaz', 'Accounts Clerk', 48000, 20, DATE '2023-03-28', 'ACTIVE');
INSERT INTO employees VALUES (292, 'Bilal Butt', 'Marketing Officer', 57000, 40, DATE '2020-10-10', 'ACTIVE');
INSERT INTO employees VALUES (293, 'Rida Anwar', 'Network Engineer', 102000, 30, DATE '2022-11-16', 'ACTIVE');
INSERT INTO employees VALUES (294, 'Haris Ahmed', 'Store Keeper', 41000, 50, DATE '2021-04-11', 'ACTIVE');
INSERT INTO employees VALUES (295, 'Nida Hashmi', 'Finance Analyst', 88000, 20, DATE '2017-04-26', 'ACTIVE');
INSERT INTO employees VALUES (296, 'Talha Yousuf', 'Recruiter', 60000, 10, DATE '2020-07-17', 'ACTIVE');
INSERT INTO employees VALUES (297, 'Junaid Tariq', 'Accounts Clerk', 47000, 20, DATE '2025-06-24', 'ACTIVE');
INSERT INTO employees VALUES (298, 'Mahnoor Yousuf', 'Recruiter', 52000, 10, DATE '2023-10-18', 'ACTIVE');
INSERT INTO employees VALUES (299, 'Maria Siddiqui', 'Support Engineer', 69000, 30, DATE '2022-01-13', 'ACTIVE');
INSERT INTO employees VALUES (300, 'Saad Raza', 'Store Keeper', 42000, 50, DATE '2022-04-24', 'ACTIVE');

COMMIT;
ALTER TRIGGER trg_employees_audit ENABLE;

-- Check:  expect 115 employees (15 existing + 100 new), 0 new audit rows
-- SELECT COUNT(*) FROM employees;
-- SELECT dept_id, COUNT(*) AS employees, ROUND(AVG(salary)) AS avg_salary FROM employees GROUP BY dept_id ORDER BY dept_id;
-- SELECT status FROM user_triggers WHERE trigger_name = 'TRG_EMPLOYEES_AUDIT';   -- must be ENABLED


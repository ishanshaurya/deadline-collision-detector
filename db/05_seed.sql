-- =====================================================================
-- Seed data. Every date is relative to CURRENT_DATE so the demo always
-- shows live collisions, whatever day it is run.
-- Demo login for every user: password123
-- Courses are the real PES course list; credits, staff, cabins, office
-- hours, phone numbers and teammates are PLACEHOLDERS to replace.
-- =====================================================================

TRUNCATE team_members, teams, office_hours, course_staff, staff,
         task_dependencies, study_availability, tasks, enrollments, courses, users
    RESTART IDENTITY CASCADE;

INSERT INTO users (name, email, password_hash, role) VALUES
    ('Admin',        'admin@dcd.edu', crypt('password123', gen_salt('bf')), 'ADMIN'),
    ('Aarav Menon',  'aarav@dcd.edu', crypt('password123', gen_salt('bf')), 'STUDENT'),
    ('Diya Rao',     'diya@dcd.edu',  crypt('password123', gen_salt('bf')), 'STUDENT'),
    ('Kabir Shetty', 'kabir@dcd.edu', crypt('password123', gen_salt('bf')), 'STUDENT');

INSERT INTO courses (course_code, course_name, course_type, semester, credits, description) VALUES
    ('UE24CS341A',   'Software Engineering',                    'CC', 5, 4, 'Requirements, design, testing and project management'),
    ('UE24CS342AA4', 'Applied Cryptography',                    'EC', 5, 4, 'Symmetric and public-key cryptography in practice'),
    ('UE24CS343AB2', 'Big Data',                                'EC', 5, 4, 'Distributed storage and processing with Spark and Kafka'),
    ('UE24CS351A',   'Database Management System',              'CC', 5, 4, 'Relational model, SQL, normalization, transactions'),
    ('UE24CS352A',   'Machine Learning',                        'CC', 5, 4, 'Supervised and unsupervised learning'),
    ('UE24CS241B',   'Design and Analysis of Algorithms',       'CC', 4, 4, 'Algorithm design paradigms and complexity'),
    ('UE24CS242B',   'Operating Systems',                       'CC', 4, 4, 'Processes, scheduling, memory, file systems'),
    ('UE24CS251B',   'Microprocessor and Computer Architecture', 'CC', 4, 4, 'ARM assembly, pipelining, memory hierarchy'),
    ('UE24CS252B',   'Computer Networks',                       'CC', 4, 4, 'Layered architecture, TCP/IP, routing'),
    ('UE24MA241B',   'Linear Algebra and Its Applications',     'CC', 4, 4, 'Vector spaces, eigenvalues, SVD');

-- placeholder staff: one professor and one TA per course
INSERT INTO staff (name, email, phone, cabin) VALUES
    ('Prof. Anita Kulkarni',  'anita.k@dcd.edu',   '+91 80000 00101', 'F block, 4th floor, cabin 412'),
    ('Rohan Pai',        'rohan.ta@dcd.edu',  '+91 80000 00102', 'F block, TA room 405'),
    ('Prof. Sameer Bhat',     'sameer.b@dcd.edu',  '+91 80000 00103', 'B block, 2nd floor, cabin 215'),
    ('Nisha Gowda',      'nisha.ta@dcd.edu',  '+91 80000 00104', 'B block, TA room 210'),
    ('Prof. Kavya Hegde',     'kavya.h@dcd.edu',   '+91 80000 00105', 'F block, 5th floor, cabin 508'),
    ('Arjun Nair',       'arjun.ta@dcd.edu',  '+91 80000 00106', 'F block, TA room 405'),
    ('Prof. Ramesh Iyer',     'ramesh.i@dcd.edu',  '+91 80000 00107', 'F block, 4th floor, cabin 419'),
    ('Sneha Reddy',      'sneha.ta@dcd.edu',  '+91 80000 00108', 'F block, TA room 405'),
    ('Prof. Leela Menon',     'leela.m@dcd.edu',   '+91 80000 00109', 'F block, 5th floor, cabin 512'),
    ('Vikram Das',       'vikram.ta@dcd.edu', '+91 80000 00110', 'F block, TA room 506'),
    ('Prof. Harish Rao',      'harish.r@dcd.edu',  '+91 80000 00111', 'B block, 3rd floor, cabin 318'),
    ('Prof. Deepa Shenoy',    'deepa.s@dcd.edu',   '+91 80000 00112', 'B block, 3rd floor, cabin 322'),
    ('Prof. Manoj Joshi',     'manoj.j@dcd.edu',   '+91 80000 00113', 'MRD block, 1st floor, cabin 104'),
    ('Prof. Shalini Prasad',  'shalini.p@dcd.edu', '+91 80000 00114', 'B block, 2nd floor, cabin 207'),
    ('Prof. Gautam Varma',    'gautam.v@dcd.edu',  '+91 80000 00115', 'Maths dept, cabin 9'),
    ('Ira Kapoor',       'ira.ta@dcd.edu',    '+91 80000 00116', 'B block, TA room 301');

INSERT INTO course_staff (course_id, staff_id, role)
SELECT c.course_id, s.staff_id, x.role::staff_role
FROM (VALUES
    ('UE24CS341A',   'anita.k@dcd.edu',   'PROFESSOR'), ('UE24CS341A',   'rohan.ta@dcd.edu',  'TA'),
    ('UE24CS342AA4', 'sameer.b@dcd.edu',  'PROFESSOR'), ('UE24CS342AA4', 'nisha.ta@dcd.edu',  'TA'),
    ('UE24CS343AB2', 'kavya.h@dcd.edu',   'PROFESSOR'), ('UE24CS343AB2', 'arjun.ta@dcd.edu',  'TA'),
    ('UE24CS351A',   'ramesh.i@dcd.edu',  'PROFESSOR'), ('UE24CS351A',   'sneha.ta@dcd.edu',  'TA'),
    ('UE24CS352A',   'leela.m@dcd.edu',   'PROFESSOR'), ('UE24CS352A',   'vikram.ta@dcd.edu', 'TA'),
    ('UE24CS241B',   'harish.r@dcd.edu',  'PROFESSOR'), ('UE24CS241B',   'ira.ta@dcd.edu',    'TA'),
    ('UE24CS242B',   'deepa.s@dcd.edu',   'PROFESSOR'), ('UE24CS242B',   'ira.ta@dcd.edu',    'TA'),
    ('UE24CS251B',   'manoj.j@dcd.edu',   'PROFESSOR'),
    ('UE24CS252B',   'shalini.p@dcd.edu', 'PROFESSOR'),
    ('UE24MA241B',   'gautam.v@dcd.edu',  'PROFESSOR')
) AS x(code, email, role)
JOIN courses c ON c.course_code = x.code
JOIN staff   s ON s.email = x.email;

INSERT INTO office_hours (staff_id, weekday, starts_at, ends_at)
SELECT s.staff_id, x.weekday, x.starts_at::time, x.ends_at::time
FROM (VALUES
    ('anita.k@dcd.edu', 1, '14:00', '15:30'), ('anita.k@dcd.edu', 4, '11:00', '12:00'),
    ('rohan.ta@dcd.edu', 3, '16:00', '17:30'),
    ('sameer.b@dcd.edu', 2, '10:00', '11:30'),
    ('nisha.ta@dcd.edu', 5, '14:00', '16:00'),
    ('kavya.h@dcd.edu', 1, '11:00', '12:30'), ('kavya.h@dcd.edu', 3, '15:00', '16:00'),
    ('arjun.ta@dcd.edu', 4, '16:00', '18:00'),
    ('ramesh.i@dcd.edu', 2, '14:00', '16:00'), ('ramesh.i@dcd.edu', 5, '10:00', '11:00'),
    ('sneha.ta@dcd.edu', 1, '16:00', '17:30'), ('sneha.ta@dcd.edu', 3, '13:00', '14:00'),
    ('leela.m@dcd.edu', 3, '10:00', '12:00'),
    ('vikram.ta@dcd.edu', 2, '16:00', '17:00'), ('vikram.ta@dcd.edu', 4, '13:00', '14:00'),
    ('harish.r@dcd.edu', 2, '11:00', '12:00'),
    ('deepa.s@dcd.edu', 4, '14:00', '15:30'),
    ('manoj.j@dcd.edu', 1, '10:00', '11:00'),
    ('shalini.p@dcd.edu', 5, '11:00', '12:30'),
    ('gautam.v@dcd.edu', 3, '14:00', '15:00'),
    ('ira.ta@dcd.edu', 2, '15:00', '16:30')
) AS x(email, weekday, starts_at, ends_at)
JOIN staff s ON s.email = x.email;

INSERT INTO enrollments (user_id, course_id)
SELECT u.user_id, c.course_id
FROM users u
JOIN courses c ON
     (u.email = 'aarav@dcd.edu' AND c.semester = 5)
  OR (u.email = 'kabir@dcd.edu' AND c.semester = 5)
  OR (u.email = 'diya@dcd.edu'  AND c.course_code IN ('UE24CS241B','UE24CS242B','UE24CS252B','UE24MA241B'));

-- helpers raise if a name is misspelled, so the demo can't silently lose a row
CREATE FUNCTION pg_temp.seed_task(
    p_email TEXT, p_code TEXT, p_title TEXT, p_desc TEXT, p_type TEXT,
    p_day_offset INTEGER, p_hour INTEGER, p_hours DECIMAL, p_priority INTEGER
) RETURNS VOID AS $$
BEGIN
    INSERT INTO tasks (user_id, course_id, title, description, task_type, deadline,
                       estimated_hours, priority)
    SELECT u.user_id, c.course_id, p_title, p_desc, p_type::task_kind,
           CURRENT_DATE + p_day_offset + make_interval(hours => p_hour),
           p_hours, p_priority
    FROM users u, courses c
    WHERE u.email = p_email AND c.course_code = p_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'seed_task: no user % or course %', p_email, p_code;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.seed_dep(p_email TEXT, p_task TEXT, p_prereq TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO task_dependencies (task_id, prerequisite_task_id)
    SELECT t.task_id, p.task_id
    FROM tasks t
    JOIN tasks p ON p.user_id = t.user_id
    JOIN users u ON u.user_id = t.user_id
    WHERE u.email = p_email AND t.title = p_task AND p.title = p_prereq;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'seed_dep: no task "%" or "%" for %', p_task, p_prereq, p_email;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- creates the team and assigns the named tasks to it
CREATE FUNCTION pg_temp.seed_team(p_email TEXT, p_code TEXT, p_team TEXT, p_tasks TEXT[])
RETURNS INTEGER AS $$
DECLARE
    v_team INTEGER;
BEGIN
    INSERT INTO teams (user_id, course_id, name)
    SELECT u.user_id, c.course_id, p_team
    FROM users u, courses c
    WHERE u.email = p_email AND c.course_code = p_code
    RETURNING team_id INTO STRICT v_team;

    UPDATE tasks SET team_id = v_team
    WHERE title = ANY (p_tasks)
      AND user_id = (SELECT user_id FROM users WHERE email = p_email);
    IF NOT FOUND AND cardinality(p_tasks) > 0 THEN
        RAISE EXCEPTION 'seed_team: no tasks % for %', p_tasks, p_email;
    END IF;
    RETURN v_team;
END;
$$ LANGUAGE plpgsql;

DO $seed$
DECLARE
    v_team INTEGER;
BEGIN
-- ---------------------------------------------------------------------
-- Aarav (semester 5): one severe collision cluster around day 9-11, a
-- heavy week, dependency chains, one inversion, one overdue and one
-- completed task, three project teams
-- ---------------------------------------------------------------------
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS351A','ER diagram for mini project',
    'Draw the ER diagram with cardinalities and participation constraints for the library system', 'PROJECT', 2, 23, 4, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS351A','Relational schema and DDL',
    'Map the ER diagram to relations, write DDL with constraints and keys', 'PROJECT', 5, 23, 5, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS351A','DBMS mini project submission',
    'Final submission with triggers, procedures, views and a working web front end', 'PROJECT', 10, 23, 14, 1);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS341A','SE assignment 3: UML diagrams',
    'Use case, class and sequence diagrams for the campus canteen system', 'ASSIGNMENT', 9, 17, 8, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS342AA4','Crypto quiz 2',
    'Quiz on block cipher modes: CBC, CTR and GCM', 'QUIZ', 11, 10, 3, 3);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS352A','ML midterm exam',
    'Linear regression, logistic regression, SVM, bias variance tradeoff', 'EXAM', 11, 14, 12, 1);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS352A','Dataset cleaning for ML project',
    'Clean the housing dataset, handle missing values and outliers', 'PROJECT', 15, 23, 6, 3);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS352A','ML project model training',
    'Train and tune gradient boosting and random forest models', 'PROJECT', 20, 23, 10, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS352A','ML project report',
    'Write report with evaluation metrics and error analysis', 'PROJECT', 24, 23, 5, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS343AB2','Spark streaming job',
    'Kafka to Spark structured streaming pipeline for ride events', 'ASSIGNMENT', 19, 23, 9, 2);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS343AB2','Big Data assignment report',
    'Report on the streaming pipeline with throughput measurements', 'ASSIGNMENT', 17, 23, 4, 3);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS341A','SE lab 6: unit testing',
    'Write JUnit tests with boundary value analysis for the billing module', 'LAB', 4, 16, 3, 3);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS342AA4','Read chapter 5: block ciphers',
    'Feistel networks, DES and AES round structure', 'READING', 13, 20, 2, 4);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS342AA4','Crypto lab 4: AES modes',
    'Encrypt images with ECB and CBC and compare the results', 'LAB', -1, 17, 3, 3);
PERFORM pg_temp.seed_task('aarav@dcd.edu','UE24CS341A','SE assignment 2: SRS document',
    'Software requirements specification for the canteen system', 'ASSIGNMENT', -3, 23, 6, 2);
UPDATE tasks SET status = 'COMPLETED' WHERE title = 'SE assignment 2: SRS document';

PERFORM pg_temp.seed_dep('aarav@dcd.edu','Relational schema and DDL','ER diagram for mini project');
PERFORM pg_temp.seed_dep('aarav@dcd.edu','DBMS mini project submission','Relational schema and DDL');
PERFORM pg_temp.seed_dep('aarav@dcd.edu','ML project model training','Dataset cleaning for ML project');
PERFORM pg_temp.seed_dep('aarav@dcd.edu','ML project report','ML project model training');
-- inversion: report due before the job it depends on
PERFORM pg_temp.seed_dep('aarav@dcd.edu','Big Data assignment report','Spark streaming job');

v_team := pg_temp.seed_team('aarav@dcd.edu', 'UE24CS351A', 'Query Crew',
    ARRAY['ER diagram for mini project', 'Relational schema and DDL', 'DBMS mini project submission']);
INSERT INTO team_members (team_id, name, srn, email, phone, role) VALUES
    (v_team, 'Aarav Menon',   'PES2UG24CS001', 'aarav@dcd.edu',   '+91 90000 00001', 'Team lead, backend'),
    (v_team, 'Meghana Iyer',  'PES2UG24CS118', 'meghana@dcd.edu', '+91 90000 00002', 'Schema and SQL'),
    (v_team, 'Farhan Sheikh', 'PES2UG24CS097', 'farhan@dcd.edu',  '+91 90000 00003', 'Frontend');

v_team := pg_temp.seed_team('aarav@dcd.edu', 'UE24CS352A', 'Gradient Gang',
    ARRAY['Dataset cleaning for ML project', 'ML project model training', 'ML project report']);
INSERT INTO team_members (team_id, name, srn, email, phone, role) VALUES
    (v_team, 'Aarav Menon',  'PES2UG24CS001', 'aarav@dcd.edu',  '+91 90000 00001', 'Modelling'),
    (v_team, 'Tanvi Bhat',   'PES2UG24CS210', 'tanvi@dcd.edu',  '+91 90000 00004', 'Team lead, data cleaning'),
    (v_team, 'Rahul Kamath', 'PES2UG24CS176', 'rahul@dcd.edu',  '+91 90000 00005', 'Evaluation and report'),
    (v_team, 'Zoya Khan',    'PES2UG24CS244', 'zoya@dcd.edu',   '+91 90000 00006', 'Feature engineering');

v_team := pg_temp.seed_team('aarav@dcd.edu', 'UE24CS343AB2', 'Stream Team',
    ARRAY['Spark streaming job', 'Big Data assignment report']);
INSERT INTO team_members (team_id, name, srn, email, phone, role) VALUES
    (v_team, 'Aarav Menon',  'PES2UG24CS001', 'aarav@dcd.edu',  '+91 90000 00001', 'Spark consumer'),
    (v_team, 'Ishaan Gupta', 'PES2UG24CS133', 'ishaan@dcd.edu', '+91 90000 00007', 'Kafka producer'),
    (v_team, 'Pooja Nayak',  'PES2UG24CS189', 'pooja@dcd.edu',  '+91 90000 00008', 'Team lead, VM setup');

-- ---------------------------------------------------------------------
-- Diya (semester 4): light, well spread load (the control case)
-- ---------------------------------------------------------------------
PERFORM pg_temp.seed_task('diya@dcd.edu','UE24CS241B','DAA worksheet 4: greedy algorithms',
    'Activity selection, Huffman coding and fractional knapsack', 'ASSIGNMENT', 3, 23, 3, 3);
PERFORM pg_temp.seed_task('diya@dcd.edu','UE24CS242B','OS quiz 2',
    'Deadlocks and the bankers algorithm', 'QUIZ', 8, 11, 2, 3);
PERFORM pg_temp.seed_task('diya@dcd.edu','UE24MA241B','Linear algebra problem set 5',
    'Eigenvalues, diagonalisation and SVD exercises', 'ASSIGNMENT', 14, 23, 4, 3);
PERFORM pg_temp.seed_task('diya@dcd.edu','UE24CS252B','CN mini project: routing simulator',
    'Link state routing simulation with Dijkstra', 'PROJECT', 21, 23, 12, 2);

-- ---------------------------------------------------------------------
-- Kabir (semester 5): chronically overloaded (low availability, dense
-- deadlines)
-- ---------------------------------------------------------------------
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS351A','DBMS mini project submission',
    'Final submission with triggers, procedures and a web front end', 'PROJECT', 6, 23, 15, 1);
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS342AA4','Crypto assignment: RSA from scratch',
    'Key generation, encryption and signature verification', 'ASSIGNMENT', 5, 23, 10, 2);
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS352A','ML midterm exam',
    'Linear regression, logistic regression, SVM', 'EXAM', 7, 14, 12, 1);
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS343AB2','Kafka producer assignment',
    'Kafka producer and consumer for order events', 'ASSIGNMENT', 6, 18, 8, 2);
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS341A','SE quiz 1',
    'Process models and requirements engineering', 'QUIZ', 7, 9, 3, 3);
PERFORM pg_temp.seed_task('kabir@dcd.edu','UE24CS352A','ML assignment 2',
    'Implement k-means and PCA from scratch', 'ASSIGNMENT', 13, 23, 9, 2);

v_team := pg_temp.seed_team('kabir@dcd.edu', 'UE24CS351A', 'Null Pointers',
    ARRAY['DBMS mini project submission']);
INSERT INTO team_members (team_id, name, srn, email, phone, role) VALUES
    (v_team, 'Kabir Shetty', 'PES2UG24CS150', 'kabir@dcd.edu',  '+91 90000 00009', 'Team lead'),
    (v_team, 'Ananya Rao',   'PES2UG24CS021', 'ananya@dcd.edu', '+91 90000 00010', 'Frontend');
END
$seed$;

-- ---------------------------------------------------------------------
-- Availability: weekday / weekend pattern, then individual exceptions
-- ---------------------------------------------------------------------
DO $avail$
DECLARE
    v_aarav INTEGER := (SELECT user_id FROM users WHERE email = 'aarav@dcd.edu');
    v_diya  INTEGER := (SELECT user_id FROM users WHERE email = 'diya@dcd.edu');
    v_kabir INTEGER := (SELECT user_id FROM users WHERE email = 'kabir@dcd.edu');
BEGIN
    CALL sp_set_availability(v_aarav, CURRENT_DATE - 3, CURRENT_DATE + 55, 3, 6);
    CALL sp_set_availability(v_diya,  CURRENT_DATE - 3, CURRENT_DATE + 55, 3, 5);
    CALL sp_set_availability(v_kabir, CURRENT_DATE - 3, CURRENT_DATE + 55, 2, 4);

    -- Aarav: college fest, almost no study time
    UPDATE study_availability SET available_hours = 1
     WHERE user_id = v_aarav AND available_date BETWEEN CURRENT_DATE + 7 AND CURRENT_DATE + 8;
END
$avail$;

-- =====================================================================
-- Transactions, concurrency control and locking demo (psql).
-- Open TWO psql sessions (A and B) on deadline_detector, run the binding
-- block below in BOTH, then run the steps in the order shown. Nothing
-- here is permanent: each scenario ends in ROLLBACK or undoes itself.
-- =====================================================================

SELECT user_id   AS aarav    FROM users   WHERE email = 'aarav@dcd.edu' \gset
SELECT course_id AS dbms     FROM courses WHERE course_code = 'UE24CS351A' \gset
SELECT task_id   AS cleaning FROM tasks   WHERE user_id = :aarav AND title = 'Dataset cleaning for ML project' \gset
SELECT task_id   AS training FROM tasks   WHERE user_id = :aarav AND title = 'ML project model training' \gset
SELECT task_id   AS os_a3    FROM tasks   WHERE user_id = :aarav AND title = 'SE assignment 3: UML diagrams' \gset
SELECT task_id   AS cn_quiz  FROM tasks   WHERE user_id = :aarav AND title = 'Crypto quiz 2' \gset
SELECT task_id   AS project  FROM tasks   WHERE user_id = :aarav AND title = 'DBMS mini project submission' \gset

-- ---------------------------------------------------------------------
-- Scenario 1: atomicity. sp_add_task inserts the task, then the FK on
-- task_dependencies rejects a missing prerequisite, so the task insert
-- is undone as well.
-- ---------------------------------------------------------------------
BEGIN;
SELECT COUNT(*) FROM tasks WHERE user_id = :aarav;                  -- n
CALL sp_add_task(:aarav, :dbms, 'Orphan check', NULL, 'QUIZ',
                 (CURRENT_DATE + 3)::timestamp, 2, 3, ARRAY[9999], NULL); -- ERROR
ROLLBACK;
SELECT COUNT(*) FROM tasks WHERE user_id = :aarav;                  -- still n

-- ---------------------------------------------------------------------
-- Scenario 2: row locking (lost update prevention)
-- ---------------------------------------------------------------------
-- A:  BEGIN;
-- A:  CALL sp_reschedule_task(:aarav, :cleaning, (CURRENT_DATE + 18)::timestamp, TRUE);
--     (locks the task and its dependents with SELECT ... FOR UPDATE)
-- B:  BEGIN;
-- B:  UPDATE tasks SET estimated_hours = 20 WHERE task_id = :training;
--     (B blocks: it is waiting for A's row lock)
-- A:  SELECT pid, mode, granted, relation::regclass
--       FROM pg_locks WHERE relation = 'tasks'::regclass;
-- A:  ROLLBACK;
--     (B now proceeds)
-- B:  ROLLBACK;

-- ---------------------------------------------------------------------
-- Scenario 3: concurrent cycle creation is prevented by the advisory
-- lock in trg_validate_dependency. Without it, each session would see
-- no cycle in its own snapshot and both inserts would succeed.
-- ---------------------------------------------------------------------
-- A:  BEGIN;
-- A:  INSERT INTO task_dependencies (task_id, prerequisite_task_id) VALUES (:cn_quiz, :os_a3);
-- B:  BEGIN;
-- B:  INSERT INTO task_dependencies (task_id, prerequisite_task_id) VALUES (:os_a3, :cn_quiz);
--     (B blocks on pg_advisory_xact_lock(:aarav))
-- A:  COMMIT;
--     B wakes up. Under READ COMMITTED each statement takes a fresh snapshot,
--     so B's trigger query now sees A's row and raises "... would create a cycle".
-- B:  ROLLBACK;
-- cleanup:  DELETE FROM task_dependencies WHERE task_id = :cn_quiz AND prerequisite_task_id = :os_a3;

-- ---------------------------------------------------------------------
-- Scenario 4: isolation levels. REPEATABLE READ keeps a stable snapshot
-- for a whole report, READ COMMITTED does not.
-- ---------------------------------------------------------------------
-- A:  BEGIN ISOLATION LEVEL REPEATABLE READ;
-- A:  SELECT SUM(estimated_hours) FROM tasks WHERE user_id = :aarav;   -- x
-- B:  UPDATE tasks SET estimated_hours = estimated_hours + 5 WHERE task_id = :project;
-- A:  SELECT SUM(estimated_hours) FROM tasks WHERE user_id = :aarav;   -- still x
-- A:  COMMIT;
-- A:  SELECT SUM(estimated_hours) FROM tasks WHERE user_id = :aarav;   -- x + 5
-- B:  UPDATE tasks SET estimated_hours = estimated_hours - 5 WHERE task_id = :project;

-- ---------------------------------------------------------------------
-- Scenario 5: savepoints. Keep the good part of a batch.
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO study_availability (user_id, available_date, available_hours)
VALUES (:aarav, CURRENT_DATE + 100, 4);
SAVEPOINT before_bad_row;
INSERT INTO study_availability (user_id, available_date, available_hours)
VALUES (:aarav, CURRENT_DATE + 101, 30);                            -- violates CHECK (<= 24)
ROLLBACK TO SAVEPOINT before_bad_row;
SELECT available_date, available_hours FROM study_availability
 WHERE user_id = :aarav AND available_date >= CURRENT_DATE + 100;   -- first row kept
ROLLBACK;

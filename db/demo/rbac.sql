-- =====================================================================
-- Roles and access control demo (psql, connected as postgres).
-- Each block is its own transaction and ends in ROLLBACK.
-- =====================================================================

SELECT user_id AS admin FROM users WHERE email = 'admin@dcd.edu' \gset
SELECT user_id AS aarav FROM users WHERE email = 'aarav@dcd.edu' \gset
SELECT user_id AS kabir FROM users WHERE email = 'kabir@dcd.edu' \gset
SELECT task_id AS kabir_task FROM tasks WHERE user_id = :kabir ORDER BY task_id LIMIT 1 \gset

-- ---------------------------------------------------------------------
-- 1. Application roles, checked inside the database
-- ---------------------------------------------------------------------
SELECT name, email, role FROM users ORDER BY user_id;

-- the admin overview returns rows only for an ADMIN caller
SELECT COUNT(*) AS rows_for_aarav FROM v_admin_overview WHERE fn_is_admin(:aarav);
SELECT name, role, pending_tasks, pending_hours, critical_tasks FROM v_admin_overview WHERE fn_is_admin(:admin);

-- a student calling an admin procedure is refused (ERROR expected)
CALL sp_admin_set_role(:aarav, :aarav, 'ADMIN');

-- an admin can, and the last admin can't be demoted (ERROR expected)
BEGIN;
CALL sp_admin_set_role(:admin, :kabir, 'ADMIN');
SELECT name, role FROM users WHERE user_id = :kabir;
ROLLBACK;
CALL sp_admin_set_role(:admin, :admin, 'STUDENT');

-- ---------------------------------------------------------------------
-- 2. Database roles + row-level security
-- SET LOCAL ROLE switches to the restricted role for one transaction;
-- app.user_id says which student the session acts for.
-- ---------------------------------------------------------------------
\dp tasks

BEGIN;
SET LOCAL ROLE dcd_student;
SELECT set_config('app.user_id', :'aarav', true);
SELECT COUNT(*) AS tasks_i_can_see FROM tasks;                              -- only Aarav's
SELECT COUNT(*) AS kabirs_tasks_visible FROM tasks WHERE user_id = :kabir;  -- 0
UPDATE tasks SET priority = 1 WHERE task_id = :kabir_task;                  -- UPDATE 0
SELECT name, email FROM users;                                              -- only Aarav
SELECT COUNT(*) AS my_notes FROM task_notes;
SELECT password_hash FROM users;                                            -- ERROR: permission denied
ROLLBACK;

-- writing a row for someone else breaks the policy's WITH CHECK (ERROR expected)
BEGIN;
SET LOCAL ROLE dcd_student;
SELECT set_config('app.user_id', :'aarav', true);
INSERT INTO study_availability (user_id, available_date, available_hours)
VALUES (:kabir, CURRENT_DATE + 200, 4);
ROLLBACK;

-- the same tables as dcd_admin: every row
BEGIN;
SET LOCAL ROLE dcd_admin;
SELECT COUNT(*) AS all_tasks FROM tasks;
SELECT COUNT(*) AS all_users FROM users;
ROLLBACK;

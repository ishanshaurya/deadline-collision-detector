-- =====================================================================
-- Views
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_task_details: one row per task with course, team, dependency counts and
-- state (status, or OVERDUE when an unfinished task is past its deadline;
-- the complement of fn_upcoming_tasks among unfinished tasks)
-- ---------------------------------------------------------------------
CREATE VIEW v_task_details AS
SELECT t.task_id, t.user_id,
       t.course_id, c.course_code, c.course_name, c.course_type,
       t.title, t.description, t.task_type, t.deadline, t.estimated_hours,
       t.priority, t.status, t.created_at, t.updated_at,
       t.team_id, tm.name AS team_name,
       CASE WHEN t.team_id IS NULL THEN 'INDIVIDUAL' ELSE 'TEAM' END             AS work_mode,
       CASE WHEN t.status <> 'COMPLETED' AND t.deadline < LOCALTIMESTAMP
            THEN 'OVERDUE' ELSE t.status::text END                                         AS state,
       (SELECT COUNT(*) FROM task_dependencies d WHERE d.task_id = t.task_id)              AS prerequisite_count,
       (SELECT COUNT(*) FROM task_dependencies d WHERE d.prerequisite_task_id = t.task_id) AS dependent_count
FROM tasks t
JOIN courses c    ON c.course_id = t.course_id
LEFT JOIN teams tm ON tm.team_id = t.team_id;

-- ---------------------------------------------------------------------

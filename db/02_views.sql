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
-- v_course_workload: open hours per student per course, the course's
-- share of that student's total, and its rank (window functions)
-- ---------------------------------------------------------------------
CREATE VIEW v_course_workload AS
WITH per_course AS (
    SELECT e.user_id, c.course_id, c.course_code, c.course_name, c.course_type, c.semester, c.credits,
           COUNT(t.task_id) FILTER (WHERE t.status <> 'COMPLETED')                    AS pending_tasks,
           COUNT(t.task_id) FILTER (WHERE t.status =  'COMPLETED')                    AS completed_tasks,
           COALESCE(SUM(t.estimated_hours) FILTER (WHERE t.status <> 'COMPLETED'), 0) AS pending_hours
    FROM enrollments e
    JOIN courses c    ON c.course_id = e.course_id
    LEFT JOIN tasks t ON t.user_id = e.user_id AND t.course_id = e.course_id
    GROUP BY e.user_id, c.course_id, c.course_code, c.course_name, c.course_type, c.semester, c.credits
)
SELECT *,
       ROUND(100.0 * pending_hours / NULLIF(SUM(pending_hours) OVER (PARTITION BY user_id), 0), 1) AS share_pct,
       ROUND(pending_hours / credits, 2)                                                          AS hours_per_credit,
       RANK() OVER (PARTITION BY user_id ORDER BY pending_hours DESC)                             AS load_rank
FROM per_course;

-- ---------------------------------------------------------------------
-- v_user_summary: task counts per user (aggregate + FILTER)
-- ---------------------------------------------------------------------
CREATE VIEW v_user_summary AS
SELECT u.user_id, u.name,
       COUNT(t.task_id) FILTER (WHERE t.state <> 'COMPLETED') AS pending_tasks,
       COUNT(t.task_id) FILTER (WHERE t.state =  'OVERDUE')   AS overdue_tasks
FROM users u
LEFT JOIN v_task_details t ON t.user_id = u.user_id
GROUP BY u.user_id, u.name;

-- ---------------------------------------------------------------------
-- v_course_staff: who to contact for each course, with office hours
-- folded into one readable line (string_agg ordered by day and time)
-- ---------------------------------------------------------------------
CREATE VIEW v_course_staff AS
SELECT cs.course_id, cs.role, s.staff_id, s.name, s.email, s.phone, s.cabin,
       (SELECT string_agg(to_char(DATE '2024-01-07' + oh.weekday, 'Dy') || ' '
                          || to_char(oh.starts_at, 'HH24:MI') || '-' || to_char(oh.ends_at, 'HH24:MI'),
                          ', ' ORDER BY oh.weekday, oh.starts_at)
        FROM office_hours oh
        WHERE oh.staff_id = s.staff_id) AS office_hours
FROM course_staff cs
JOIN staff s ON s.staff_id = cs.staff_id;

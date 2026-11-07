-- =====================================================================
-- Demo queries for the viva (run with psql). Each block is tagged with
-- the syllabus concept it demonstrates.
-- =====================================================================

SELECT user_id AS aarav FROM users WHERE email = 'aarav@dcd.edu' \gset
SELECT user_id AS kabir FROM users WHERE email = 'kabir@dcd.edu' \gset
SELECT user_id AS diya  FROM users WHERE email = 'diya@dcd.edu'  \gset
SELECT task_id AS ml_report FROM tasks WHERE user_id = :aarav AND title = 'ML project report' \gset

-- [Set operations: INTERSECT] courses taken by both Aarav and Kabir
SELECT c.course_code, c.course_name FROM enrollments e JOIN courses c USING (course_id) WHERE e.user_id = :aarav
INTERSECT
SELECT c.course_code, c.course_name FROM enrollments e JOIN courses c USING (course_id) WHERE e.user_id = :kabir;

-- [Set operations: EXCEPT] Aarav's courses with no pending work at all
SELECT course_id FROM enrollments WHERE user_id = :aarav
EXCEPT
SELECT course_id FROM tasks WHERE user_id = :aarav AND status <> 'COMPLETED';

-- [Set operations: UNION] one timeline of events: deadlines and zero-availability days
SELECT deadline::date AS day, 'DEADLINE: ' || title AS event FROM tasks
 WHERE user_id = :aarav AND status <> 'COMPLETED'
UNION ALL
SELECT available_date, 'NO STUDY TIME' FROM study_availability
 WHERE user_id = :aarav AND available_hours < 2 AND available_date >= CURRENT_DATE
ORDER BY day;

-- [Aggregates + GROUP BY + HAVING] task types that dominate a student's load
SELECT user_id, task_type, COUNT(*) AS n, SUM(estimated_hours) AS hours
FROM tasks
WHERE status <> 'COMPLETED'
GROUP BY user_id, task_type
HAVING SUM(estimated_hours) > 10
ORDER BY user_id, hours DESC;

-- [NULL handling + outer join] every enrolled course, including ones with no tasks yet
SELECT c.course_code, COUNT(t.task_id) AS tasks, COALESCE(SUM(t.estimated_hours), 0) AS hours
FROM enrollments e
JOIN courses c       ON c.course_id = e.course_id
LEFT JOIN tasks t    ON t.user_id = e.user_id AND t.course_id = e.course_id
WHERE e.user_id = :diya
GROUP BY c.course_code;

-- [Nested subquery] students whose pending hours exceed the class average
SELECT u.name, SUM(t.estimated_hours) AS pending_hours
FROM users u JOIN tasks t ON t.user_id = u.user_id
WHERE t.status <> 'COMPLETED'
GROUP BY u.user_id, u.name
HAVING SUM(t.estimated_hours) > (
    SELECT AVG(per_user) FROM (
        SELECT SUM(estimated_hours) AS per_user
        FROM tasks WHERE status <> 'COMPLETED' GROUP BY user_id
    ) s
);

-- [Correlated subquery] each task that is the largest pending task in its course for that student
SELECT t.user_id, t.title, t.estimated_hours
FROM tasks t
WHERE t.status <> 'COMPLETED'
  AND t.estimated_hours = (
      SELECT MAX(t2.estimated_hours) FROM tasks t2
      WHERE t2.user_id = t.user_id AND t2.course_id = t.course_id AND t2.status <> 'COMPLETED'
  );

-- [Correlated EXISTS / NOT EXISTS] pending tasks that are ready to start (no unfinished prerequisite)
SELECT t.task_id, t.title, t.deadline
FROM tasks t
WHERE t.user_id = :aarav AND t.status <> 'COMPLETED'
  AND NOT EXISTS (
      SELECT 1 FROM task_dependencies d JOIN tasks p ON p.task_id = d.prerequisite_task_id
      WHERE d.task_id = t.task_id AND p.status <> 'COMPLETED'
  )
ORDER BY t.deadline;

-- [Self-join] pairwise collisions
SELECT * FROM fn_collision_pairs(:aarav, 48, LOCALTIMESTAMP);

-- [Recursive CTE] full prerequisite chain of the ML report
SELECT * FROM fn_prerequisites(:ml_report);

-- [Recursive CTE] total hours that must be done before a task can be submitted
WITH RECURSIVE needs(task_id) AS (
    SELECT :ml_report
    UNION
    SELECT d.prerequisite_task_id FROM task_dependencies d JOIN needs n ON d.task_id = n.task_id
)
SELECT SUM(t.estimated_hours) AS hours_including_prerequisites
FROM needs JOIN tasks t USING (task_id)
WHERE t.status <> 'COMPLETED';

-- [Window functions] EDF feasibility (running SUM), see fn_task_risk
SELECT title, deadline, estimated_hours, cumulative_demand, capacity_by_deadline, slack_hours, level
FROM fn_task_risk(:aarav, LOCALTIMESTAMP);

-- [Window functions: LEAD] gap to the next deadline, smallest gaps first
SELECT title, deadline,
       LEAD(title)    OVER w AS next_task,
       LEAD(deadline) OVER w - deadline AS gap
FROM tasks
WHERE user_id = :aarav AND status <> 'COMPLETED' AND deadline >= LOCALTIMESTAMP
WINDOW w AS (ORDER BY deadline)
ORDER BY gap NULLS LAST
LIMIT 5;

-- [Window functions: DENSE_RANK + PARTITION] busiest week per student
SELECT * FROM (
    SELECT user_id, date_trunc('week', deadline)::date AS week, SUM(estimated_hours) AS hours,
           DENSE_RANK() OVER (PARTITION BY user_id ORDER BY SUM(estimated_hours) DESC) AS rnk
    FROM tasks WHERE status <> 'COMPLETED'
    GROUP BY user_id, date_trunc('week', deadline)
) ranked
WHERE rnk = 1;

-- [Gaps and islands] collision clusters and high-risk periods
SELECT * FROM fn_collision_clusters(:aarav, 48, 7, LOCALTIMESTAMP);
SELECT risk_period, MIN(day) AS from_day, MAX(day) AS to_day, MAX(pressure) AS peak_pressure
FROM fn_daily_pressure(:aarav, 28, 7, LOCALTIMESTAMP)
WHERE level = 'CRITICAL'
GROUP BY risk_period ORDER BY risk_period;

-- [Weekly overload]
SELECT * FROM fn_weekly_load(:aarav, 6, LOCALTIMESTAMP);

-- [Full-text search] websearch syntax with ranking and highlighted snippet
SELECT * FROM fn_search_tasks(:aarav, 'project -report', '<b>', '</b>');

-- =====================================================================
-- [Query processing and optimization] compare plans with and without
-- the composite index. Small tables may still pick a seq scan; the
-- SET below forces the planner to show the index path for comparison.
-- =====================================================================
EXPLAIN ANALYZE
SELECT * FROM tasks WHERE user_id = :aarav AND deadline BETWEEN LOCALTIMESTAMP AND LOCALTIMESTAMP + INTERVAL '7 days';

SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT * FROM tasks WHERE user_id = :aarav AND deadline BETWEEN LOCALTIMESTAMP AND LOCALTIMESTAMP + INTERVAL '7 days';
EXPLAIN ANALYZE
SELECT task_id FROM tasks WHERE search_vector @@ websearch_to_tsquery('english', 'spark');
RESET enable_seqscan;

-- [Join + string_agg] who to contact for each of Aarav's courses
SELECT c.course_code, c.course_type, s.role, s.name, s.cabin, s.office_hours
FROM enrollments e
JOIN courses c        USING (course_id)
JOIN v_course_staff s USING (course_id)
WHERE e.user_id = :aarav
ORDER BY c.course_code, s.role;

-- [Outer join + GROUP BY] team vs individual workload per subject
SELECT course_code, work_mode, COUNT(*) AS tasks, SUM(estimated_hours) AS hours
FROM v_task_details
WHERE user_id = :aarav AND state <> 'COMPLETED'
GROUP BY ROLLUP (course_code, work_mode)
ORDER BY course_code NULLS LAST, work_mode NULLS LAST;

-- [Composite FK] a team can only be used by tasks of its own subject (ERROR expected)
-- UPDATE tasks SET team_id = (SELECT team_id FROM teams WHERE name = 'Query Crew')
--  WHERE user_id = :aarav AND title = 'ML midterm exam';

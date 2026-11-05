-- =====================================================================
-- Functions and triggers
-- Analytics take p_now so they can be evaluated at any instant; the app
-- passes LOCALTIMESTAMP.
-- =====================================================================

-- =====================================================================
-- BUILDING BLOCKS
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_load_level: the one severity scale used by every analytic
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_load_level(p_demand DECIMAL, p_capacity DECIMAL)
RETURNS load_level AS $$
    SELECT CASE
        WHEN p_demand <= 0                  THEN 'NONE'
        WHEN p_demand >  p_capacity         THEN 'CRITICAL'
        WHEN p_demand >= 0.8 * p_capacity   THEN 'HIGH'
        WHEN p_demand >= 0.6 * p_capacity   THEN 'MEDIUM'
        ELSE 'LOW'
    END::load_level;
$$ LANGUAGE sql IMMUTABLE;

-- NULL means work is due with no hours to do it in
CREATE FUNCTION fn_load_ratio(p_demand DECIMAL, p_capacity DECIMAL)
RETURNS DECIMAL AS $$
    SELECT CASE WHEN p_demand <= 0 THEN 0 ELSE ROUND(p_demand / NULLIF(p_capacity, 0), 2) END;
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION fn_is_weekend(p_day DATE)
RETURNS BOOLEAN AS $$
    SELECT EXTRACT(ISODOW FROM p_day) IN (6, 7);
$$ LANGUAGE sql IMMUTABLE;

-- a prerequisite is late when it is unfinished and due after the task needing it
CREATE FUNCTION fn_is_late_prerequisite(p_status task_status, p_deadline TIMESTAMP, p_needed_by TIMESTAMP)
RETURNS BOOLEAN AS $$
    SELECT p_status <> 'COMPLETED' AND p_deadline > p_needed_by;
$$ LANGUAGE sql IMMUTABLE;

-- ---------------------------------------------------------------------
-- fn_upcoming_tasks: work still to do (not completed, deadline not passed);
-- the unfinished tasks it excludes are the ones v_task_details marks OVERDUE
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_upcoming_tasks(p_user_id INTEGER, p_now TIMESTAMP)
RETURNS TABLE (
    task_id          INTEGER,
    course_id        INTEGER,
    course_code      VARCHAR,
    title            VARCHAR,
    task_type        task_kind,
    deadline         TIMESTAMP,
    estimated_hours  DECIMAL,
    priority         INTEGER
) AS $$
    SELECT t.task_id, t.course_id, c.course_code, t.title, t.task_type,
           t.deadline, t.estimated_hours, t.priority
    FROM tasks t
    JOIN courses c ON c.course_id = t.course_id
    WHERE t.user_id = p_user_id
      AND t.status <> 'COMPLETED'
      AND t.deadline >= p_now;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_daily_ledger: one row per day with the upcoming hours due that day
-- and the study hours available that day
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_daily_ledger(
    p_user_id INTEGER,
    p_from    DATE,
    p_to      DATE,
    p_now     TIMESTAMP
)
RETURNS TABLE (
    day              DATE,
    tasks_due        INTEGER,
    due_hours        DECIMAL,
    available_hours  DECIMAL
) AS $$
    SELECT d::date,
           COALESCE(due.n, 0)::INTEGER,
           COALESCE(due.hours, 0),
           COALESCE(a.available_hours, 0)
    FROM generate_series(p_from, p_to, INTERVAL '1 day') d
    LEFT JOIN (
        SELECT u.deadline::date AS day, COUNT(*) AS n, SUM(u.estimated_hours) AS hours
        FROM fn_upcoming_tasks(p_user_id, p_now) u
        GROUP BY u.deadline::date
    ) due ON due.day = d::date
    LEFT JOIN study_availability a
           ON a.user_id = p_user_id AND a.available_date = d::date;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------

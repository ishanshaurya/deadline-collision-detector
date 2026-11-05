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
-- fn_prerequisites / fn_dependents: transitive closure of the
-- dependency graph in each direction, each task once at its shallowest
-- depth. The visited array stops the walk if a cycle exists.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_prerequisites(p_task_id INTEGER)
RETURNS TABLE (
    task_id          INTEGER,
    title            VARCHAR,
    deadline         TIMESTAMP,
    estimated_hours  DECIMAL,
    state            TEXT,
    depth            INTEGER,
    due_after_task   BOOLEAN
) AS $$
    WITH RECURSIVE walk(task_id, depth, visited) AS (
        SELECT d.prerequisite_task_id, 1, ARRAY[d.prerequisite_task_id]
        FROM task_dependencies d
        WHERE d.task_id = p_task_id
        UNION ALL
        SELECT d.prerequisite_task_id, w.depth + 1, w.visited || d.prerequisite_task_id
        FROM walk w
        JOIN task_dependencies d ON d.task_id = w.task_id
        WHERE NOT d.prerequisite_task_id = ANY (w.visited)
    ),
    shallowest AS (
        SELECT DISTINCT ON (w.task_id) w.task_id, w.depth
        FROM walk w
        ORDER BY w.task_id, w.depth
    )
    SELECT t.task_id, t.title, t.deadline, t.estimated_hours, t.state, s.depth,
           fn_is_late_prerequisite(t.status, t.deadline, root.deadline)
    FROM shallowest s
    JOIN v_task_details t ON t.task_id = s.task_id
    JOIN tasks root       ON root.task_id = p_task_id
    ORDER BY s.depth, t.deadline;
$$ LANGUAGE sql STABLE;

CREATE FUNCTION fn_dependents(p_task_id INTEGER)
RETURNS TABLE (
    task_id   INTEGER,
    title     VARCHAR,
    deadline  TIMESTAMP,
    state     TEXT,
    depth     INTEGER
) AS $$
    WITH RECURSIVE walk(task_id, depth, visited) AS (
        SELECT d.task_id, 1, ARRAY[d.task_id]
        FROM task_dependencies d
        WHERE d.prerequisite_task_id = p_task_id
        UNION ALL
        SELECT d.task_id, w.depth + 1, w.visited || d.task_id
        FROM walk w
        JOIN task_dependencies d ON d.prerequisite_task_id = w.task_id
        WHERE NOT d.task_id = ANY (w.visited)
    ),
    shallowest AS (
        SELECT DISTINCT ON (w.task_id) w.task_id, w.depth
        FROM walk w
        ORDER BY w.task_id, w.depth
    )
    SELECT t.task_id, t.title, t.deadline, t.state, s.depth
    FROM shallowest s
    JOIN v_task_details t ON t.task_id = s.task_id
    ORDER BY s.depth, t.deadline;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- v_dependency_edges: each direct dependency, flagged when the
-- prerequisite is late
-- ---------------------------------------------------------------------
CREATE VIEW v_dependency_edges AS
SELECT d.dependency_id, d.task_id, d.prerequisite_task_id,
       fn_is_late_prerequisite(p.status, p.deadline, t.deadline) AS inverted
FROM task_dependencies d
JOIN tasks t ON t.task_id = d.task_id
JOIN tasks p ON p.task_id = d.prerequisite_task_id;

-- =====================================================================
-- TRIGGERS
-- =====================================================================

CREATE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tasks_updated_at
    BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------
-- validate a dependency edge after it is written:
--   * both tasks belong to the same student
--   * the graph has no cycle: the task must not be its own prerequisite
-- The per-user advisory lock serialises concurrent edits; without it two
-- transactions could each add half of a cycle and neither would see it.
-- ---------------------------------------------------------------------
CREATE FUNCTION trg_validate_dependency() RETURNS TRIGGER AS $$
DECLARE
    v_user_task   INTEGER;
    v_user_prereq INTEGER;
BEGIN
    SELECT user_id INTO v_user_task   FROM tasks WHERE task_id = NEW.task_id;
    SELECT user_id INTO v_user_prereq FROM tasks WHERE task_id = NEW.prerequisite_task_id;

    IF v_user_task IS DISTINCT FROM v_user_prereq THEN
        RAISE EXCEPTION 'Task % and prerequisite % belong to different users',
            NEW.task_id, NEW.prerequisite_task_id
            USING ERRCODE = 'check_violation';
    END IF;

    PERFORM pg_advisory_xact_lock(v_user_task);

    IF EXISTS (SELECT 1 FROM fn_prerequisites(NEW.task_id) p WHERE p.task_id = NEW.task_id) THEN
        RAISE EXCEPTION 'Dependency % -> % would create a cycle',
            NEW.task_id, NEW.prerequisite_task_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER task_dependencies_validate
    AFTER INSERT OR UPDATE ON task_dependencies
    FOR EACH ROW EXECUTE FUNCTION trg_validate_dependency();

-- ---------------------------------------------------------------------
-- a task cannot be COMPLETED while a prerequisite is not
-- ---------------------------------------------------------------------
CREATE FUNCTION trg_guard_completion() RETURNS TRIGGER AS $$
DECLARE
    v_blocking TEXT;
BEGIN
    IF NEW.status = 'COMPLETED' AND OLD.status <> 'COMPLETED' THEN
        SELECT string_agg(p.title, ', ' ORDER BY p.deadline) INTO v_blocking
        FROM task_dependencies d
        JOIN tasks p ON p.task_id = d.prerequisite_task_id
        WHERE d.task_id = NEW.task_id
          AND p.status <> 'COMPLETED';

        IF v_blocking IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot complete "%": unfinished prerequisites: %',
                NEW.title, v_blocking
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tasks_guard_completion
    BEFORE UPDATE OF status ON tasks
    FOR EACH ROW EXECUTE FUNCTION trg_guard_completion();

-- =====================================================================
-- ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_task_risk: deadline feasibility per upcoming task.
--
-- Work is scheduled Earliest-Deadline-First. For a single worker EDF is
-- optimal, so the task set is feasible iff for every deadline d:
--     (hours of upcoming tasks due by d) <= (study hours available by d)
-- slack_hours = capacity_by_deadline - cumulative_demand. Negative slack
-- means the deadline is missed under ANY ordering of the work.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_task_risk(p_user_id INTEGER, p_now TIMESTAMP)
RETURNS TABLE (
    task_id               INTEGER,
    title                 VARCHAR,
    course_code           VARCHAR,
    task_type             task_kind,
    deadline              TIMESTAMP,
    estimated_hours       DECIMAL,
    priority              INTEGER,
    cumulative_demand     DECIMAL,
    capacity_by_deadline  DECIMAL,
    slack_hours           DECIMAL,
    level                 load_level,
    dependency_inversion  BOOLEAN
) AS $$
    WITH demand AS (
        SELECT u.*,
               SUM(u.estimated_hours) OVER (
                   ORDER BY u.deadline RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS cumulative_demand
        FROM fn_upcoming_tasks(p_user_id, p_now) u
    ),
    capacity AS (
        SELECT l.day,
               SUM(l.available_hours) OVER (ORDER BY l.day) AS cumulative_capacity
        FROM fn_daily_ledger(p_user_id, p_now::date,
                             (SELECT MAX(deadline)::date FROM demand), p_now) l
    )
    SELECT d.task_id, d.title, d.course_code, d.task_type, d.deadline,
           d.estimated_hours, d.priority, d.cumulative_demand,
           c.cumulative_capacity,
           c.cumulative_capacity - d.cumulative_demand,
           fn_load_level(d.cumulative_demand, c.cumulative_capacity),
           EXISTS (SELECT 1 FROM v_dependency_edges e WHERE e.task_id = d.task_id AND e.inverted)
    FROM demand d
    JOIN capacity c ON c.day = d.deadline::date
    ORDER BY d.deadline, d.priority;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_collision_pairs: every pair of upcoming tasks due within
-- p_window_hours of each other (self-join)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_collision_pairs(
    p_user_id      INTEGER,
    p_window_hours INTEGER,
    p_now          TIMESTAMP
)
RETURNS TABLE (
    task_a_id      INTEGER, task_a VARCHAR, course_a VARCHAR, deadline_a TIMESTAMP,
    task_b_id      INTEGER, task_b VARCHAR, course_b VARCHAR, deadline_b TIMESTAMP,
    gap_hours      DECIMAL,
    combined_hours DECIMAL,
    cross_course   BOOLEAN
) AS $$
    WITH u AS (SELECT * FROM fn_upcoming_tasks(p_user_id, p_now))
    SELECT a.task_id, a.title, a.course_code, a.deadline,
           b.task_id, b.title, b.course_code, b.deadline,
           ROUND(ABS(EXTRACT(EPOCH FROM (b.deadline - a.deadline))) / 3600, 1),
           a.estimated_hours + b.estimated_hours,
           a.course_id <> b.course_id
    FROM u a
    JOIN u b
      ON b.task_id > a.task_id
     AND b.deadline BETWEEN a.deadline - make_interval(hours => p_window_hours)
                        AND a.deadline + make_interval(hours => p_window_hours)
    ORDER BY 9, a.deadline;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_collision_clusters: upcoming deadlines grouped into clusters where
-- consecutive deadlines are within p_window_hours of each other
-- (gaps-and-islands with LAG + running SUM). A cluster of 2+ tasks is a
-- deadline collision. Capacity = study hours in the p_lead_days up to
-- the cluster's last deadline.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_collision_clusters(
    p_user_id      INTEGER,
    p_window_hours INTEGER,
    p_lead_days    INTEGER,
    p_now          TIMESTAMP
)
RETURNS TABLE (
    cluster_id        INTEGER,
    starts_at         TIMESTAMP,
    ends_at           TIMESTAMP,
    task_count        INTEGER,
    total_hours       DECIMAL,
    available_hours   DECIMAL,
    pressure          DECIMAL,
    level             load_level,
    tasks             TEXT[]
) AS $$
    WITH upcoming AS (
        SELECT u.*,
               CASE WHEN u.deadline - LAG(u.deadline) OVER w
                         <= make_interval(hours => p_window_hours)
                    THEN 0 ELSE 1 END AS starts_cluster
        FROM fn_upcoming_tasks(p_user_id, p_now) u
        WINDOW w AS (ORDER BY u.deadline, u.task_id)
    ),
    numbered AS (
        SELECT *, SUM(starts_cluster) OVER (ORDER BY deadline, task_id) AS cluster_no
        FROM upcoming
    ),
    clusters AS (
        SELECT MIN(deadline) AS starts_at,
               MAX(deadline) AS ends_at,
               COUNT(*)::INTEGER AS task_count,
               SUM(estimated_hours) AS total_hours,
               array_agg(course_code || ': ' || title ORDER BY deadline) AS tasks
        FROM numbered
        GROUP BY cluster_no
        HAVING COUNT(*) >= 2
    ),
    ledger AS (
        SELECT * FROM fn_daily_ledger(p_user_id, p_now::date,
                                      (SELECT MAX(ends_at)::date FROM clusters), p_now)
    )
    SELECT (ROW_NUMBER() OVER (ORDER BY cl.starts_at))::INTEGER,
           cl.starts_at, cl.ends_at, cl.task_count, cl.total_hours,
           cap.hours,
           fn_load_ratio(cl.total_hours, cap.hours),
           fn_load_level(cl.total_hours, cap.hours),
           cl.tasks
    FROM clusters cl
    CROSS JOIN LATERAL (
        SELECT SUM(l.available_hours) AS hours
        FROM ledger l
        WHERE l.day BETWEEN cl.ends_at::date - p_lead_days + 1 AND cl.ends_at::date
    ) cap
    ORDER BY cl.starts_at;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_weekly_load: demand vs capacity per ISO week (Mon-Sun)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_weekly_load(
    p_user_id INTEGER,
    p_weeks   INTEGER,
    p_now     TIMESTAMP
)
RETURNS TABLE (
    week_start          DATE,
    tasks_due           INTEGER,
    demand_hours        DECIMAL,
    capacity_hours      DECIMAL,
    load_ratio          DECIMAL,
    cumulative_demand   DECIMAL,
    cumulative_capacity DECIMAL,
    level               load_level
) AS $$
    WITH weeks AS (
        SELECT date_trunc('week', l.day)::date AS week_start,
               SUM(l.tasks_due)::INTEGER AS tasks_due,
               SUM(l.due_hours)          AS demand_hours,
               SUM(l.available_hours)    AS capacity_hours
        FROM fn_daily_ledger(p_user_id, p_now::date,
                             date_trunc('week', p_now)::date + 7 * p_weeks - 1, p_now) l
        GROUP BY 1
    )
    SELECT week_start, tasks_due, demand_hours, capacity_hours,
           fn_load_ratio(demand_hours, capacity_hours),
           SUM(demand_hours)   OVER (ORDER BY week_start),
           SUM(capacity_hours) OVER (ORDER BY week_start),
           fn_load_level(demand_hours, capacity_hours)
    FROM weeks
    ORDER BY week_start;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_daily_pressure: for each day, hours due in the next p_window days
-- vs study hours in those same days (sliding window frame). Consecutive
-- CRITICAL days are merged into a numbered high-risk period.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_daily_pressure(
    p_user_id INTEGER,
    p_days    INTEGER,
    p_window  INTEGER,
    p_now     TIMESTAMP
)
RETURNS TABLE (
    day             DATE,
    due_hours       DECIMAL,
    available_hours DECIMAL,
    window_demand   DECIMAL,
    window_capacity DECIMAL,
    pressure        DECIMAL,
    level           load_level,
    risk_period     INTEGER
) AS $$
    WITH windowed AS (
        SELECT l.day, l.due_hours, l.available_hours,
               SUM(l.due_hours)       OVER w AS window_demand,
               SUM(l.available_hours) OVER w AS window_capacity
        FROM fn_daily_ledger(p_user_id, p_now::date, p_now::date + p_days + p_window - 2, p_now) l
        WINDOW w AS (ORDER BY l.day ROWS BETWEEN CURRENT ROW AND (p_window - 1) FOLLOWING)
    ),
    scored AS (
        SELECT *, fn_load_level(window_demand, window_capacity) AS level
        FROM windowed
        WHERE day < p_now::date + p_days
    ),
    islands AS (
        SELECT *,
               CASE WHEN level = 'CRITICAL'
                     AND LAG(level) OVER (ORDER BY day) IS DISTINCT FROM 'CRITICAL'
                    THEN 1 ELSE 0 END AS starts_period
        FROM scored
    )
    SELECT day, due_hours, available_hours, window_demand, window_capacity,
           fn_load_ratio(window_demand, window_capacity),
           level,
           CASE WHEN level = 'CRITICAL'
                THEN SUM(starts_period) OVER (ORDER BY day)::INTEGER
           END
    FROM islands
    ORDER BY day;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_focus_tasks: the tasks behind each dashboard number, so every
-- headline figure can be opened as a list
--   due_soon      upcoming, due within p_window_days
--   colliding     in at least one collision pair
--   infeasible    CRITICAL in the EDF feasibility check
--   overloaded    due in a CRITICAL week
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_focus_tasks(
    p_user_id      INTEGER,
    p_focus        TEXT,
    p_window_hours INTEGER,
    p_window_days  INTEGER,
    p_weeks        INTEGER,
    p_now          TIMESTAMP
)
RETURNS TABLE (task_id INTEGER) AS $$
    SELECT u.task_id FROM fn_upcoming_tasks(p_user_id, p_now) u
    WHERE p_focus = 'due_soon' AND u.deadline::date < p_now::date + p_window_days
    UNION
    SELECT unnest(ARRAY[p.task_a_id, p.task_b_id])
    FROM fn_collision_pairs(p_user_id, p_window_hours, p_now) p
    WHERE p_focus = 'colliding'
    UNION
    SELECT r.task_id FROM fn_task_risk(p_user_id, p_now) r
    WHERE p_focus = 'infeasible' AND r.level = 'CRITICAL'
    UNION
    SELECT u.task_id
    FROM fn_upcoming_tasks(p_user_id, p_now) u
    JOIN fn_weekly_load(p_user_id, p_weeks, p_now) w
      ON w.week_start = date_trunc('week', u.deadline)::date
    WHERE p_focus = 'overloaded' AND w.level = 'CRITICAL';
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_search_tasks: ranked full-text search over a student's tasks
-- (websearch syntax: "exact phrase", -exclude, or). The caller chooses
-- the markers that wrap matched words in the snippet.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_search_tasks(
    p_user_id   INTEGER,
    p_query     TEXT,
    p_start_sel TEXT,
    p_stop_sel  TEXT
)
RETURNS TABLE (
    task_id     INTEGER,
    title       VARCHAR,
    course_code VARCHAR,
    deadline    TIMESTAMP,
    state       TEXT,
    rank        REAL,
    snippet     TEXT
) AS $$
    SELECT t.task_id, t.title, v.course_code, t.deadline, v.state,
           ts_rank(t.search_vector, q),
           ts_headline('english', coalesce(t.description, t.title), q,
                       format('StartSel="%s", StopSel="%s", MaxWords=18, MinWords=6',
                              p_start_sel, p_stop_sel))
    FROM tasks t
    JOIN v_task_details v ON v.task_id = t.task_id,
         websearch_to_tsquery('english', p_query) q
    WHERE t.user_id = p_user_id
      AND t.search_vector @@ q
    ORDER BY 6 DESC, t.deadline;
$$ LANGUAGE sql STABLE;

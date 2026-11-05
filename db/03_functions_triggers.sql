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

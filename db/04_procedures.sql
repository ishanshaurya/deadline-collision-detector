-- =====================================================================
-- Stored procedures. Each runs inside the caller's transaction, so any
-- exception (including one raised by a trigger or constraint) rolls back
-- every change the procedure made.
-- =====================================================================

-- ---------------------------------------------------------------------
-- sp_add_task: insert a task and its prerequisites as one unit
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_add_task(
    p_user_id      INTEGER,
    p_course_id    INTEGER,
    p_title        VARCHAR,
    p_description  TEXT,
    p_task_type    task_kind,
    p_deadline     TIMESTAMP,
    p_hours        DECIMAL,
    p_priority     INTEGER,
    p_prereq_ids   INTEGER[],
    p_team_id      INTEGER,
    INOUT p_task_id INTEGER DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tasks (user_id, course_id, title, description, task_type,
                       deadline, estimated_hours, priority, team_id)
    VALUES (p_user_id, p_course_id, p_title, p_description, p_task_type,
            p_deadline, p_hours, p_priority, p_team_id)
    RETURNING task_id INTO p_task_id;

    INSERT INTO task_dependencies (task_id, prerequisite_task_id)
    SELECT DISTINCT p_task_id, x FROM unnest(p_prereq_ids) AS x;
END;
$$;

-- ---------------------------------------------------------------------

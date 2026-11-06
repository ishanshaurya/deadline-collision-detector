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
-- sp_reschedule_task: move a deadline. With p_cascade and a later
-- deadline, every unfinished transitive dependent moves by the same
-- amount. All affected rows are locked up front in task_id order so
-- concurrent reschedules cannot deadlock or interleave half-applied
-- shifts. p_shifted reports how many tasks moved.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_reschedule_task(
    p_user_id       INTEGER,
    p_task_id       INTEGER,
    p_new_deadline  TIMESTAMP,
    p_cascade       BOOLEAN,
    INOUT p_shifted INTEGER DEFAULT 0
)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_deadline TIMESTAMP;
    v_delta        INTERVAL;
BEGIN
    IF p_new_deadline < LOCALTIMESTAMP THEN
        RAISE EXCEPTION 'New deadline % is in the past', p_new_deadline;
    END IF;

    PERFORM 1
    FROM tasks t
    WHERE t.task_id = p_task_id
       OR (p_cascade AND t.task_id IN (SELECT task_id FROM fn_dependents(p_task_id)))
    ORDER BY t.task_id
    FOR UPDATE;

    SELECT deadline INTO v_old_deadline
    FROM tasks
    WHERE task_id = p_task_id AND user_id = p_user_id AND status <> 'COMPLETED';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found, not yours, or already completed', p_task_id;
    END IF;

    v_delta := p_new_deadline - v_old_deadline;
    UPDATE tasks SET deadline = p_new_deadline WHERE task_id = p_task_id;
    p_shifted := 1;

    IF p_cascade AND v_delta > INTERVAL '0' THEN
        UPDATE tasks
           SET deadline = deadline + v_delta
         WHERE task_id IN (SELECT task_id FROM fn_dependents(p_task_id))
           AND status <> 'COMPLETED';
        GET DIAGNOSTICS p_shifted = ROW_COUNT;
        p_shifted := p_shifted + 1;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_complete_task: mark done (trigger rejects if prerequisites pending)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_complete_task(p_user_id INTEGER, p_task_id INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE tasks
       SET status = 'COMPLETED'
     WHERE task_id = p_task_id
       AND user_id = p_user_id
       AND status <> 'COMPLETED';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task % not found, not yours, or already completed', p_task_id;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_set_availability: bulk upsert a weekday/weekend study pattern
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_set_availability(
    p_user_id        INTEGER,
    p_from           DATE,
    p_to             DATE,
    p_weekday_hours  DECIMAL,
    p_weekend_hours  DECIMAL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_to < p_from THEN
        RAISE EXCEPTION 'Date range is empty (% to %)', p_from, p_to;
    END IF;

    INSERT INTO study_availability (user_id, available_date, available_hours)
    SELECT p_user_id, d::date,
           CASE WHEN fn_is_weekend(d::date) THEN p_weekend_hours ELSE p_weekday_hours END
    FROM generate_series(p_from, p_to, INTERVAL '1 day') AS d
    ON CONFLICT (user_id, available_date)
    DO UPDATE SET available_hours = EXCLUDED.available_hours;
END;
$$;

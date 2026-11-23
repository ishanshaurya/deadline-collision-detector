-- =====================================================================
-- Roles and access control
-- 1. Application roles. users.role is STUDENT or ADMIN. Admin-only work
--    goes through procedures and views that check the caller's role in
--    the database, so a non-admin is refused whatever client calls them.
-- 2. Database roles. dcd_student and dcd_admin get GRANTs, and row-level
--    security limits a student session to its own rows.
-- The web app connects as the table owner, which bypasses row-level
-- security, so it relies on (1) and on user_id predicates in every query.
-- demo/rbac.sql shows (2) in psql.
-- =====================================================================

CREATE FUNCTION fn_is_admin(p_user_id INTEGER)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM users WHERE user_id = p_user_id AND role = 'ADMIN');
$$ LANGUAGE sql STABLE;

CREATE FUNCTION fn_assert_admin(p_actor INTEGER)
RETURNS VOID AS $$
BEGIN
    IF NOT fn_is_admin(p_actor) THEN
        RAISE EXCEPTION 'Permission denied: user % is not an ADMIN', p_actor
            USING ERRCODE = 'insufficient_privilege';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- v_admin_overview: every account with its workload. Read it as
--   SELECT * FROM v_admin_overview WHERE fn_is_admin(<caller>)
-- so a non-admin caller gets no rows.
-- ---------------------------------------------------------------------
CREATE VIEW v_admin_overview AS
SELECT u.user_id, u.name, u.email, u.role, u.created_at,
       (SELECT COUNT(*) FROM enrollments e WHERE e.user_id = u.user_id)                        AS courses,
       s.pending_tasks, s.overdue_tasks,
       (SELECT COALESCE(SUM(t.estimated_hours), 0) FROM tasks t
        WHERE t.user_id = u.user_id AND t.status <> 'COMPLETED')                               AS pending_hours,
       (SELECT COUNT(*) FROM fn_task_risk(u.user_id, LOCALTIMESTAMP) r WHERE r.level = 'CRITICAL') AS critical_tasks
FROM users u
JOIN v_user_summary s ON s.user_id = u.user_id;

-- ---------------------------------------------------------------------
-- sp_admin_set_role: change an account's role. The ADMIN rows are locked
-- first so two admins demoting each other at once can't leave zero.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_admin_set_role(p_actor INTEGER, p_user_id INTEGER, p_role VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
    v_current VARCHAR;
BEGIN
    PERFORM fn_assert_admin(p_actor);
    PERFORM 1 FROM users WHERE role = 'ADMIN' ORDER BY user_id FOR UPDATE;

    SELECT role INTO v_current FROM users WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id;
    END IF;

    IF v_current = 'ADMIN' AND p_role <> 'ADMIN'
       AND (SELECT COUNT(*) FROM users WHERE role = 'ADMIN') = 1 THEN
        RAISE EXCEPTION 'Cannot remove the last ADMIN';
    END IF;

    UPDATE users SET role = p_role WHERE user_id = p_user_id;
END;
$$;

-- sp_admin_add_course: only an ADMIN can add to the course catalogue
CREATE PROCEDURE sp_admin_add_course(
    p_actor        INTEGER,
    p_code         VARCHAR,
    p_name         VARCHAR,
    p_type         course_type,
    p_semester     INTEGER,
    p_credits      INTEGER,
    p_description  TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_assert_admin(p_actor);
    INSERT INTO courses (course_code, course_name, course_type, semester, credits, description)
    VALUES (upper(btrim(p_code)), btrim(p_name), p_type, p_semester, p_credits, NULLIF(btrim(p_description), ''));
END;
$$;

-- =====================================================================
-- Database roles, GRANTs and row-level security
-- Roles belong to the whole server, so they are created only once.
-- =====================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dcd_student') THEN
        CREATE ROLE dcd_student NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dcd_admin') THEN
        CREATE ROLE dcd_admin NOLOGIN;
    END IF;
END $$;

-- the student a session acts for, set with set_config('app.user_id', ...)
CREATE FUNCTION fn_app_user()
RETURNS INTEGER AS $$
    SELECT NULLIF(current_setting('app.user_id', true), '')::int;
$$ LANGUAGE sql STABLE;

-- views check permissions and row-level security as the querying role
ALTER VIEW v_task_details     SET (security_invoker = on);
ALTER VIEW v_course_workload  SET (security_invoker = on);
ALTER VIEW v_user_summary     SET (security_invoker = on);
ALTER VIEW v_course_staff     SET (security_invoker = on);
ALTER VIEW v_dependency_edges SET (security_invoker = on);
ALTER VIEW v_task_notes       SET (security_invoker = on);
ALTER VIEW v_admin_overview   SET (security_invoker = on);

GRANT USAGE ON SCHEMA public TO dcd_student, dcd_admin;

-- students: read the catalogue, work on their own rows, never see password hashes
GRANT SELECT ON courses, staff, course_staff, office_hours TO dcd_student;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON enrollments, tasks, task_dependencies, study_availability, teams, team_members, task_notes
    TO dcd_student;
GRANT SELECT ON task_embeddings TO dcd_student;
GRANT SELECT (user_id, name, email, role, created_at) ON users TO dcd_student;
GRANT SELECT ON v_task_details, v_course_workload, v_user_summary, v_course_staff,
                v_dependency_edges, v_task_notes
    TO dcd_student;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO dcd_student;

-- admins: everything
GRANT ALL ON ALL TABLES    IN SCHEMA public TO dcd_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO dcd_admin;

ALTER TABLE users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_dependencies  ENABLE ROW LEVEL SECURITY;
ALTER TABLE study_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams              ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members       ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_notes         ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_embeddings    ENABLE ROW LEVEL SECURITY;

-- a student sees only their own account and rows that carry their user_id
CREATE POLICY student_self ON users FOR SELECT TO dcd_student
    USING (user_id = fn_app_user());
CREATE POLICY student_own ON enrollments FOR ALL TO dcd_student
    USING (user_id = fn_app_user()) WITH CHECK (user_id = fn_app_user());
CREATE POLICY student_own ON tasks FOR ALL TO dcd_student
    USING (user_id = fn_app_user()) WITH CHECK (user_id = fn_app_user());
CREATE POLICY student_own ON study_availability FOR ALL TO dcd_student
    USING (user_id = fn_app_user()) WITH CHECK (user_id = fn_app_user());
CREATE POLICY student_own ON teams FOR ALL TO dcd_student
    USING (user_id = fn_app_user()) WITH CHECK (user_id = fn_app_user());

-- child rows are visible when their parent is (the subquery is itself
-- filtered by the parent's policy)
CREATE POLICY student_own ON task_dependencies FOR ALL TO dcd_student
    USING      (EXISTS (SELECT 1 FROM tasks t WHERE t.task_id = task_dependencies.task_id))
    WITH CHECK (EXISTS (SELECT 1 FROM tasks t WHERE t.task_id = task_dependencies.task_id));
CREATE POLICY student_own ON team_members FOR ALL TO dcd_student
    USING      (EXISTS (SELECT 1 FROM teams t WHERE t.team_id = team_members.team_id))
    WITH CHECK (EXISTS (SELECT 1 FROM teams t WHERE t.team_id = team_members.team_id));
CREATE POLICY student_own ON task_notes FOR ALL TO dcd_student
    USING      (EXISTS (SELECT 1 FROM tasks t WHERE t.task_id = task_notes.task_id))
    WITH CHECK (EXISTS (SELECT 1 FROM tasks t WHERE t.task_id = task_notes.task_id));
CREATE POLICY student_own ON task_embeddings FOR SELECT TO dcd_student
    USING (EXISTS (SELECT 1 FROM tasks t WHERE t.task_id = task_embeddings.task_id));

-- an admin session sees every row
CREATE POLICY admin_all ON users              FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON enrollments        FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON tasks              FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON task_dependencies  FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON study_availability FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON teams              FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON team_members       FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON task_notes         FOR ALL TO dcd_admin USING (true) WITH CHECK (true);
CREATE POLICY admin_all ON task_embeddings    FOR ALL TO dcd_admin USING (true) WITH CHECK (true);

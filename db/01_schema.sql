-- =====================================================================
-- Deadline Collision Detector: schema (PostgreSQL 14+)
-- =====================================================================

-- Setup owns this whole database: every run starts from an empty schema.
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

CREATE EXTENSION pgcrypto;
CREATE EXTENSION citext;

CREATE TYPE task_kind   AS ENUM ('ASSIGNMENT', 'EXAM', 'QUIZ', 'PROJECT', 'LAB', 'READING');
CREATE TYPE task_status AS ENUM ('PENDING', 'IN_PROGRESS', 'COMPLETED');
CREATE TYPE load_level  AS ENUM ('NONE', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL');
CREATE TYPE course_type AS ENUM ('CC', 'EC');                 -- core course, elective course
CREATE TYPE staff_role  AS ENUM ('PROFESSOR', 'TA');

-- ---------------------------------------------------------------------
-- USERS
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id        SERIAL PRIMARY KEY,
    name           VARCHAR(100) NOT NULL,
    email          CITEXT UNIQUE NOT NULL,
    password_hash  TEXT NOT NULL,
    role           VARCHAR(20) NOT NULL DEFAULT 'STUDENT',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_name  CHECK (btrim(name) <> ''),
    CONSTRAINT valid_role  CHECK (role IN ('STUDENT', 'ADMIN')),
    CONSTRAINT valid_email CHECK (email LIKE '%_@_%._%')
);

-- ---------------------------------------------------------------------
-- COURSES
-- ---------------------------------------------------------------------
CREATE TABLE courses (
    course_id    SERIAL PRIMARY KEY,
    course_code  VARCHAR(20) UNIQUE NOT NULL,
    course_name  VARCHAR(150) NOT NULL,
    course_type  course_type NOT NULL,
    semester     INTEGER NOT NULL,
    credits      INTEGER NOT NULL,
    description  TEXT,
    CONSTRAINT valid_credits  CHECK (credits > 0 AND credits <= 10),
    CONSTRAINT valid_semester CHECK (semester BETWEEN 1 AND 8)
);

-- ---------------------------------------------------------------------
-- STAFF, COURSE_STAFF (M:N with a role), OFFICE_HOURS (STAFF 1:N)
-- ---------------------------------------------------------------------
CREATE TABLE staff (
    staff_id  SERIAL PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    email     CITEXT UNIQUE NOT NULL,
    phone     VARCHAR(20),
    cabin     VARCHAR(100),
    CONSTRAINT valid_staff_email CHECK (email LIKE '%_@_%._%')
);

CREATE TABLE course_staff (
    course_id  INTEGER NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    staff_id   INTEGER NOT NULL REFERENCES staff(staff_id)    ON DELETE CASCADE,
    role       staff_role NOT NULL,
    PRIMARY KEY (course_id, staff_id)
);

CREATE TABLE office_hours (
    office_hour_id  SERIAL PRIMARY KEY,
    staff_id        INTEGER NOT NULL REFERENCES staff(staff_id) ON DELETE CASCADE,
    weekday         INTEGER NOT NULL,                          -- ISO: 1 = Monday
    starts_at       TIME NOT NULL,
    ends_at         TIME NOT NULL,
    CONSTRAINT valid_weekday CHECK (weekday BETWEEN 1 AND 7),
    CONSTRAINT valid_hours   CHECK (ends_at > starts_at)
);

-- ---------------------------------------------------------------------
-- ENROLLMENTS  (associative entity for USERS M:N COURSES)
-- ---------------------------------------------------------------------
CREATE TABLE enrollments (
    enrollment_id  SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL REFERENCES users(user_id)     ON DELETE CASCADE,
    course_id      INTEGER NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    enrolled_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_enrollment UNIQUE (user_id, course_id)
);

-- ---------------------------------------------------------------------
-- TEAMS (a student's team for one course) and TEAM_MEMBERS
-- ---------------------------------------------------------------------
CREATE TABLE teams (
    team_id    SERIAL PRIMARY KEY,
    user_id    INTEGER NOT NULL,
    course_id  INTEGER NOT NULL,
    name       VARCHAR(100) NOT NULL,
    CONSTRAINT uq_team_scope UNIQUE (team_id, user_id, course_id),
    CONSTRAINT fk_team_enrollment FOREIGN KEY (user_id, course_id)
        REFERENCES enrollments(user_id, course_id) ON DELETE CASCADE
);

CREATE TABLE team_members (
    member_id  SERIAL PRIMARY KEY,
    team_id    INTEGER NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
    name       VARCHAR(100) NOT NULL,
    srn        VARCHAR(20),
    email      CITEXT,
    phone      VARCHAR(20),
    role       VARCHAR(60) NOT NULL,
    CONSTRAINT uq_member_srn UNIQUE (team_id, srn)
);

-- ---------------------------------------------------------------------
-- TASKS
-- fk_task_enrollment: a student only has tasks for courses they take.
-- fk_task_team: a team task uses one of that student's teams for the
-- same course; team_id NULL means individual work.
-- ---------------------------------------------------------------------
CREATE TABLE tasks (
    task_id          SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(user_id)     ON DELETE CASCADE,
    course_id        INTEGER NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    title            VARCHAR(200) NOT NULL,
    description      TEXT,
    task_type        task_kind NOT NULL,
    deadline         TIMESTAMP NOT NULL,
    estimated_hours  DECIMAL(5,2) NOT NULL,
    priority         INTEGER NOT NULL DEFAULT 3,                -- 1 = highest
    status           task_status NOT NULL DEFAULT 'PENDING',
    team_id          INTEGER,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    search_vector    TSVECTOR GENERATED ALWAYS AS (
                         setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
                         setweight(to_tsvector('english', coalesce(description, '')), 'B')
                     ) STORED,
    CONSTRAINT valid_hours     CHECK (estimated_hours > 0),
    CONSTRAINT valid_priority  CHECK (priority BETWEEN 1 AND 5),
    CONSTRAINT fk_task_enrollment FOREIGN KEY (user_id, course_id)
        REFERENCES enrollments(user_id, course_id) ON DELETE CASCADE,
    CONSTRAINT fk_task_team FOREIGN KEY (team_id, user_id, course_id)
        REFERENCES teams(team_id, user_id, course_id) ON DELETE SET NULL (team_id)
);

-- ---------------------------------------------------------------------
-- STUDY_AVAILABILITY  (USERS 1:N, one row per user per day)
-- ---------------------------------------------------------------------
CREATE TABLE study_availability (
    availability_id  SERIAL PRIMARY KEY,
    user_id          INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    available_date   DATE NOT NULL,
    available_hours  DECIMAL(4,2) NOT NULL,
    CONSTRAINT valid_available_hours CHECK (available_hours >= 0 AND available_hours <= 24),
    CONSTRAINT uq_user_day UNIQUE (user_id, available_date)
);

-- ---------------------------------------------------------------------
-- TASK_DEPENDENCIES  (unary M:N on TASKS: task_id requires prerequisite_task_id)
-- ---------------------------------------------------------------------
CREATE TABLE task_dependencies (
    dependency_id         SERIAL PRIMARY KEY,
    task_id               INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    prerequisite_task_id  INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    CONSTRAINT no_self_dependency CHECK (task_id <> prerequisite_task_id),
    CONSTRAINT uq_dependency UNIQUE (task_id, prerequisite_task_id)
);

-- ---------------------------------------------------------------------

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

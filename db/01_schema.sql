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

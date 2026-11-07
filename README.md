# Deadline Collision Detector

An academic workload and deadline risk analysis system. It stores courses, enrollments, tasks with deadlines and estimated hours, task dependencies and each student's daily study availability, then analyses temporal overlaps and workload concentration to find deadline collisions, high-risk periods and overloaded weeks.

**Stack:** PostgreSQL 15+ (all analytics live in the database as SQL/PLpgSQL) and Next.js 16 (App Router, server components, server actions, raw SQL through `pg`, no ORM). Every panel in the UI has a **Show SQL** toggle with the exact statement it ran.

**Repository:** [github.com/ishanshaurya/deadline-collision-detector](https://github.com/ishanshaurya/deadline-collision-detector)  
**Project work window:** November 2–7, 2026

## Individual contribution

| Member | Contribution |
|---|---|
| **Shivansh Sharma (PES2UG24CS474)** | Relational schema and constraints, analytics SQL, procedures/triggers, database integration and report preparation. |
| **Shaurya Ishan (PES2UG24CS464)** | Next.js screens and interaction flow, authentication UI/session handling, testing/demo preparation and documentation review. |

Both members contributed to requirements analysis, debugging, integration, viva preparation and final validation. The project’s originality is the combination of deadline-collision detection, prerequisite feasibility and study-capacity analysis in database-resident SQL rather than only in application code.

```
deadline-collision-detector/
├── db/
│   ├── 01_schema.sql              enum types, tables, constraints, keys, indexes, FTS column
│   ├── 02_views.sql               4 views
│   ├── 03_functions_triggers.sql  building blocks, graph traversal, 3 triggers, 6 analytics
│   ├── 04_procedures.sql          4 stored procedures
│   ├── 05_seed.sql                demo data (dates relative to CURRENT_DATE)
│   └── demo/
│       ├── analytics_queries.sql  viva demo queries, tagged by syllabus topic
│       └── transactions.sql       two-session locking / isolation scenarios
├── web/                           Next.js app
└── DECISIONS.md                   refactor decision log
```

---

## 1. Setup

Prerequisites: PostgreSQL 15 or newer, Node.js 22.9 or newer.

```bash
# 1. create the database (psql, pgAdmin, or:)
createdb -U postgres deadline_detector

# 2. configure the app
cd web
cp .env.example .env          # set your postgres password in DATABASE_URL

# 3. install, load schema + demo data, run
npm install
npm run db:setup
npm run dev                   # http://localhost:3000
```

Demo logins (password `password123`):

| User | Scenario |
|---|---|
| `aarav@dcd.edu` | Main demo: collision clusters, an overloaded week, dependency chains, one dependency inversion, one overdue task |
| `diya@dcd.edu`  | Control case (semester 4 courses): light, well-spread load |
| `kabir@dcd.edu` | Chronically overloaded: low availability, five deadlines in 48 hours |

Courses are the real semester 4 and 5 PES course list (CC = core, EC = elective). **Credits, staff names, cabins, office hours, phone numbers and teammates in `05_seed.sql` are placeholders**: replace them with real details before showing the app to anyone.

What the app does:

- **Dashboard:** every number (pending, overdue, due this week, pile-ups, overloaded weeks, won't fit) opens the list of tasks behind it.
- **Tasks:** filter by status, subject, type, team or solo, and focus (the dashboard's categories); sort by deadline, priority, hours, subject or title; switch between a list and a by-subject view; full-text search. New tasks are individual or belong to one of your teams for that subject.
- **Courses:** grouped by semester, each with its core/elective tag, share of your workload, and the professor and TA to contact (cabin, office hours, email, phone). There is no unenroll.
- **Subject page:** contacts, every assignment for that subject, and its teams with a members table (name, role, SRN, email, phone). Teammates can be added and removed, and new teams created.
- **Collisions, availability, login:** pile-up clusters and pairs at 24/48/72h, the daily study-hours editor, accounts.

`npm run db:setup` runs every `db/*.sql` file in name order. The first file drops and recreates the whole `public` schema of `deadline_detector`, so rerun it any time to reset the demo, and don't point `DATABASE_URL` at a database you use for anything else. The files can also be run with `psql -f` in the same order; the `demo/` scripts are for psql only.

---

## 2. Changes from the submitted ER diagram and DDL

| # | Change | Reason |
|---|---|---|
| 1 | `HAS_AVAILABILITY` now connects **USERS** (1) to STUDY_AVAILABILITY (N), not COURSES | The table carries `user_id`; availability is a property of the student, not the course |
| 2 | `HAS_DEPENDENCY` drawn as a **unary M:N relationship on TASKS** (two lines from TASKS, roles *task* and *prerequisite*) | In the diagram it was connected to USERS and COURSES lines; a dependency relates two tasks |
| 3 | Removed the line from ENROLLMENTS to TASKS; added a composite FK `tasks(user_id, course_id) → enrollments(user_id, course_id)` | Enforces "a student can only have tasks for courses they are enrolled in" declaratively. Unenrolling cascades to that course's tasks |
| 4 | Added `courses.description TEXT` | Attribute was in the ER diagram but missing from the DDL |
| 5 | Fixed `CHECK (estimated hours > 0),` | Missing underscore and a trailing comma before `)` |
| 6 | `task_type` and `status` are enum types (`task_kind`: ASSIGNMENT, EXAM, QUIZ, PROJECT, LAB, READING; `task_status`: PENDING, IN_PROGRESS, COMPLETED). `email` is `CITEXT` (case-insensitive, so sign-up and login agree on `Foo@x.edu` vs `foo@x.edu`). Added `CHECK`s: `priority` 1..5, `available_hours` 0..24, non-blank name, basic email format | Domains declared once; the app reads the task types from the enum instead of keeping its own list |
| 7 | Added `UNIQUE(user_id, available_date)` on study_availability | One availability value per student per day; also the target for `ON CONFLICT` upserts |
| 8 | Added `UNIQUE(task_id, prerequisite_task_id)` and `CHECK(task_id <> prerequisite_task_id)` on task_dependencies | No duplicate edges, no self-loops. Longer cycles are blocked by a trigger |
| 9 | Added generated column `tasks.search_vector` + GIN index | Full-text search |
| 10 | Added indexes on `tasks(user_id, deadline)`, a partial index on pending tasks, `tasks(course_id)`, `task_dependencies(prerequisite_task_id)`, `enrollments(course_id)` | Every analytics query filters by user and orders by deadline; FK columns used in joins |

### Corrected ER summary (for redrawing the diagram)

- USERS **ENROLLS_IN** COURSES: M:N, associative entity ENROLLMENTS (`enrollment_id`, `enrolled_at`)
- USERS **ASSIGNS** TASKS: 1:N
- COURSES **HAS_TASKS** TASKS: 1:N
- USERS **HAS_AVAILABILITY** STUDY_AVAILABILITY: 1:N
- TASKS **HAS_DEPENDENCY** TASKS: unary M:N, resolved by TASK_DEPENDENCIES (`dependency_id`, `task_id`, `prerequisite_task_id`)

Added for contacts and team work (new entities, not in the original ER diagram):

- COURSES **TAUGHT_BY** STAFF: M:N with attribute `role` (PROFESSOR or TA), resolved by COURSE_STAFF
- STAFF **HOLDS** OFFICE_HOURS: 1:N (weekday, start and end time)
- USERS **FORMS** TEAMS for a COURSE: each team belongs to one enrollment (composite FK to ENROLLMENTS)
- TEAMS **HAS** TEAM_MEMBERS: 1:N (name, SRN, email, phone, role)
- TEAMS **WORKS_ON** TASKS: 1:N, optional; a task with no team is individual work. Composite FK `tasks(team_id, user_id, course_id) → teams(team_id, user_id, course_id)` guarantees the team belongs to the same student and subject

---

## 3. Relational schema

PK = primary key, FK = foreign key, UQ = unique.

```
USERS              (user_id PK, name, email UQ, password_hash, role, created_at)
COURSES            (course_id PK, course_code UQ, course_name, course_type, semester, credits, description)
STAFF              (staff_id PK, name, email UQ, phone, cabin)
COURSE_STAFF       (course_id PK FK→COURSES, staff_id PK FK→STAFF, role)
OFFICE_HOURS       (office_hour_id PK, staff_id FK→STAFF, weekday, starts_at, ends_at)
ENROLLMENTS        (enrollment_id PK, user_id FK→USERS, course_id FK→COURSES, enrolled_at)
                    UQ(user_id, course_id)
TASKS              (task_id PK, user_id FK→USERS, course_id FK→COURSES, title, description,
                    task_type, deadline, estimated_hours, priority, status, team_id,
                    created_at, updated_at, search_vector)
                    FK(user_id, course_id)→ENROLLMENTS(user_id, course_id)
                    FK(team_id, user_id, course_id)→TEAMS(team_id, user_id, course_id)
TEAMS              (team_id PK, user_id, course_id, name)
                    UQ(team_id, user_id, course_id), FK(user_id, course_id)→ENROLLMENTS
TEAM_MEMBERS       (member_id PK, team_id FK→TEAMS, name, srn, email, phone, role)
                    UQ(team_id, srn)
STUDY_AVAILABILITY (availability_id PK, user_id FK→USERS, available_date, available_hours)
                    UQ(user_id, available_date)
TASK_DEPENDENCIES  (dependency_id PK, task_id FK→TASKS, prerequisite_task_id FK→TASKS)
                    UQ(task_id, prerequisite_task_id)
```

---

## 4. Normalization (Unit 3)

Functional dependencies (non-trivial):

| Relation | FDs | Candidate keys |
|---|---|---|
| USERS | user_id → all; email → all | {user_id}, {email} |
| COURSES | course_id → all; course_code → all | {course_id}, {course_code} |
| ENROLLMENTS | enrollment_id → all; user_id, course_id → all | {enrollment_id}, {user_id, course_id} |
| TASKS | task_id → all | {task_id} |
| STUDY_AVAILABILITY | availability_id → all; user_id, available_date → all | {availability_id}, {user_id, available_date} |
| TASK_DEPENDENCIES | dependency_id → all; task_id, prerequisite_task_id → all | {dependency_id}, {task_id, prerequisite_task_id} |
| STAFF | staff_id → all; email → all | {staff_id}, {email} |
| COURSE_STAFF | course_id, staff_id → role | {course_id, staff_id} |
| OFFICE_HOURS | office_hour_id → all | {office_hour_id} |
| TEAMS | team_id → all | {team_id} |
| TEAM_MEMBERS | member_id → all; team_id, srn → all | {member_id}, {team_id, srn} |

Work mode (team or individual) is not stored: it is derived from whether `team_id` is NULL (in `v_task_details`), so it can never disagree with the team assignment. Office hours are rows, not a text column, so each slot is atomic (1NF) and can be queried by day.

- **1NF:** all attributes are atomic; no repeating groups (dependencies are rows, not a list column).
- **2NF / 3NF / BCNF:** in every relation the determinant of each FD is a candidate key, so all six relations are in BCNF.
- **One honest exception:** `tasks.search_vector` is derived from `title` and `description` (task_id → title, description → search_vector), which is a transitive dependency. It is a `GENERATED ALWAYS ... STORED` column, so the DBMS recomputes it on every write and it cannot become inconsistent. It is a deliberate denormalization for indexing, not an update anomaly.
- **Decisions that avoid anomalies:** course_code is not copied into tasks; weekly totals, risk levels and collisions are never stored but computed by functions and views, so they cannot go stale.

---

## 5. How the analysis works

Every analytic takes `p_now`, so it can be evaluated at any instant (the app passes `LOCALTIMESTAMP`). They share three building blocks: `fn_upcoming_tasks` (the only definition of work still to do), `fn_daily_ledger` (hours due and hours available per day) and `fn_load_level` (one severity scale, the ordered enum `load_level`: demand > capacity is CRITICAL, ≥ 80% HIGH, ≥ 60% MEDIUM, otherwise LOW; NONE when nothing is due). The analysis settings (windows, horizons) live in one place, `ANALYSIS` in `web/lib/queries.ts`.

| Output | Object | Method |
|---|---|---|
| **Deadline collisions (pairs)** | `fn_collision_pairs(user, window_hours, now)` | Self-join on upcoming tasks: two tasks due within the window of each other |
| **Collision clusters** | `fn_collision_clusters(user, window_hours, lead_days, now)` | Gaps-and-islands: `LAG(deadline)` marks a new cluster when the gap exceeds the window, a running `SUM` numbers clusters, `HAVING COUNT(*) >= 2`. Level compares cluster hours with study hours in the `lead_days` up to the last deadline |
| **Deadline feasibility** | `fn_task_risk(user, now)` | Earliest-deadline-first test. For a single worker, EDF is optimal, so the task set is feasible iff for every deadline *d*: hours due by *d* ≤ study hours available by *d*. Running `SUM` over deadlines vs running `SUM` over availability gives slack; negative slack = **CRITICAL** (missed under any ordering). Also flags a late prerequisite: unfinished and due after the task that needs it (`fn_is_late_prerequisite`, used by `v_dependency_edges` and `fn_prerequisites`) |
| **Overloaded weeks** | `fn_weekly_load(user, weeks, now)` | The daily ledger grouped by ISO week, with cumulative totals. A CRITICAL week is overloaded |
| **High-risk periods** | `fn_daily_pressure(user, days, window, now)` | For each day of the ledger, a forward sliding frame (`ROWS BETWEEN CURRENT ROW AND window - 1 FOLLOWING`) sums hours due and hours available. CRITICAL days are high risk; consecutive ones are merged into numbered periods |
| **Dependency chains** | `fn_prerequisites(task)`, `fn_dependents(task)` | Recursive CTEs with a visited-path array, each task once at its shallowest depth. The cycle trigger, the reschedule cascade and the task page all use them |

Assumptions to state in the viva: estimated hours are taken as given (no partial progress for IN_PROGRESS), study hours on the deadline day count fully, and overdue tasks are excluded from forward-looking risk (they show separately as OVERDUE).

---

## 6. Syllabus coverage

| Unit | Topic | Where |
|---|---|---|
| 1 | ER model, reduction to relational schema | Sections 2 and 3 |
| 1 | Constraints and keys (PK, FK, composite FK, UNIQUE, CHECK, NOT NULL, DEFAULT) | `01_schema.sql` |
| 1 | Aggregate functions, grouping, HAVING | `demo/analytics_queries.sql`, `v_course_workload`, `fn_weekly_load` |
| 2 | Set operations (UNION ALL, INTERSECT, EXCEPT) | `demo/analytics_queries.sql` |
| 2 | Null values (COALESCE, NULLIF, IS DISTINCT FROM, outer joins) | `fn_daily_ledger`, `fn_load_ratio`, `fn_daily_pressure`, demo queries |
| 2 | Nested and correlated subqueries, EXISTS / NOT EXISTS | `fn_task_risk` (inversion flag), `v_task_details`, demo queries |
| 2 | Join expressions (inner, left outer, self, LATERAL) | `fn_collision_pairs` (self), `fn_daily_ledger` (outer), `fn_collision_clusters` (LATERAL) |
| 2 | Views | `02_views.sql` (4) |
| 2 | Triggers | `updated_at`; dependency validation (AFTER trigger: same user, cycle check via `fn_prerequisites`, advisory lock); completion guard |
| 2 | Functions | 6 analytics + 6 building-block SQL functions |
| 2 | Procedures | `sp_add_task`, `sp_reschedule_task`, `sp_complete_task`, `sp_set_availability` |
| 2 | CTEs, recursive CTEs | `fn_prerequisites`, `fn_dependents` (used by cycle detection and cascade reschedule) |
| 2 | Window functions | SUM OVER (running and sliding frames), LAG, LEAD, RANK, DENSE_RANK, PARTITION BY |
| 2 | Full-text search | generated `tsvector`, GIN index, `websearch_to_tsquery`, `ts_rank`, `ts_headline` |
| 3 | FDs, normal forms, BCNF | Section 4 |
| 3 | Query processing and optimization | `EXPLAIN ANALYZE` in `demo/analytics_queries.sql`: composite B-tree index scan, GIN bitmap scan |
| 4 | Transactions, atomicity, savepoints | procedures, multi-day availability save as one statement, `demo/transactions.sql` scenarios 1 and 5 |
| 4 | Concurrency control and locking | `SELECT ... FOR UPDATE` in fixed order (no deadlock), `pg_advisory_xact_lock` against concurrent cycles, isolation levels (`demo/transactions.sql` scenarios 2 to 4) |
| 4 | Web application with Next.js and SQL | `web/` |

Not used, on purpose: NoSQL, Neo4j and vector databases. The dependency graph is small and per-student, so a recursive CTE handles it inside the relational model.

---

## 7. Suggested viva walkthrough (about 10 minutes)

1. Log in as Aarav. Dashboard: overloaded week, collision clusters, red high-risk days on the pressure strip. (Seed dates are relative to today, so exact numbers shift slightly with the weekday.)
2. Feasibility table: point at a CRITICAL row (negative slack) and explain the EDF argument.
3. Collisions page: switch 24h / 48h / 72h windows; open Show SQL on the clusters panel.
4. Click the **won't fit** card: the task list opens filtered to the CRITICAL tasks. Try the filters (team only, sort by hours, by subject).
5. Open **courses → Database Management System**: professor and TA contacts with office hours (`v_course_staff`, `string_agg`), the subject's assignments, and the Query Crew team table. Try adding a team task under the wrong subject: the composite FK rejects it.
6. Open "DBMS mini project submission", click **mark done**: the trigger rejects it because "Relational schema and DDL" is unfinished.
7. Open "Dataset cleaning for ML project", reschedule it 3 days later with cascade on: both dependents move together in one transaction ("3 tasks moved").
8. Search `spark OR kafka` on the Tasks page (full-text search with highlighted snippet).
9. Availability: drop a weekend to 0 hours, save, return to the dashboard and show the risk change.
10. In psql, run `demo/transactions.sql` scenario 3 in two terminals to show the concurrent-cycle protection.

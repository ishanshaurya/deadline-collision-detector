# Refactor decision log

Refactor of the whole codebase against one question: should these pieces change together? Each fix is listed above the problems it solves. Line numbers refer to the pre-refactor commit.

## 1. One severity scale, computed in one place

Add `fn_load_level(demand, capacity)` returning `NONE | LOW | MEDIUM | HIGH | CRITICAL` (ratio > 1 critical, ≥ 0.8 high, ≥ 0.6 medium). Every analytic calls it; the UI badge map knows only these five plus task states.

- `02_functions_triggers.sql:196` (task risk) grades slack with thresholds 0 / 0.2 / 0.5 of demand.
- `02_functions_triggers.sql:279` (clusters) grades with `> cap` / `> 0.75 cap` and names levels CRITICAL / HIGH / MODERATE.
- `02_functions_triggers.sql:345` (weekly) grades with `> cap` / `> 0.8 cap` and names levels FREE / MANAGEABLE / HEAVY / OVERLOADED.
- `02_functions_triggers.sql:405` (daily) uses a fourth rule, `demand > capacity`.
- Ratio `ROUND(x / NULLIF(y, 0), 2)` is written three times (`:277`, `:341`, `:405`).
- Special case `cap.hours = 0 OR` at `:279` and `COALESCE(c.hours, 0) = 0 OR` at `:346` patch division by zero separately.
- `components/ui.tsx:23` maps 13 level names (CRITICAL, OVERLOADED, HIGH, HEAVY, MEDIUM, MODERATE, LOW, MANAGEABLE, FREE, ...) to 5 tones.
- `app/(app)/page.tsx:57` and `components/charts.tsx:42` test for the string `"OVERLOADED"`; `page.tsx:58` tests `"CRITICAL"`.

## 2. One per-day ledger of demand and capacity

Add `fn_upcoming_tasks(user, now)` (the only definition of "work still to do": not completed, deadline not passed) and `fn_daily_ledger(user, from, to, now)` (one row per day: hours due, hours available). Task risk, weekly load, daily pressure and cluster capacity are all aggregates over the ledger.

- `status <> 'COMPLETED' AND deadline >= p_now` is repeated in four functions (`:175`, `:249`, `:325`, `:388`) and three views (`03_views.sql:39-42`, `:74-75`).
- Study hours in a date range are summed four different ways (`:186`, `:286`, `:331`, the `LEFT JOIN` in `fn_daily_pressure`), plus `03_views.sql:77`.
- `fn_daily_pressure` computes each day's due hours with a correlated subquery per day (`:390`).
- `v_user_summary.hours_due_7d / hours_available_7d` (`03_views.sql:73-81`) recompute what day 0 of the daily pressure window already holds, with a different boundary (168 hours vs 7 calendar days).

## 3. Graph traversal as two functions

Add `fn_prerequisites(task)` and `fn_dependents(task)` (recursive CTEs, both return task details and depth). The cycle trigger, the reschedule procedure, the task page and the demo queries use them.

- The dependents recursive CTE is written three times: `04_procedures.sql:79`, `:109`, `lib/queries.ts:40`.
- The cycle check (`02_functions_triggers.sql:47`) is a third traversal, with a special case `dependency_id IS DISTINCT FROM NEW.dependency_id` (`:51`, `:56`) so an UPDATE does not see its own old row. Moving the check to an AFTER trigger ("is the task now reachable from itself?") handles INSERT and UPDATE the same way, so the special case goes.
- "Prerequisite due after its dependent" is computed three times: `02:201` (correlated subquery), `04_procedures.sql:124` (only to RAISE NOTICE), `app/(app)/tasks/[id]/page.tsx:103` (in TSX).
- The NOTICE in `sp_reschedule_task:131` is never seen: the app discards notices and the dashboard already shows inversions. Removed.
- `sp_reschedule_task` returns `p_shifted`, but the app ignores it (`lib/queries.ts:56` passes `0`). The app now reports it.

## 4. Pairwise collisions take the same window as clusters

Replace the fixed-48h view `v_deadline_collisions` with `fn_collision_pairs(user, window_hours, now)` built on `fn_upcoming_tasks`.

- `03_views.sql:36` hard-codes 48 hours, so at the 72h window `collisions/page.tsx:35` silently shows only pairs within 48h (the page footnote at `:75` admits "48h max"). Bug.
- `03_views.sql:41` uses `LOCALTIMESTAMP` while every function takes `p_now`.
- `v_user_summary.collision_pairs` (`03_views.sql:82`) depends on the 48h view; the dashboard prints "(48h)" separately (`page.tsx:71`).

## 5. Domains declared once, in the database

Make `task_type` and `status` PostgreSQL enum types. The app reads the allowed task types from `enum_range`. `v_task_details.state` is the single definition of "overdue".

- `tasks/page.tsx:17` copies the six task types from the CHECK at `01_schema.sql:74`.
- Overdue is defined in `03_views.sql:15` and again in `:72`.
- `tasks/page.tsx:83` and `tasks/[id]/page.tsx:52` each pick `"OVERDUE"` vs `status` in TSX.

## 6. Analysis parameters owned by the app, defaults removed from SQL

`lib/queries.ts` holds the analysis settings (collision windows 24/48/72, default 48, lead days 7, pressure window 7, horizon 28 days, 8 weeks). The SQL functions have no defaults for these, so there is no second copy.

- 48 appears in `02:228` (default), `03_views.sql:36`, `page.tsx:51`, `:71`, `:83`, `:97`, `collisions/page.tsx:26`, `:31`, `:75`.
- 7 lead days: `02:229`, `queries.ts:22`, `collisions/page.tsx:62`.
- 28 / 7 for pressure: `02:364-365`, `queries.ts:18`, `page.tsx:101`, `charts.tsx:92`, `:102`, `:113`.
- 8 weeks: `02:300`, `queries.ts:16`, `page.tsx:72` ("of the next 8").

## 7. Each query carries its row type and reports what it ran

`lib/queries.ts` defines each query with `sql<Row>(text)`; `.run(...params)` returns `{ rows, sql, params }`, and `SqlPeek` renders that result. Chart components import row types from the same module.

- Row types are redeclared away from their SQL: `Cluster` twice (`page.tsx:31`, `collisions/page.tsx:8`), `Task` twice, `Week` and `Day` in `charts.tsx`, plus the workaround `Parameters<typeof WeeklyLoadChart>[0]["weeks"][number]` (`page.tsx:48`).
- Every `SqlPeek` has a hand-written `params` string (`page.tsx:79`, `:97`, `:103`, `:140`, `collisions/page.tsx:71`, `:94`, ...) that must match the real call; `collisions/page.tsx:94` labels `$2` as `max_gap`.

## 8. Flash messages: one module, rendered once

`lib/flash.ts` owns the query keys and builds redirect URLs; a single client `<Flash />` in the app layout (and on the login page) reads them. Actions return to the page that posted the form (Referer), so no caller-specific return paths.

- The `msg` / `error` keys are a convention between `actions.ts:15` and five pages that each read `searchParams` and render `<Flash>`.
- `completeTask` takes a hidden `return_to` field only the task page sends (`tasks/[id]/page.tsx:63`, `actions.ts:86`).
- `rescheduleTask` hard-codes its return path (`actions.ts:95`).

## 9. Let constraints speak; remove code that repeats them

- `sp_add_task:34-40` checks that prerequisites exist, which the FK on `task_dependencies` already enforces.
- `register` (`actions.ts:44`) re-validates name and email in TS; the name rule moves to a CHECK, email is already checked.
- `dbErrorMessage` (`lib/db.ts:33-35`) has one branch per error code and one per constraint name. Replaced by the server's own message plus its detail.

## 10. Remove surplus and one-off special cases

- `saveDays` (`actions.ts:136-155`) dynamically imports the pool it could import statically and runs a manual BEGIN/COMMIT loop; one `INSERT ... SELECT FROM unnest(...) ON CONFLICT` is atomic on its own.
- `export const dynamic = "force-dynamic"` (`(app)/layout.tsx:5`, `login/page.tsx:7`) repeats what reading cookies already implies.
- `v_user_summary` filters `role = 'STUDENT'` (`03_views.sql:85`), so the dashboard needs a fallback object for admins (`page.tsx:54`). The filter goes, so does the fallback.
- `availability/page.tsx:20` guards `days.length` though the query always returns 28 rows; `addDays` lives in the page instead of `lib/format.ts`; the default pattern end is `+55` days labelled `plus8w`.
- `hours()` (`lib/format.ts:33`) handles `null`/`undefined` that no caller passes.
- `v_course_workload` (`03_views.sql:52-59`) repeats the same `COALESCE(SUM ... FILTER ...)` expression five times; computed once in a CTE.

## 11. Configuration has one source

- The default connection string is copied in `lib/db.ts:16`, `scripts/setup-db.mjs:17` and `.env.example`; `SESSION_SECRET` falls back to a hard-coded secret (`session.ts:7`). Both now come only from `.env`, and a missing value fails with a clear message.
- `setup-db.mjs` parses `.env` by hand (`:8-14`); Node's `--env-file-if-exists` does it.
- `setup-db.mjs:18` lists the five setup files by name; demo scripts move to `db/demo/` and setup runs every `db/*.sql` in order.

## 12. Seed and demo scripts don't assume insertion order

- `05_seed.sql:136-142` and both demo scripts use literal ids (`2`, `9`, ...) that only hold if rows are inserted in a fixed order. Seed looks users up by email; demo scripts bind ids by email/title with `\gset`.

## 13. Comments (add-on)

Removed comments that restate code (e.g. `-- each unordered pair once`, the `settle`/`dbErrorMessage`/`SqlPeek`/chart docblocks, `// rounded data end, square at the baseline`, `-- helper used only while seeding`, the run-order header, the `RANGE frame` note now made explicit in the frame clause, type-OID labels replaced by named constants). Kept comments about things outside the code: the EDF feasibility argument, why the advisory lock exists, why timestamps are parsed as strings, priority 1 = highest, accessibility rule for badges.

## 14. Second pass (independent audit)

A subagent re-audited the refactored code. Fixed:

- Make `users.email` `CITEXT`, so sign-up and login can't disagree on letter case.
  - `register` lowercased the email but `login` didn't; `Foo@x.edu` could never log in.
- Make severity the ordered enum `load_level`, and give the app one `ratio()` formatter. `fn_load_ratio` returns 0 when nothing is due, so NULL now only means "work due, no hours to do it".
  - A CRITICAL week with zero capacity rendered `■ x`; NULL ratios showed as `∞`, `-` or blank depending on the component.
- Graph functions and search return `state` from `v_task_details`, and one predicate `fn_is_late_prerequisite` serves both `v_dependency_edges` (direct edges) and `fn_prerequisites` (relative to the root task).
  - The prerequisite chain showed overdue tasks as PENDING.
  - The late-prerequisite test was written twice.
- `taskById` counts only unfinished work, the task's own hours included; a completed task showed "Xh still to do".
- The reschedule checkbox no longer quotes a count, because the procedure only moves unfinished dependents and only when the deadline moves later.
- `fn_is_weekend` serves both `sp_set_availability` and the availability page.
- `MIN_PASSWORD_LENGTH` is defined once in `lib/session.ts` and shared by the form and the action.
- `<Flash />` contains its own `<Suspense>` boundary, instead of every caller adding one.
- The CSS colour triplets shared by badges and flashes are now variables, and the selectors are shared.
- `run()` returns `rowCount`, so delete and unenroll report "not found" instead of a false success.
- The empty-description → NULL conversion moved from `sp_add_task` to the form action.
- Seed helpers raise on a misspelled name instead of silently inserting nothing; the unused `RETURNING` and duplicated status default are gone.
- Removed: a no-op notice handler in the setup script, `max: 10` (pg's default), `student_name` and the `users` join in `v_task_details`, `role` in `userById`, an unused `code {}` rule, a fixed 5-column stat grid, and an unexplained float epsilon in the colour scale.

Kept, with reasons:

- The priority domain 1..5 appears in both the CHECK constraint and the form. Reading the bounds back from the catalog would be more fragile than this one numeric copy.
- The availability page reads `study_availability` rows directly rather than through `fn_daily_ledger`, because it edits stored rows, including whether a day is set at all. It does not compute capacity.
- `v_task_details.state` (OVERDUE) and `fn_upcoming_tasks` are complementary definitions. The view uses the real clock for display; the function takes `p_now` for analysis. A comment in each points to the other.
- The demo scripts repeat literal arguments and predicates on purpose, to illustrate syllabus constructs; a missing row fails loudly.
- Row types are hand-written next to each query. Every column was checked and nothing drifts today.

## Special cases that remain (the system needs them)

- `sp_reschedule_task` cascades only when the deadline moves later; moving earlier never invalidates dependents.
- Completion guard trigger: a task can't be completed before its prerequisites.
- A task can't be rescheduled to a past deadline (adding a task with a past deadline is allowed, e.g. to log something already overdue).
- `fn_daily_ledger` is computed `window - 1` days past the horizon so the last day's forward window is complete.
- Delete redirects to `/tasks` instead of back, because the page it was posted from no longer exists.

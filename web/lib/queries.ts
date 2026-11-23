// Every SQL statement the app runs lives here, next to the row type it returns.
import { getPool } from "./db";

export type Ran<Row> = { rows: Row[]; rowCount: number; sql: string; params: unknown[] };

function sql<Row = Record<string, never>>(text: string) {
  return {
    sql: text,
    async run(...params: unknown[]): Promise<Ran<Row>> {
      const res = await getPool().query(text, params);
      return { rows: res.rows as Row[], rowCount: res.rowCount ?? 0, sql: text, params };
    },
  };
}

/** Tuning for the analytics. */
export const ANALYSIS = {
  collisionWindows: [24, 48, 72],
  defaultWindow: 48,
  leadDays: 7,
  pressureWindow: 7,
  horizonDays: 28,
  weeks: 8,
} as const;

// Mirrors of database vocabularies: Level is the load_level enum (01_schema.sql);
// TaskState is the task_status enum plus OVERDUE from v_task_details.state.
export type Level = "NONE" | "LOW" | "MEDIUM" | "HIGH" | "CRITICAL";
export type TaskState = "PENDING" | "IN_PROGRESS" | "COMPLETED" | "OVERDUE";

// ------------------------------------------------------------------ auth

export const login = sql<{ user_id: number }>(`SELECT user_id
FROM users
WHERE email = $1
  AND password_hash = crypt($2, password_hash)`);

export const register = sql<{ user_id: number }>(`INSERT INTO users (name, email, password_hash)
VALUES ($1, $2, crypt($3, gen_salt('bf')))
RETURNING user_id`);

export type Role = "STUDENT" | "ADMIN";
export const userById = sql<{ user_id: number; name: string; email: string; role: Role }>(
  `SELECT user_id, name, email, role FROM users WHERE user_id = $1`,
);

// ------------------------------------------------------------------ analytics

export type Summary = { user_id: number; name: string; pending_tasks: number; overdue_tasks: number };
export const summary = sql<Summary>(`SELECT * FROM v_user_summary WHERE user_id = $1`);

export type WeekRow = {
  week_start: string;
  tasks_due: number;
  demand_hours: number;
  capacity_hours: number;
  load_ratio: number | null;
  cumulative_demand: number;
  cumulative_capacity: number;
  level: Level;
};
export const weeklyLoad = sql<WeekRow>(`SELECT * FROM fn_weekly_load($1, $2, LOCALTIMESTAMP)`);

export type DayRow = {
  day: string;
  due_hours: number;
  available_hours: number;
  window_demand: number;
  window_capacity: number;
  pressure: number | null;
  level: Level;
  risk_period: number | null;
};
export const dailyPressure = sql<DayRow>(`SELECT * FROM fn_daily_pressure($1, $2, $3, LOCALTIMESTAMP)`);

export type RiskRow = {
  task_id: number;
  title: string;
  course_code: string;
  task_type: string;
  deadline: string;
  estimated_hours: number;
  priority: number;
  cumulative_demand: number;
  capacity_by_deadline: number;
  slack_hours: number;
  level: Level;
  dependency_inversion: boolean;
};
export const taskRisk = sql<RiskRow>(`SELECT * FROM fn_task_risk($1, LOCALTIMESTAMP)`);

export type ClusterRow = {
  cluster_id: number;
  starts_at: string;
  ends_at: string;
  task_count: number;
  total_hours: number;
  available_hours: number;
  pressure: number | null;
  level: Level;
  tasks: string[];
};
export const clusters = sql<ClusterRow>(`SELECT * FROM fn_collision_clusters($1, $2, $3, LOCALTIMESTAMP)`);

export type PairRow = {
  task_a_id: number; task_a: string; course_a: string; deadline_a: string;
  task_b_id: number; task_b: string; course_b: string; deadline_b: string;
  gap_hours: number; combined_hours: number; cross_course: boolean;
};
export const collisionPairs = sql<PairRow>(`SELECT * FROM fn_collision_pairs($1, $2, LOCALTIMESTAMP)`);

export type CourseLoad = {
  course_id: number; course_code: string; course_name: string; course_type: CourseType; semester: number; credits: number;
  pending_tasks: number; completed_tasks: number; pending_hours: number;
  share_pct: number | null; hours_per_credit: number; load_rank: number;
};
export const courseWorkload = sql<CourseLoad>(
  `SELECT * FROM v_course_workload WHERE user_id = $1 ORDER BY semester DESC, course_type, course_code`,
);

export const courseForUser = sql<CourseLoad & { description: string | null }>(`SELECT w.*, c.description
FROM v_course_workload w
JOIN courses c USING (course_id)
WHERE w.user_id = $1 AND w.course_id = $2`);

export type StaffRow = {
  course_id: number; role: "PROFESSOR" | "TA"; staff_id: number; name: string;
  email: string; phone: string | null; cabin: string | null; office_hours: string | null;
};
export const staffForUser = sql<StaffRow>(`SELECT s.*
FROM v_course_staff s
JOIN enrollments e ON e.course_id = s.course_id
WHERE e.user_id = $1
ORDER BY s.course_id, s.role, s.name`);

export const staffForCourse = sql<StaffRow>(`SELECT * FROM v_course_staff WHERE course_id = $1 ORDER BY role, name`);

// ------------------------------------------------------------------ teams

export type TeamMember = { member_id: number; name: string; srn: string | null; email: string | null; phone: string | null; role: string };
export type TeamRow = { team_id: number; name: string; course_id: number; course_code: string; members: TeamMember[] };

export const teamsForUser = sql<TeamRow>(`SELECT tm.team_id, tm.name, tm.course_id, c.course_code,
       COALESCE((SELECT json_agg(m ORDER BY m.member_id) FROM team_members m WHERE m.team_id = tm.team_id), '[]') AS members
FROM teams tm
JOIN courses c USING (course_id)
WHERE tm.user_id = $1
ORDER BY c.course_code, tm.name`);

export const createTeam = sql(`INSERT INTO teams (user_id, course_id, name) VALUES ($1, $2, $3)`);
export const addTeamMember = sql(`INSERT INTO team_members (team_id, name, srn, email, phone, role)
SELECT team_id, $3, $4, $5, $6, $7 FROM teams WHERE team_id = $2 AND user_id = $1`);
export const removeTeamMember = sql(`DELETE FROM team_members m
USING teams t
WHERE m.member_id = $2 AND m.team_id = t.team_id AND t.user_id = $1`);

// ------------------------------------------------------------------ tasks

export type CourseType = "CC" | "EC";

export type TaskRow = {
  task_id: number; title: string; description: string | null;
  course_id: number; course_code: string; course_name: string; course_type: CourseType; task_type: string;
  deadline: string; estimated_hours: number; priority: number;
  state: TaskState; prerequisite_count: number; dependent_count: number; updated_at: string;
  team_id: number | null; team_name: string | null; work_mode: "INDIVIDUAL" | "TEAM";
};

/** Filter and sort vocabularies for the task list; values are passed to SQL as parameters. */
export const TASK_FILTERS = {
  status: { OPEN: "not done", PENDING: "pending", IN_PROGRESS: "in progress", OVERDUE: "overdue", COMPLETED: "done", ALL: "everything" },
  mode: { INDIVIDUAL: "individual", TEAM: "team" },
  focus: {
    due_soon: `due in the next ${ANALYSIS.pressureWindow} days`,
    colliding: `within ${ANALYSIS.defaultWindow}h of another deadline`,
    overloaded: "due in an overloaded week",
    infeasible: "can't be finished in time",
  },
  sort: { deadline: "deadline", priority: "priority", hours: "most hours", course: "subject", title: "title" },
} as const;
export type TaskSort = keyof typeof TASK_FILTERS.sort;

const TASK_ORDER: Record<TaskSort, string> = {
  deadline: "deadline",
  priority: "priority, deadline",
  hours: "estimated_hours DESC, deadline",
  course: "course_code, deadline",
  title: "title",
};

const taskListQueries = Object.fromEntries(
  (Object.keys(TASK_ORDER) as TaskSort[]).map((key) => [
    key,
    sql<TaskRow>(`SELECT *
FROM v_task_details t
WHERE t.user_id = $1
  AND ($2::int  IS NULL OR t.course_id = $2)
  AND ($3::text IS NULL OR t.task_type::text = $3)
  AND ($4::text = 'ALL' OR t.state = $4 OR ($4 = 'OPEN' AND t.state <> 'COMPLETED'))
  AND ($5::text IS NULL OR t.work_mode = $5)
  AND ($6::text IS NULL OR t.task_id IN (
        SELECT task_id FROM fn_focus_tasks($1, $6, $7, $8, $9, LOCALTIMESTAMP)))
ORDER BY (t.status = 'COMPLETED'), ${TASK_ORDER[key]}`),
  ]),
) as Record<TaskSort, ReturnType<typeof sql<TaskRow>>>;

export type TaskQuery = {
  courseId: number | null;
  type: string | null;
  status: keyof typeof TASK_FILTERS.status;
  mode: keyof typeof TASK_FILTERS.mode | null;
  focus: keyof typeof TASK_FILTERS.focus | null;
  sort: TaskSort;
};

export function taskList(userId: number, f: TaskQuery) {
  return taskListQueries[f.sort].run(
    userId, f.courseId, f.type, f.status, f.mode, f.focus,
    ANALYSIS.defaultWindow, ANALYSIS.pressureWindow, ANALYSIS.weeks,
  );
}

export const taskById = sql<TaskRow & { hours_still_to_do: number }>(`SELECT t.*,
       (SELECT COALESCE(SUM(x.estimated_hours), 0)
        FROM (SELECT t.estimated_hours, t.state
              UNION ALL
              SELECT p.estimated_hours, p.state FROM fn_prerequisites(t.task_id) p) x
        WHERE x.state <> 'COMPLETED') AS hours_still_to_do
FROM v_task_details t
WHERE t.task_id = $1 AND t.user_id = $2`);

export type PrerequisiteRow = {
  task_id: number; title: string; deadline: string; estimated_hours: number;
  state: TaskState; depth: number; due_after_task: boolean;
};
export const prerequisites = sql<PrerequisiteRow>(`SELECT * FROM fn_prerequisites($1)`);

export type DependentRow = { task_id: number; title: string; deadline: string; state: TaskState; depth: number };
export const dependents = sql<DependentRow>(`SELECT * FROM fn_dependents($1)`);

export const taskKinds = sql<{ kind: string }>(`SELECT unnest(enum_range(NULL::task_kind))::text AS kind`);

export const addTask = sql(`CALL sp_add_task($1, $2, $3, $4, $5, $6, $7, $8, $9::int[], $10)`);
export const completeTask = sql(`CALL sp_complete_task($1, $2)`);
export const rescheduleTask = sql<{ p_shifted: number }>(`CALL sp_reschedule_task($1, $2, $3, $4)`);
export const deleteTask = sql(`DELETE FROM tasks WHERE task_id = $1 AND user_id = $2`);

// Matches in search snippets are wrapped in these markers by the database
// and split back out here, so no HTML from task text is ever rendered.
const MARK_START = "[[";
const MARK_END = "]]";
const searchQuery = sql<{
  task_id: number; title: string; course_code: string; deadline: string; state: TaskState; rank: number; snippet: string;
}>(`SELECT * FROM fn_search_tasks($1, $2, $3, $4)`);

export type Segment = { text: string; match: boolean };
export async function searchTasks(userId: number, q: string) {
  const ran = await searchQuery.run(userId, q, MARK_START, MARK_END);
  return {
    ...ran,
    rows: ran.rows.map((r) => ({
      ...r,
      snippet: r.snippet.split(MARK_START).flatMap((part, i): Segment[] => {
        if (i === 0) return [{ text: part, match: false }];
        const [hit, rest] = part.split(MARK_END);
        return [{ text: hit, match: true }, { text: rest ?? "", match: false }];
      }),
    })),
  };
}

// ------------------------------------------------------------------ courses

export const enrolledCourses = sql<{ course_id: number; course_code: string; course_name: string }>(`SELECT c.course_id, c.course_code, c.course_name
FROM enrollments e JOIN courses c USING (course_id)
WHERE e.user_id = $1
ORDER BY c.course_code`);

export const availableCourses = sql<{
  course_id: number; course_code: string; course_name: string; credits: number; description: string | null;
}>(`SELECT c.*
FROM courses c
WHERE NOT EXISTS (
    SELECT 1 FROM enrollments e
    WHERE e.course_id = c.course_id AND e.user_id = $1
)
ORDER BY c.course_code`);

export const enroll = sql(`INSERT INTO enrollments (user_id, course_id) VALUES ($1, $2)`);

// ------------------------------------------------------------------ availability

export type AvailabilityDay = { day: string; available_hours: number; is_set: boolean; is_weekend: boolean };
export const availability = sql<AvailabilityDay>(`SELECT d::date AS day,
       COALESCE(a.available_hours, 0) AS available_hours,
       (a.availability_id IS NOT NULL) AS is_set,
       fn_is_weekend(d::date) AS is_weekend
FROM generate_series(CURRENT_DATE, CURRENT_DATE + $2::int - 1, INTERVAL '1 day') d
LEFT JOIN study_availability a
       ON a.user_id = $1 AND a.available_date = d::date
ORDER BY d`);

export const setPattern = sql(`CALL sp_set_availability($1, $2, $3, $4, $5)`);

export const saveDays = sql(`INSERT INTO study_availability (user_id, available_date, available_hours)
SELECT $1, d, h FROM unnest($2::date[], $3::numeric[]) AS x(d, h)
ON CONFLICT (user_id, available_date)
DO UPDATE SET available_hours = EXCLUDED.available_hours`);

// ------------------------------------------------------------------ notes (JSONB document store)

export type ChecklistItem = { item: string; done: boolean };
export type NoteRow = {
  note_id: number; task_id: number; task_title: string; course_code: string;
  text: string; tags: string[]; checklist: ChecklistItem[]; open_items: number;
  doc: Record<string, unknown>; updated_at: string;
};

export const notesForTask = sql<NoteRow>(`SELECT * FROM v_task_notes
WHERE task_id = $1 AND user_id = $2
ORDER BY created_at`);

export const notesForUser = sql<NoteRow>(`SELECT * FROM v_task_notes
WHERE user_id = $1
  AND ($2::text IS NULL OR doc @> jsonb_build_object('tags', jsonb_build_array($2::text)))
ORDER BY updated_at DESC`);

export const noteTags = sql<{ tag: string; notes: number }>(`SELECT tag, COUNT(*) AS notes
FROM task_notes n
JOIN tasks t ON t.task_id = n.task_id,
     jsonb_array_elements_text(COALESCE(n.doc->'tags', '[]')) AS tag
WHERE t.user_id = $1
GROUP BY tag
ORDER BY notes DESC, tag`);

export const addNote = sql(`INSERT INTO task_notes (task_id, doc)
SELECT task_id, fn_make_note_doc($3, $4::text[], $5::text[])
FROM tasks
WHERE task_id = $2 AND user_id = $1`);

export const toggleNoteItem = sql(`UPDATE task_notes n
SET doc = jsonb_set(n.doc, ARRAY['checklist', $3::int::text, 'done'],
                    to_jsonb(NOT COALESCE((n.doc #>> ARRAY['checklist', $3::int::text, 'done'])::boolean, false)))
FROM tasks t
WHERE n.note_id = $2 AND t.task_id = n.task_id AND t.user_id = $1
  AND $3::int < jsonb_array_length(COALESCE(n.doc->'checklist', '[]'))`);

export const addNoteTag = sql(`UPDATE task_notes n
SET doc = jsonb_set(n.doc, '{tags}', COALESCE(n.doc->'tags', '[]') || to_jsonb(lower(btrim($3::text))))
FROM tasks t
WHERE n.note_id = $2 AND t.task_id = n.task_id AND t.user_id = $1
  AND btrim($3::text) <> ''
  AND NOT COALESCE(n.doc->'tags', '[]') ? lower(btrim($3::text))`);

export const removeNoteTag = sql(`UPDATE task_notes n
SET doc = jsonb_set(n.doc, '{tags}', COALESCE(n.doc->'tags', '[]') - $3::text)
FROM tasks t
WHERE n.note_id = $2 AND t.task_id = n.task_id AND t.user_id = $1`);

export const deleteNote = sql(`DELETE FROM task_notes n
USING tasks t
WHERE n.note_id = $2 AND t.task_id = n.task_id AND t.user_id = $1`);

// ------------------------------------------------------------------ vectors (embedding store)

export type SimilarRow = { task_id: number; title: string; course_code: string; state: TaskState; similarity: number };
export const similarTasks = sql<SimilarRow>(`SELECT * FROM fn_similar_tasks($1, 5)`);

export const vectorSearch = sql<SimilarRow & { deadline: string }>(`SELECT * FROM fn_vector_search($1, $2, 8)`);

export const embeddingInfo = sql<{ model: string; dims: number; embedded_at: string; preview: number[] }>(`SELECT model, array_length(embedding, 1) AS dims, embedded_at, embedding[1:6] AS preview
FROM task_embeddings
WHERE task_id = $1`);

// ------------------------------------------------------------------ admin (checked by role in the database)

export type AdminRow = {
  user_id: number; name: string; email: string; role: Role; created_at: string;
  courses: number; pending_tasks: number; overdue_tasks: number; pending_hours: number; critical_tasks: number;
};
export const adminOverview = sql<AdminRow>(`SELECT * FROM v_admin_overview WHERE fn_is_admin($1) ORDER BY role, name`);

export const adminCourses = sql<{
  course_id: number; course_code: string; course_name: string; course_type: CourseType; semester: number; credits: number; students: number;
}>(`SELECT c.course_id, c.course_code, c.course_name, c.course_type, c.semester, c.credits, COUNT(e.user_id) AS students
FROM courses c
LEFT JOIN enrollments e ON e.course_id = c.course_id
WHERE fn_is_admin($1)
GROUP BY c.course_id
ORDER BY c.semester DESC, c.course_code`);

export const adminSetRole = sql(`CALL sp_admin_set_role($1, $2, $3)`);
export const adminAddCourse = sql(`CALL sp_admin_add_course($1, $2, $3, $4, $5, $6, $7)`);

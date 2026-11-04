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

export const userById = sql<{ user_id: number; name: string; email: string }>(
  `SELECT user_id, name, email FROM users WHERE user_id = $1`,
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


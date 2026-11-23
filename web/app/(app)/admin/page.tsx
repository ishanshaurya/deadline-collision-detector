import * as Q from "@/lib/queries";
import { requireAdmin } from "@/lib/session";
import { hours } from "@/lib/format";
import { Card, CourseTypeTag, SqlPeek } from "@/components/ui";
import { adminAddCourse, adminSetRole } from "@/app/actions";

export default async function Admin() {
  const user = await requireAdmin();
  const [people, courses] = await Promise.all([
    Q.adminOverview.run(user.user_id),
    Q.adminCourses.run(user.user_id),
  ]);
  const students = people.rows.filter((p) => p.role === "STUDENT");
  const atRisk = students.filter((p) => p.critical_tasks > 0).length;

  return (
    <>
      <header className="page-head">
        <div>
          <span className="eyebrow">admin</span>
          <h1>accounts and courses</h1>
          <p>{students.length} students, {atRisk} with tasks they can&apos;t finish in time. Every query here checks your role inside the database.</p>
        </div>
      </header>

      <Card title="accounts">
        <div className="table-wrap">
          <table>
            <thead>
              <tr><th>name</th><th>email</th><th>courses</th><th>pending</th><th>overdue</th><th>hours left</th><th>won&apos;t fit</th><th>role</th></tr>
            </thead>
            <tbody>
              {people.rows.map((p) => (
                <tr key={p.user_id}>
                  <td><strong>{p.name}</strong></td>
                  <td>{p.email}</td>
                  <td className="mono">{p.courses}</td>
                  <td className="mono">{p.pending_tasks}</td>
                  <td className={`mono ${p.overdue_tasks > 0 ? "tomato" : ""}`}>{p.overdue_tasks}</td>
                  <td className="mono">{hours(p.pending_hours)}</td>
                  <td className={`mono ${p.critical_tasks > 0 ? "tomato" : ""}`}>{p.critical_tasks}</td>
                  <td>
                    <form action={adminSetRole} className="role-form">
                      <input type="hidden" name="user_id" value={p.user_id} />
                      <label className="sr-only" htmlFor={`role-${p.user_id}`}>Role for {p.name}</label>
                      <select id={`role-${p.user_id}`} name="role" defaultValue={p.role}>
                        <option value="STUDENT">student</option>
                        <option value="ADMIN">admin</option>
                      </select>
                      <button className="btn btn-sm">save</button>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="muted small" style={{ margin: 0 }}>Role changes go through sp_admin_set_role, which refuses non-admins and won&apos;t remove the last admin.</p>
        <SqlPeek query={people} />
      </Card>

      <div className="grid-2">
        <Card title={`course catalogue (${courses.rows.length})`}>
          <div className="table-wrap">
            <table>
              <thead><tr><th>code</th><th>name</th><th>type</th><th>sem</th><th>credits</th><th>students</th></tr></thead>
              <tbody>
                {courses.rows.map((c) => (
                  <tr key={c.course_id}>
                    <td className="mono small">{c.course_code}</td>
                    <td>{c.course_name}</td>
                    <td><CourseTypeTag type={c.course_type} /></td>
                    <td className="mono">{c.semester}</td>
                    <td className="mono">{c.credits}</td>
                    <td className="mono">{c.students}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <SqlPeek query={courses} />
        </Card>

        <Card title="add a course">
          <form action={adminAddCourse} className="form">
            <div className="row">
              <label>code<input name="course_code" required maxLength={20} placeholder="UE24CS353A" /></label>
              <label>type
                <select name="course_type" defaultValue="CC">
                  <option value="CC">core</option>
                  <option value="EC">elective</option>
                </select>
              </label>
            </div>
            <label>name<input name="course_name" required maxLength={150} /></label>
            <div className="row">
              <label>semester<input name="semester" type="number" min={1} max={8} defaultValue={5} required /></label>
              <label>credits<input name="credits" type="number" min={1} max={10} defaultValue={4} required /></label>
            </div>
            <label>description<textarea name="description" rows={2} /></label>
            <button className="btn btn-ink" style={{ alignSelf: "flex-start" }}>add course</button>
          </form>
          <SqlPeek query={Q.adminAddCourse} />
        </Card>
      </div>
    </>
  );
}

import * as Q from "@/lib/queries";
import { ANALYSIS } from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { addDays, fmtDate } from "@/lib/format";
import { Card, SqlPeek } from "@/components/ui";
import { saveDays, setPattern } from "@/app/actions";

export default async function Availability() {
  const user = await requireUser();
  const days = await Q.availability.run(user.user_id, ANALYSIS.horizonDays);
  const total = days.rows.reduce((a, d) => a + d.available_hours, 0);
  const today = days.rows[0].day;

  return (
    <>
      <header className="page-head">
        <div>
          <h1>study time</h1>
          <p>Hours you can realistically study each day. Every risk number is measured against this.</p>
        </div>
      </header>

      <div className="split">
        <div className="main-col">
        <Card title={`next ${days.rows.length} days (${total}h)`}>
          <form action={saveDays}>
            <div className="days">
              {days.rows.map((d) => (
                <label key={d.day} className={`day ${d.is_weekend ? "day-weekend" : ""} ${d.is_set ? "" : "day-unset"}`}>
                  <span>{fmtDate(d.day)}</span>
                  <input type="hidden" name="day" value={d.day} />
                  <input type="number" name="hours" min="0" max="24" step="0.5" defaultValue={d.available_hours} />
                </label>
              ))}
            </div>
            <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap", marginTop: 14 }}>
              <button className="btn btn-ink">save all days</button>
              <span className="muted small">One INSERT … ON CONFLICT statement: all days are saved or none are.</span>
            </div>
          </form>
          <SqlPeek query={Q.saveDays} />
        </Card>
        </div>

        <div className="side-col">
        <Card title="weekly pattern" outline>
          <form action={setPattern} className="form">
            <div className="row">
              <label>from<input type="date" name="from" defaultValue={today} required /></label>
              <label>to<input type="date" name="to" defaultValue={addDays(today, 7 * ANALYSIS.weeks - 1)} required /></label>
            </div>
            <div className="row">
              <label>weekdays<input type="number" name="weekday" min="0" max="24" step="0.5" defaultValue="3" required /></label>
              <label>weekends<input type="number" name="weekend" min="0" max="24" step="0.5" defaultValue="6" required /></label>
            </div>
            <button className="btn btn-tomato">apply pattern</button>
          </form>
          <SqlPeek query={Q.setPattern} />
        </Card>
        </div>
      </div>
    </>
  );
}

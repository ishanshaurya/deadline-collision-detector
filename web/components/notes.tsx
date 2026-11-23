import Link from "next/link";
import type { NoteRow } from "@/lib/queries";
import { fmtDateTime } from "@/lib/format";
import { addNote, addNoteTag, deleteNote, removeNoteTag, toggleNoteItem } from "@/app/actions";

// Keys every note has; anything else in the document is shown as raw JSON.
const KNOWN_KEYS = new Set(["text", "tags", "checklist"]);

export function NoteItem({ n, showTask = false }: { n: NoteRow; showTask?: boolean }) {
  const extra = Object.fromEntries(Object.entries(n.doc).filter(([k]) => !KNOWN_KEYS.has(k)));
  return (
    <article className="note">
      {showTask && (
        <div className="meta small">
          <span className="tag">{n.course_code}</span> <Link href={`/tasks/${n.task_id}`} style={{ fontWeight: 600 }}>{n.task_title}</Link>
        </div>
      )}
      <p style={{ margin: 0 }}>{n.text}</p>

      {n.checklist.length > 0 && (
        <ul className="checklist">
          {n.checklist.map((c, i) => (
            <li key={i}>
              <form action={toggleNoteItem}>
                <input type="hidden" name="note_id" value={n.note_id} />
                <input type="hidden" name="index" value={i} />
                <button className={`tick ${c.done ? "tick-done" : ""}`} aria-label={`${c.done ? "Untick" : "Tick"} ${c.item}`}>
                  {c.done ? "✓" : ""}
                </button>
              </form>
              <span className={c.done ? "muted done-item" : ""}>{c.item}</span>
            </li>
          ))}
        </ul>
      )}

      {Object.keys(extra).length > 0 && <pre className="doc-extra">{JSON.stringify(extra, null, 2)}</pre>}

      <div className="note-foot">
        {n.tags.map((t) => (
          <form key={t} action={removeNoteTag} className="tag-chip">
            <input type="hidden" name="note_id" value={n.note_id} />
            <input type="hidden" name="tag" value={t} />
            <Link href={`/notes?tag=${encodeURIComponent(t)}`}>#{t}</Link>
            <button aria-label={`Remove tag ${t}`}>×</button>
          </form>
        ))}
        <form action={addNoteTag} className="tag-add">
          <input type="hidden" name="note_id" value={n.note_id} />
          <label className="sr-only" htmlFor={`tag-${n.note_id}`}>Add tag</label>
          <input id={`tag-${n.note_id}`} name="tag" placeholder="+ tag" maxLength={30} />
        </form>
        <span className="muted small" style={{ marginLeft: "auto" }}>{fmtDateTime(n.updated_at)}</span>
        <form action={deleteNote}>
          <input type="hidden" name="note_id" value={n.note_id} />
          <button className="btn btn-ghost btn-sm">delete</button>
        </form>
      </div>
    </article>
  );
}

export function NoteForm({ taskId }: { taskId: number }) {
  return (
    <form action={addNote} className="form">
      <input type="hidden" name="task_id" value={taskId} />
      <label>note<textarea name="text" rows={2} required placeholder="What to remember about this task" /></label>
      <div className="row">
        <label>tags (comma separated)<input name="tags" placeholder="viva, report" /></label>
        <label>checklist (one item per line)<textarea name="checklist" rows={2} /></label>
      </div>
      <button className="btn btn-ink" style={{ alignSelf: "flex-start" }}>save note</button>
    </form>
  );
}

import Link from "next/link";
import * as Q from "@/lib/queries";
import { requireUser } from "@/lib/session";
import { Card, SqlPeek } from "@/components/ui";
import { NoteItem } from "@/components/notes";

export default async function Notes({ searchParams }: { searchParams: Promise<{ tag?: string }> }) {
  const user = await requireUser();
  const tag = (await searchParams).tag?.trim().toLowerCase() || null;

  const [notes, tags] = await Promise.all([
    Q.notesForUser.run(user.user_id, tag),
    Q.noteTags.run(user.user_id),
  ]);
  const openItems = notes.rows.reduce((sum, n) => sum + n.open_items, 0);

  return (
    <>
      <header className="page-head">
        <div>
          <h1>notes</h1>
          <p>{notes.rows.length} note{notes.rows.length === 1 ? "" : "s"}{tag ? ` tagged #${tag}` : ""}, {openItems} checklist item{openItems === 1 ? "" : "s"} still open. Add notes from any task page.</p>
        </div>
      </header>

      <Card title="tags">
        {tags.rows.length === 0 ? <p className="empty">No tags yet.</p> : (
          <nav className="seg" aria-label="Filter by tag">
            <Link href="/notes" aria-current={tag === null ? "true" : undefined}>all</Link>
            {tags.rows.map((t) => (
              <Link key={t.tag} href={`/notes?tag=${encodeURIComponent(t.tag)}`} aria-current={tag === t.tag ? "true" : undefined}>
                #{t.tag} <span className="muted small" style={{ marginLeft: 6 }}>{t.notes}</span>
              </Link>
            ))}
          </nav>
        )}
        <SqlPeek query={tags} />
      </Card>

      <Card title={tag ? `#${tag}` : "all notes"}>
        <p className="muted small" style={{ margin: 0 }}>
          Filtering uses JSONB containment (<code>doc @&gt; {"'{\"tags\": [...]}'"}</code>) on a GIN index. Documents keep whatever extra keys they were saved with.
        </p>
        {notes.rows.length === 0 ? <p className="empty">No notes{tag ? " with this tag" : ""}.</p> : (
          <div className="notes">
            {notes.rows.map((n) => <NoteItem key={n.note_id} n={n} showTask />)}
          </div>
        )}
        <SqlPeek query={notes} />
      </Card>
    </>
  );
}

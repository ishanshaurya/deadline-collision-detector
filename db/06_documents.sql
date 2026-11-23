-- =====================================================================
-- Document store (NoSQL) inside PostgreSQL
-- task_notes is a schemaless collection: each note is one JSONB document.
-- Only "text" is required; "tags", "checklist", "links" or any other key
-- can be added per document without changing the table. The GIN index
-- answers containment queries such as doc @> '{"tags": ["viva"]}'.
-- =====================================================================

CREATE TABLE task_notes (
    note_id     SERIAL PRIMARY KEY,
    task_id     INTEGER NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
    doc         JSONB NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT doc_is_object       CHECK (jsonb_typeof(doc) = 'object'),
    CONSTRAINT doc_has_text        CHECK (COALESCE(btrim(doc->>'text'), '') <> ''),
    CONSTRAINT doc_tags_array      CHECK (NOT doc ? 'tags'      OR jsonb_typeof(doc->'tags') = 'array'),
    CONSTRAINT doc_checklist_array CHECK (NOT doc ? 'checklist' OR jsonb_typeof(doc->'checklist') = 'array')
);

CREATE INDEX idx_task_notes_task ON task_notes (task_id);
CREATE INDEX idx_task_notes_doc  ON task_notes USING GIN (doc jsonb_path_ops);

CREATE TRIGGER task_notes_updated_at
    BEFORE UPDATE ON task_notes
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- ---------------------------------------------------------------------
-- fn_make_note_doc: build a note document from form input. Tags are
-- trimmed, lower-cased and de-duplicated; checklist lines become
-- {"item": ..., "done": false} objects.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_make_note_doc(p_text TEXT, p_tags TEXT[], p_items TEXT[])
RETURNS JSONB AS $$
    SELECT jsonb_build_object(
        'text', btrim(p_text),
        'tags', (SELECT COALESCE(jsonb_agg(DISTINCT lower(btrim(t))), '[]'::jsonb)
                 FROM unnest(p_tags) AS t
                 WHERE btrim(t) <> ''),
        'checklist', (SELECT COALESCE(jsonb_agg(jsonb_build_object('item', btrim(i), 'done', false) ORDER BY n), '[]'::jsonb)
                      FROM unnest(p_items) WITH ORDINALITY AS x(i, n)
                      WHERE btrim(i) <> '')
    );
$$ LANGUAGE sql IMMUTABLE;

-- ---------------------------------------------------------------------
-- v_task_notes: the documents projected back into columns, with the
-- owning task and the number of unticked checklist items
-- ---------------------------------------------------------------------
CREATE VIEW v_task_notes AS
SELECT n.note_id, n.task_id, t.user_id, t.title AS task_title, c.course_code,
       n.doc->>'text' AS text,
       ARRAY(SELECT jsonb_array_elements_text(COALESCE(n.doc->'tags', '[]'::jsonb))) AS tags,
       COALESCE(n.doc->'checklist', '[]'::jsonb) AS checklist,
       (SELECT COUNT(*)
        FROM jsonb_array_elements(COALESCE(n.doc->'checklist', '[]'::jsonb)) i
        WHERE NOT COALESCE((i->>'done')::boolean, false)) AS open_items,
       n.doc, n.created_at, n.updated_at
FROM task_notes n
JOIN tasks t   ON t.task_id = n.task_id
JOIN courses c ON c.course_id = t.course_id;

-- ---------------------------------------------------------------------
-- Demo documents. Two use extra keys ("links", "split") that the other
-- notes don't have, which is the point of a schemaless collection.
-- ---------------------------------------------------------------------
INSERT INTO task_notes (task_id, doc)
SELECT t.task_id, d.doc
FROM (VALUES
    ('DBMS mini project submission',
     fn_make_note_doc('Viva prep: be ready to explain the cycle trigger and the EDF slack calculation.',
                      ARRAY['viva', 'dbms'],
                      ARRAY['Rehearse triggers demo', 'Run transactions.sql scenario 3', 'Print the report'])),
    ('DBMS mini project submission',
     '{"text": "Report checklist from the course page", "tags": ["report", "dbms"],
       "links": ["https://github.com/ishanshaurya/deadline-collision-detector"],
       "checklist": [{"item": "Cover page with both SRNs", "done": true},
                     {"item": "ER diagram redrawn", "done": false}]}'::jsonb),
    ('ML project report',
     '{"text": "Split the report so the training section is written while the model runs",
       "tags": ["ml", "report"], "split": {"methods": 3, "results": 4, "error analysis": 2}}'::jsonb),
    ('Dataset cleaning for ML project',
     fn_make_note_doc('Drop rows with missing labels before normalising features.',
                      ARRAY['ml', 'data'],
                      ARRAY['Check class balance', 'Save the cleaned CSV'])),
    ('Crypto quiz 2',
     fn_make_note_doc('Revise modular inverse and RSA key generation.', ARRAY['revision', 'quiz'], ARRAY[]::text[]))
) AS d(title, doc)
JOIN tasks t ON t.title = d.title
JOIN users u ON u.user_id = t.user_id AND u.email = 'aarav@dcd.edu';

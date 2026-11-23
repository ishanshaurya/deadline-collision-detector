-- =====================================================================
-- Document store and vector store demo (psql). Run after npm run db:setup.
-- Everything runs inside one transaction and is rolled back at the end.
-- =====================================================================

SELECT user_id AS aarav FROM users WHERE email = 'aarav@dcd.edu' \gset
SELECT task_id AS project FROM tasks WHERE user_id = :aarav AND title = 'DBMS mini project submission' \gset

BEGIN;

-- [Document store] the raw documents: notes don't share one shape
SELECT note_id, jsonb_pretty(doc) FROM task_notes WHERE task_id = :project;

-- [Read] containment query on the GIN index: every note tagged "dbms"
SELECT note_id, doc->>'text' AS text FROM task_notes WHERE doc @> '{"tags": ["dbms"]}';

-- [Read] path query: notes that carry a "split" object, and its keys
SELECT note_id, jsonb_object_keys(doc->'split') AS part FROM task_notes WHERE doc ? 'split';

-- [Read] unnest a document array: tag counts across all notes
SELECT tag, COUNT(*) FROM task_notes, jsonb_array_elements_text(doc->'tags') AS tag
GROUP BY tag ORDER BY 2 DESC, 1;

-- [Create] a document with a key no other note has
INSERT INTO task_notes (task_id, doc)
VALUES (:project, '{"text": "Ask about the viva slot", "tags": ["viva"], "remind_on": "2026-11-20"}')
RETURNING note_id \gset

-- [Update] tick the first checklist item of the viva note (path update)
UPDATE task_notes
SET doc = jsonb_set(doc, '{checklist,0,done}', 'true')
WHERE task_id = :project AND doc @> '{"tags": ["viva"]}' AND doc ? 'checklist'
RETURNING note_id, doc->'checklist'->0 AS first_item;

-- [Update] add a tag (array append) and remove a key (#- operator)
UPDATE task_notes SET doc = jsonb_set(doc, '{tags}', doc->'tags' || '"urgent"') WHERE note_id = :note_id;
UPDATE task_notes SET doc = doc #- '{remind_on}' WHERE note_id = :note_id RETURNING doc;

-- [Delete] remove a tag value from the array, then the whole document
UPDATE task_notes SET doc = jsonb_set(doc, '{tags}', (doc->'tags') - 'urgent') WHERE note_id = :note_id RETURNING doc->'tags';
DELETE FROM task_notes WHERE note_id = :note_id;

-- [Vector store] one embedding: 384 numbers, unit length
SELECT task_id, model, array_length(embedding, 1) AS dims,
       round(sqrt((SELECT SUM(x * x) FROM unnest(embedding) x))::numeric, 3) AS length
FROM task_embeddings WHERE task_id = :project;

-- [Read] nearest neighbours of the mini project
SELECT * FROM fn_similar_tasks(:project, 5);

-- [Read] search by similarity: typos still find the right task
SELECT title, similarity FROM fn_vector_search(:aarav, 'datbase projct viva', 5);
SELECT title, similarity FROM fn_vector_search(:aarav, 'machine lerning model', 5);

-- [Update] editing the task re-embeds it through the trigger
SELECT embedded_at FROM task_embeddings WHERE task_id = :project;
UPDATE tasks SET description = description || ' Includes a pgvector style similarity search.' WHERE task_id = :project;
SELECT embedded_at FROM task_embeddings WHERE task_id = :project;

-- [Delete] deleting a task cascades to its notes and its vector
DELETE FROM tasks WHERE task_id = :project;
SELECT COUNT(*) AS notes_left   FROM task_notes      WHERE task_id = :project;
SELECT COUNT(*) AS vectors_left FROM task_embeddings WHERE task_id = :project;

ROLLBACK;

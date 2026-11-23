-- =====================================================================
-- Vector store inside PostgreSQL
-- Every task gets an embedding: its text (title, description, course name
-- and note texts) turned into a 384-dimension unit vector. Words and
-- character trigrams are hashed into the 384 slots (the hashing trick), so
-- "datbase projct" still lands near "database project". Similarity is the
-- cosine of two vectors. Vectors are plain REAL[] so no extension has to
-- be installed; with pgvector the column would become vector(384) and the
-- similarity the <=> operator.
-- =====================================================================

CREATE TABLE task_embeddings (
    task_id      INTEGER PRIMARY KEY REFERENCES tasks(task_id) ON DELETE CASCADE,
    embedding    REAL[] NOT NULL,
    model        TEXT NOT NULL DEFAULT 'hashed-trigram-384',
    embedded_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT embedding_dims CHECK (array_length(embedding, 1) = 384)
);

-- ---------------------------------------------------------------------
-- fn_embed: text -> 384-dim unit vector. Common filler words are
-- dropped; whole words weigh 2, each character trigram of a word weighs 1; the vector is L2-normalised so
-- the dot product of two embeddings is their cosine similarity.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_embed(p_text TEXT)
RETURNS REAL[] AS $$
    WITH words AS (
        SELECT w
        FROM regexp_split_to_table(lower(coalesce(p_text, '')), '[^a-z0-9]+') AS w
        WHERE length(w) > 1
          AND w NOT IN ('the', 'and', 'for', 'with', 'of', 'to', 'in', 'on', 'an', 'by', 'from',
                        'is', 'it', 'be', 'at', 'as', 'or', 'that', 'this', 'your', 'you', 'into')
    ),
    features AS (
        SELECT 'w:' || w AS f, 2.0 AS weight FROM words
        UNION ALL
        SELECT 't:' || substr(' ' || w || ' ', i, 3), 1.0
        FROM words, generate_series(1, length(w)) AS i
    ),
    slots AS (
        SELECT ((hashtext(f)::bigint % 384) + 384) % 384 + 1 AS slot, SUM(weight) AS v
        FROM features
        GROUP BY 1
    ),
    norm AS (SELECT sqrt(SUM(v * v)) AS n FROM slots)
    SELECT array_agg(COALESCE(s.v / NULLIF(norm.n, 0), 0)::real ORDER BY g)
    FROM generate_series(1, 384) AS g
    CROSS JOIN norm
    LEFT JOIN slots s ON s.slot = g;
$$ LANGUAGE sql IMMUTABLE;

CREATE FUNCTION fn_cosine(a REAL[], b REAL[])
RETURNS DOUBLE PRECISION AS $$
    SELECT SUM(x * y) / NULLIF(sqrt(SUM(x * x)) * sqrt(SUM(y * y)), 0)
    FROM unnest(a, b) AS v(x, y);
$$ LANGUAGE sql IMMUTABLE;

-- the text a task is embedded from
CREATE FUNCTION fn_task_text(p_task_id INTEGER)
RETURNS TEXT AS $$
    SELECT concat_ws(' ', t.title, t.description, c.course_name,
                     (SELECT string_agg(n.doc->>'text', ' ') FROM task_notes n WHERE n.task_id = t.task_id))
    FROM tasks t
    JOIN courses c ON c.course_id = t.course_id
    WHERE t.task_id = p_task_id;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_refresh_embedding: upsert one task's vector, or remove it if the
-- task is gone (a note deleted by the task's own cascade lands here).
-- SECURITY DEFINER so a student session under row-level security can
-- keep its own vectors current without write access to the store.
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_refresh_embedding(p_task_id INTEGER)
RETURNS VOID AS $$
DECLARE
    v_text TEXT;
BEGIN
    v_text := fn_task_text(p_task_id);
    IF v_text IS NULL THEN
        DELETE FROM task_embeddings WHERE task_id = p_task_id;
        RETURN;
    END IF;

    INSERT INTO task_embeddings (task_id, embedding)
    VALUES (p_task_id, fn_embed(v_text))
    ON CONFLICT (task_id)
    DO UPDATE SET embedding = EXCLUDED.embedding, embedded_at = clock_timestamp();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE FUNCTION trg_embed_task() RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_refresh_embedding(NEW.task_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tasks_embed
    AFTER INSERT OR UPDATE OF title, description, course_id ON tasks
    FOR EACH ROW EXECUTE FUNCTION trg_embed_task();

CREATE FUNCTION trg_embed_note() RETURNS TRIGGER AS $$
BEGIN
    PERFORM fn_refresh_embedding(CASE WHEN TG_OP = 'DELETE' THEN OLD.task_id ELSE NEW.task_id END);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER task_notes_embed
    AFTER INSERT OR UPDATE OF doc OR DELETE ON task_notes
    FOR EACH ROW EXECUTE FUNCTION trg_embed_note();

-- ---------------------------------------------------------------------
-- fn_similar_tasks: nearest neighbours of one task among the same
-- student's tasks
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_similar_tasks(p_task_id INTEGER, p_limit INTEGER)
RETURNS TABLE (
    task_id      INTEGER,
    title        VARCHAR,
    course_code  VARCHAR,
    state        TEXT,
    similarity   DOUBLE PRECISION
) AS $$
    SELECT v.task_id, v.title, v.course_code, v.state,
           ROUND(fn_cosine(me.embedding, e.embedding)::numeric, 3)::double precision
    FROM task_embeddings me
    JOIN tasks src          ON src.task_id = me.task_id
    JOIN task_embeddings e  ON e.task_id <> me.task_id
    JOIN v_task_details v   ON v.task_id = e.task_id AND v.user_id = src.user_id
    WHERE me.task_id = p_task_id
    ORDER BY 5 DESC, v.deadline
    LIMIT p_limit;
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------
-- fn_vector_search: embed the query text and rank the student's tasks
-- by cosine similarity (typos and word order don't matter much)
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_vector_search(p_user_id INTEGER, p_query TEXT, p_limit INTEGER)
RETURNS TABLE (
    task_id      INTEGER,
    title        VARCHAR,
    course_code  VARCHAR,
    deadline     TIMESTAMP,
    state        TEXT,
    similarity   DOUBLE PRECISION
) AS $$
    SELECT v.task_id, v.title, v.course_code, v.deadline, v.state,
           ROUND(fn_cosine(q.vec, e.embedding)::numeric, 3)::double precision
    FROM (SELECT fn_embed(p_query) AS vec) q
    CROSS JOIN task_embeddings e
    JOIN v_task_details v ON v.task_id = e.task_id
    WHERE v.user_id = p_user_id
      AND fn_cosine(q.vec, e.embedding) > 0.15
    ORDER BY 6 DESC, v.deadline
    LIMIT p_limit;
$$ LANGUAGE sql STABLE;

-- vectors for the tasks seeded before this file existed
SELECT fn_refresh_embedding(task_id) FROM tasks;

CREATE TABLE IF NOT EXISTS notes (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    filename TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

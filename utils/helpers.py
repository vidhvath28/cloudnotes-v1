import os

import psycopg2
import psycopg2.extras

MIGRATIONS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "migrations")

ALLOWED_EXTENSIONS = {"txt", "md", "pdf", "png", "jpg", "jpeg", "gif"}


def get_db_connection(database_url):
    return psycopg2.connect(database_url, cursor_factory=psycopg2.extras.RealDictCursor)


def run_migrations(database_url):
    """Apply every migrations/*.sql file once, in filename order."""
    conn = get_db_connection(database_url)
    try:
        with conn, conn.cursor() as cur:
            # Serialise concurrent callers (e.g. several gunicorn workers starting at once).
            cur.execute("SELECT pg_advisory_xact_lock(4242)")
            cur.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations ("
                " version TEXT PRIMARY KEY,"
                " applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
            )
            cur.execute("SELECT version FROM schema_migrations")
            applied = {row["version"] for row in cur.fetchall()}
            for name in sorted(os.listdir(MIGRATIONS_DIR)):
                if not name.endswith(".sql") or name in applied:
                    continue
                with open(os.path.join(MIGRATIONS_DIR, name)) as f:
                    cur.execute(f.read())
                cur.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (name,))
                print(f"applied migration {name}")
    finally:
        conn.close()


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

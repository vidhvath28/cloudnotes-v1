This repository contains a local Flask web application.

- The application entry point is `app.py`.
- HTML templates are stored in the `templates/` folder.
- Static content is grouped under `static/`.
- Uploaded files are written to the `uploads/` directory.
- Data is stored in PostgreSQL (`DATABASE_URL`); the schema lives in `migrations/`.
- REST API routes are implemented under `api/routes.py`.
- Helper functions for database access are in `utils/helpers.py`.

Deployment scripts live in `deploy/`; see `deployment.md` and `cloud-mapping.md`.

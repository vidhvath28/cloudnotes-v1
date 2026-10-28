# CloudNotes

A small Flask notes app (notes + file attachments), deployed as a systemd
service on Linux with PostgreSQL.

- [`deployment.md`](deployment.md): environment, setup commands, the service, the access path, evidence
- [`cloud-mapping.md`](cloud-mapping.md): how the local deployment maps to Google Compute Engine
- [`deploy/setup.sh`](deploy/setup.sh): one-shot provisioning for a fresh Ubuntu server
- [`deploy/cloudnotes.service`](deploy/cloudnotes.service): systemd unit
- [`.env.example`](.env.example): configuration template (copy to `.env`, never commit it)

Run locally against a PostgreSQL database:

```bash
python3 -m venv venv && . venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # set DATABASE_URL, SECRET_KEY, UPLOAD_FOLDER
python migrate.py
gunicorn --bind 0.0.0.0:5000 app:app
```

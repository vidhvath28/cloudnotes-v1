# Deploying CloudNotes on a Linux server

CloudNotes runs as an always-on systemd service on an Ubuntu VM, behind
gunicorn, with its data in PostgreSQL. All of the evidence below comes from
real runs and is saved in [`docs/evidence/`](docs/evidence/).

## Environment

| | |
|---|---|
| Host | MacBook (Apple Silicon, macOS) |
| Linux server | Ubuntu 26.04.1 LTS VM, aarch64, 2 vCPU / 2 GiB RAM / 10 GiB disk |
| Hypervisor | [Lima](https://lima-vm.io) using Apple Virtualization.framework (the same kind of free local VM as UTM or VirtualBox) |
| Init / service manager | systemd (PID 1) |
| App server | gunicorn 22, 2 workers, bound to `0.0.0.0:5000` |
| Database | PostgreSQL 18 on the same VM (`localhost:5432`) |
| Firewall | ufw: default deny incoming; allow `OpenSSH` and `5000/tcp` |

## What changed in the app

- **SQLite → PostgreSQL.** `utils/helpers.py` connects with `psycopg2` using
  `DATABASE_URL`; queries use `%s` placeholders and `INSERT ... RETURNING id`.
  The committed `database/cloudnotes.db` file is gone.
- **Migrations.** `migrations/001_create_notes.sql` holds the schema.
  `python migrate.py` applies any new file exactly once and records it in a
  `schema_migrations` table. systemd runs it (`ExecStartPre`) before every start.
- **Config from environment.** `SECRET_KEY`, `DATABASE_URL` and `UPLOAD_FOLDER`
  are read from the environment (`.env` locally, `EnvironmentFile=` under
  systemd). `.env.example` has placeholders; `.env` is git-ignored.
- **Bind address.** `python app.py` now binds to `0.0.0.0` (it used to bind to
  `127.0.0.1`) with debug off unless `FLASK_DEBUG=1`. In production gunicorn
  does the binding.
- **Startup fix.** `@app.before_first_request` was removed in Flask 2.3, so the
  app could not start. Upload-dir creation now runs at import time and the
  schema is handled by migrations. `Flask==2.3.5` (not a real release) became
  `2.3.3`; `gunicorn` and `psycopg2-binary` were added.
- **`/healthz`.** Returns status, hostname and worker PID after a `SELECT 1`
  against the database. Handy for checks and for seeing which process answered.

## Setup commands

### 1. Create the Linux server (on the Mac)

```bash
brew install lima
limactl create --name=cloudnotes --cpus=2 --memory=2 --disk=10 template://ubuntu-lts
limactl start cloudnotes
limactl shell cloudnotes          # opens a shell on the VM
```

### 2. Provision and deploy (on the VM)

Everything is in [`deploy/setup.sh`](deploy/setup.sh), which is safe to re-run:

```bash
git clone -b feature/linux-deploy https://github.com/vidhvath28/cloudnotes-v1.git
sudo bash cloudnotes-v1/deploy/setup.sh        # or: sudo bash deploy/setup.sh /path/to/local/checkout
```

The script does the following, step by step:

```bash
# 1. system packages
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip postgresql postgresql-contrib ufw git curl rsync

# 2. dedicated, unprivileged service user
sudo useradd --create-home --shell /bin/bash cloudnotes

# 3. code -> /home/cloudnotes/cloudnotes  (git clone, or rsync from a local checkout)

# 4. Python deps in a venv
sudo -u cloudnotes python3 -m venv /home/cloudnotes/cloudnotes/venv
sudo -u cloudnotes /home/cloudnotes/cloudnotes/venv/bin/pip install -r /home/cloudnotes/cloudnotes/requirements.txt

# 5. PostgreSQL database + user, .env with generated secrets (chmod 600), migrations
sudo systemctl enable --now postgresql
sudo -u postgres psql -c "CREATE ROLE cloudnotes WITH LOGIN PASSWORD '<random>'"
sudo -u postgres createdb --owner=cloudnotes cloudnotes
#   .env -> SECRET_KEY=<random>, DATABASE_URL=postgresql://cloudnotes:<random>@localhost:5432/cloudnotes
sudo -u cloudnotes bash -c 'cd /home/cloudnotes/cloudnotes && venv/bin/python migrate.py'

# 6. systemd service
sudo install -m 644 deploy/cloudnotes.service /etc/systemd/system/cloudnotes.service
sudo systemctl daemon-reload
sudo systemctl enable cloudnotes     # start on boot
sudo systemctl restart cloudnotes    # start now

# 7. firewall
sudo ufw allow OpenSSH
sudo ufw allow 5000/tcp
sudo ufw --force enable
```

The trimmed output of a real run is in
[`docs/evidence/setup-run.log`](docs/evidence/setup-run.log).

## The managed service

[`deploy/cloudnotes.service`](deploy/cloudnotes.service):

- `User=cloudnotes` means the app never runs as root.
- `EnvironmentFile=.../.env` injects config and secrets.
- `ExecStartPre=... migrate.py` keeps the schema current before each start.
- `ExecStart=... gunicorn --workers 2 --bind 0.0.0.0:5000 app:app`
- `Restart=always` + `RestartSec=2` heal the app after a crash or kill.
- `Requires=/After=postgresql.service` makes the database start first.
- `WantedBy=multi-user.target` + `systemctl enable` start the app on boot.

Useful commands:

```bash
sudo systemctl status cloudnotes
sudo journalctl -u cloudnotes -f
sudo systemctl restart cloudnotes
```

## Access path

```
browser on the Mac (http://localhost:5000)
  -> host / VM network: Lima forwards Mac port 5000 into the VM
  -> OS firewall: ufw on the VM allows 5000/tcp (default policy denies everything else incoming)
  -> Linux server: Ubuntu VM, systemd unit cloudnotes.service
  -> gunicorn listening on 0.0.0.0:5000 (all interfaces, not just 127.0.0.1)
  -> Flask app -> PostgreSQL on localhost:5432
```

In my own words: the browser only knows `localhost:5000` on the Mac. Lima
listens there and tunnels the connection into the VM, so the hypervisor plays
the part of the network. Inside the VM, the packet still has to get past the OS
firewall. ufw denies incoming traffic by default and has an explicit allow for
5000/tcp. It then reaches gunicorn, which accepts connections on any interface
because it is bound to `0.0.0.0`. If it were bound to `127.0.0.1`, anything
arriving on the VM's network interface (`eth0`, `192.168.5.15`) would be
refused even with the firewall open. Gunicorn hands the request to Flask,
Flask reads and writes PostgreSQL, and the response goes back the same way.

> Note: Lima's port forward delivers traffic to the guest's own loopback, so on
> this particular hypervisor ufw is defence in depth rather than the gate. With a
> bridged adapter (VirtualBox/UTM) or on Compute Engine, outside traffic arrives
> on `eth0` and must pass the ufw rule (and, on GCP, the VPC firewall rule).

Debugging order when the page won't load: run `curl localhost:5000/healthz` on
the VM. If that fails, the problem is the app or the service (`journalctl -u
cloudnotes`). If it works on the VM but not from outside, check the bind
address (`ss -ltnp | grep 5000` must show `0.0.0.0:5000`), then the firewall
(`ufw status`), then the hypervisor's forward or the cloud firewall rule.

## Evidence

| What | File |
|---|---|
| `systemctl status` (active, enabled), `ss` showing `0.0.0.0:5000`, `ufw status`, curl from the Mac | [`01-service-and-access.txt`](docs/evidence/01-service-and-access.txt) |
| `kill -9` of the gunicorn master → systemd restarts it (`NRestarts=1`, new PID, still serving) | [`02-crash-restart.txt`](docs/evidence/02-crash-restart.txt) |
| Note created → `systemctl restart` → VM stopped and started (new boot time) → service came back by itself → note still there, also queried straight from PostgreSQL | [`03-persistence-and-reboot.txt`](docs/evidence/03-persistence-and-reboot.txt) |
| Notes page in the browser, served from the VM | [`04-browser-notes-page.jpg`](docs/evidence/04-browser-notes-page.jpg) |
| Setup script run | [`setup-run.log`](docs/evidence/setup-run.log) |

### Reproduce the checks

```bash
# crash -> auto-restart
limactl shell cloudnotes sudo kill -9 "$(limactl shell cloudnotes systemctl show -p MainPID --value cloudnotes)"
sleep 3; limactl shell cloudnotes systemctl show -p NRestarts -p MainPID cloudnotes

# persistence across app restart and VM reboot
curl -X POST -F title="Persistence test" -F body="hello" http://localhost:5000/api/notes
limactl shell cloudnotes sudo systemctl restart cloudnotes && curl http://localhost:5000/api/notes
limactl stop cloudnotes && limactl start cloudnotes && curl http://localhost:5000/api/notes
```

See [`cloud-mapping.md`](cloud-mapping.md) for how each piece maps to Compute Engine.

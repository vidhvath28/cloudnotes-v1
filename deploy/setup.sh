#!/usr/bin/env bash
# Provision CloudNotes on a fresh Ubuntu server (VirtualBox/UTM/WSL2/Lima VM or a
# Compute Engine VM). Run as root:  sudo bash deploy/setup.sh [path-to-source]
# With no argument it clones the repo from GitHub. Safe to re-run.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vidhvath28/cloudnotes-v1.git}"
BRANCH="${BRANCH:-feature/linux-deploy}"
APP_USER=cloudnotes
APP_DIR=/home/$APP_USER/cloudnotes
SRC="${1:-}"

echo "==> 1/7 Installing system packages"
apt-get -o DPkg::Lock::Timeout=600 update -y
DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y python3 python3-venv python3-pip \
  postgresql postgresql-contrib ufw git curl rsync

echo "==> 2/7 Creating service user '$APP_USER'"
id "$APP_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$APP_USER"

echo "==> 3/7 Getting the code into $APP_DIR"
if [[ -n "$SRC" ]]; then
  mkdir -p "$APP_DIR"
  rsync -a --delete --exclude .git --exclude venv --exclude .env --exclude 'uploads/*' "$SRC"/ "$APP_DIR"/
elif [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" pull --ff-only
else
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi
mkdir -p "$APP_DIR/uploads"
chown -R "$APP_USER:$APP_USER" "/home/$APP_USER"

echo "==> 4/7 Installing Python dependencies into a venv"
sudo -u "$APP_USER" python3 -m venv "$APP_DIR/venv"
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

echo "==> 5/7 Configuring PostgreSQL and .env"
systemctl enable --now postgresql
if [[ ! -f "$APP_DIR/.env" ]]; then
  DB_PASSWORD="$(openssl rand -hex 16)"
  SECRET_KEY="$(openssl rand -hex 32)"
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='cloudnotes'" | grep -q 1; then
    sudo -u postgres psql -c "ALTER ROLE cloudnotes WITH LOGIN PASSWORD '$DB_PASSWORD'"
  else
    sudo -u postgres psql -c "CREATE ROLE cloudnotes WITH LOGIN PASSWORD '$DB_PASSWORD'"
  fi
  sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='cloudnotes'" | grep -q 1 \
    || sudo -u postgres createdb --owner=cloudnotes cloudnotes
  cat > "$APP_DIR/.env" <<ENV
SECRET_KEY=$SECRET_KEY
DATABASE_URL=postgresql://cloudnotes:$DB_PASSWORD@localhost:5432/cloudnotes
UPLOAD_FOLDER=$APP_DIR/uploads
ENV
  chown "$APP_USER:$APP_USER" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
fi
sudo -u "$APP_USER" bash -c "cd '$APP_DIR' && venv/bin/python migrate.py"

echo "==> 6/7 Installing and starting the systemd service"
install -m 644 "$APP_DIR/deploy/cloudnotes.service" /etc/systemd/system/cloudnotes.service
systemctl daemon-reload
systemctl enable cloudnotes
systemctl restart cloudnotes

echo "==> 7/7 Opening the firewall"
ufw allow OpenSSH
ufw allow 5000/tcp
ufw --force enable
ufw status verbose

sleep 2
systemctl --no-pager status cloudnotes | head -12
curl -fsS http://localhost:5000/healthz && echo
echo "CloudNotes is up on port 5000."

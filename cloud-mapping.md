# CloudNotes: local deployment → Compute Engine mapping

I deployed CloudNotes on an Ubuntu 26.04 LTS VM running on my Mac (created with
[Lima](https://lima-vm.io), the same kind of local VM as UTM/VirtualBox). Every
piece of that deployment has a direct Compute Engine equivalent. The app,
`deploy/setup.sh` and `deploy/cloudnotes.service` would run on a Compute Engine
Ubuntu VM unchanged.

| What I built locally | Compute Engine equivalent | Why they play the same role |
|---|---|---|
| Ubuntu 26.04 LTS VM on my Mac (Lima, `limactl start cloudnotes`) | Compute Engine VM (`e2-medium`, Ubuntu 26.04 LTS image) | Both are a dedicated Linux machine with its own kernel, systemd, disk and network whose only job is running CloudNotes. Only who owns the hypervisor changes. |
| My terminal / shell (`limactl shell cloudnotes`) | `gcloud compute ssh cloudnotes-vm` | Both give me an SSH shell on the server to install packages, run `systemctl` and read logs; `gcloud` just handles the SSH keys for me. |
| `localhost:5000` on my Mac (Lima forwards host port 5000 to the VM's port 5000) | VM static external IP (`gcloud compute addresses create`), e.g. `http://<static-ip>:5000` | Both are the stable address a browser uses to reach the VM. Locally the hypervisor's port forward plays that part; in GCP a reserved static IP is attached to the VM's network interface. |
| OS firewall: `ufw allow 5000/tcp` (plus `OpenSSH`) | GCP VPC firewall rule: `allow tcp:5000` from `0.0.0.0/0` to instances tagged `cloudnotes` | Both are the gate that decides whether a packet to port 5000 may reach the VM. In GCP the VPC rule sits outside the VM; `ufw` can stay on inside it as a second layer. |
| systemd unit `deploy/cloudnotes.service` (`Restart=always`, `WantedBy=multi-user.target`) | systemd on the VM (identical file) | Compute Engine Ubuntu images run the same systemd, so the same unit starts CloudNotes on boot and restarts it on crash. Nothing to translate. |
| PostgreSQL installed on the VM (`apt install postgresql`) | Cloud SQL for PostgreSQL (managed, LU 2.7) | Both hold the notes outside the app process, so the app can restart, scale or be replaced without losing data. Cloud SQL adds managed backups, patching, HA and lets the VM be disposable. |
| `/home/cloudnotes/cloudnotes/.env` (mode 600, read via `EnvironmentFile=`), template in `.env.example` | Instance metadata for non-secret config; Secret Manager for `SECRET_KEY` and the DB password | Both keep configuration and secrets out of the code and the repo, and inject them into the process at start-up. Secret Manager adds IAM access control, versioning and audit logs. |

## Request path, local vs. cloud

```
Local:  browser → localhost:5000 on Mac → Lima port forward → ufw (5000/tcp) → Ubuntu VM → gunicorn on 0.0.0.0:5000 → Flask → PostgreSQL (localhost:5432)
GCP:    browser → static external IP:5000 → VPC firewall rule (tcp:5000) → [ufw] → Compute Engine VM → gunicorn on 0.0.0.0:5000 → Flask → Cloud SQL (private IP)
```

## What the same deployment would look like on Compute Engine

```bash
gcloud compute addresses create cloudnotes-ip --region=asia-south1
gcloud compute instances create cloudnotes-vm \
  --zone=asia-south1-a --machine-type=e2-medium \
  --image-family=ubuntu-2604-lts-amd64 --image-project=ubuntu-os-cloud \
  --address=cloudnotes-ip --tags=cloudnotes
gcloud compute firewall-rules create allow-cloudnotes-5000 \
  --network=default --direction=INGRESS --action=ALLOW \
  --rules=tcp:5000 --source-ranges=0.0.0.0/0 --target-tags=cloudnotes
gcloud compute ssh cloudnotes-vm --zone=asia-south1-a \
  --command='git clone -b feature/linux-deploy https://github.com/vidhvath28/cloudnotes-v1.git && sudo bash cloudnotes-v1/deploy/setup.sh'
```

(I did not run these: the deployment I verified is the local VM, and these
commands show how it maps.)

Once Cloud SQL arrives in LU 2.7, only `DATABASE_URL` changes: it points at the
Cloud SQL instance instead of `localhost`, and the PostgreSQL install step in
`setup.sh` is dropped.

# Homelab External - Setup Anleitung

Selbst-gehostete Infrastruktur auf Hetzner Cloud (~5 EUR/Monat).

## Services

| Dienst | URL | Funktion |
|--------|-----|----------|
| Headscale | `headscale.homelab-external.robinwerner.net` | VPN Coordination Server |
| Headplane | `headscale.../admin` | VPN Web-UI |
| Uptime Kuma | `uptime.homelab-external.robinwerner.net` | Uptime Monitoring |
| ntfy | `ntfy.homelab-external.robinwerner.net` | Push Notifications |
| Healthchecks | `hc.homelab-external.robinwerner.net` | Cronjob Monitoring |
| Traefik | `traefik.homelab-external.robinwerner.net` | Reverse Proxy Dashboard |

---

## Voraussetzungen

### Tools installieren

```bash
# macOS
brew install hcloud jq openssl

# Ubuntu/Debian
apt install hcloud-cli jq openssl
```

### API Tokens besorgen

1. **Hetzner Cloud API Token** (Read & Write):
   `https://console.hetzner.cloud` → Projekt → Security → API Tokens

2. **Cloudflare API Token** (Zone DNS Edit):
   `https://dash.cloudflare.com/profile/api-tokens` → Create Custom Token

3. **Cloudflare Zone ID**:
   `https://dash.cloudflare.com` → robinwerner.net → Rechte Sidebar → Zone ID

### SSH Key

```bash
# Falls kein Key existiert:
ssh-keygen -t ed25519 -C "homelab-external"
```

---

## Deployment

### 1. Tokens setzen

```bash
export HCLOUD_TOKEN="hc_xxx..."
export CLOUDFLARE_API_TOKEN="xxx..."
export CLOUDFLARE_ZONE_ID="xxx..."
```

### 2. Bootstrap ausführen

```bash
./bootstrap.sh
```

Das Script macht automatisch:
- SSH Key zu Hetzner hochladen
- Firewall erstellen (SSH, HTTP, HTTPS, DERP)
- Server mit Cloud-Init erstellen (Docker, UFW, fail2ban)
- 5 DNS A-Records bei Cloudflare anlegen
- Auf SSH + Cloud-Init warten
- Repo klonen (HTTPS, public)
- `.env` generieren (Passwörter, Traefik Auth)
- `docker compose up -d`
- Headscale User + API Key erstellen

Dauer: ca. 3-5 Minuten.

### 3. Manuelle Schritte (nach bootstrap.sh)

Die SSH-Verbindung und das Traefik-Dashboard-Passwort werden am Ende von `bootstrap.sh` ausgegeben.

```bash
# ntfy Admin-User erstellen
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> 'docker exec -it ntfy ntfy user add --role=admin admin'

# Healthchecks Superuser erstellen
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> 'docker exec healthchecks ./manage.py createsuperuser --noinput --email admin@example.com'
# Danach Passwort über die Web-Oberfläche zurücksetzen (Forgot Password)
# oder via Django Shell:
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP> 'docker exec healthchecks ./manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.first()
u.set_password(\"DEIN_PASSWORT\")
u.save()
"'
```

---

## Teardown

```bash
./teardown.sh
```

Löscht: Server, Firewall, SSH Key, alle DNS Records. Fragt vorher "yes" als Bestätigung.

---

## Verwaltung

### SSH zum Server

```bash
ssh -i ~/.ssh/id_ed25519 root@<SERVER_IP>
```

### Docker Compose

```bash
cd /opt/homelab-repo/hetzner
docker compose ps              # Status
docker compose logs -f <svc>   # Logs
docker compose pull && docker compose up -d  # Update
```

### Auto-Update

Der Server prüft automatisch jeden Dienstag um 12:00 UTC ob neue Commits auf `main` vorliegen (z.B. von Renovate). Bei Änderungen wird `git pull && docker compose pull && docker compose up -d` ausgeführt.

Log: `/var/log/homelab-update.log`

Manuell auslösen:
```bash
bash /opt/homelab-repo/hetzner/scripts/auto-update.sh
```

### Headscale

```bash
docker exec headscale headscale users list
docker exec headscale headscale nodes list
docker exec headscale headscale preauthkeys create --user homelab --expiration 24h
```

### Ersten VPN-Client verbinden

```bash
# Pre-Auth Key erstellen (auf dem Server)
docker exec headscale headscale preauthkeys create --user homelab --expiration 24h

# Tailscale Client verbinden (auf dem Client)
tailscale up --login-server=https://headscale.homelab-external.robinwerner.net --authkey=<KEY>
```

### Subnet Router (NUC) verbinden

```bash
sudo tailscale up \
  --login-server=https://headscale.homelab-external.robinwerner.net \
  --authkey=<KEY> \
  --advertise-routes=10.0.0.0/24 \
  --accept-dns=false

# Route freigeben (auf Hetzner Server)
docker exec headscale headscale routes list
docker exec headscale headscale routes enable -r <ID>
```

---

## Troubleshooting

### Container starten nicht

```bash
cd /opt/homelab-repo/hetzner
docker compose logs -f
```

### SSL-Zertifikate fehlen

```bash
docker logs traefik
# acme.json muss 600 sein:
chmod 600 /opt/homelab-data/traefik/certs/acme.json
```

### Headscale Health Check schlägt fehl

```bash
docker exec headscale headscale health
docker compose logs headscale
```

---

## Kosten

| Posten | Kosten/Monat |
|--------|--------------|
| Hetzner CX23 (Falkenstein) | ~5 EUR |
| **Gesamt** | **~5 EUR** |

# Homelab External - Setup Anleitung

Diese Anleitung führt dich durch das komplette Setup der externen Homelab-Infrastruktur auf Hetzner.

## Übersicht

Nach dem Setup hast du:

| Dienst | URL | Funktion |
|--------|-----|----------|
| Headscale | headscale.homelab.robinwerner.net | VPN Coordination Server |
| Headplane | vpn.homelab.robinwerner.net | VPN Web-UI |
| Uptime Kuma | uptime.homelab.robinwerner.net | Uptime Monitoring |
| ntfy | ntfy.homelab.robinwerner.net | Push Notifications |
| Healthchecks | hc.homelab.robinwerner.net | Cronjob Monitoring |

---

## Phase 1: Vorbereitungen (10 Min)

### 1.1 Hetzner Cloud API Token

```
1. https://console.hetzner.cloud
2. Projekt auswählen (oder neues erstellen)
3. Security → API Tokens → Generate API Token
4. Name: "homelab-terraform"
5. Permissions: Read & Write
6. Token kopieren und sicher speichern
```

### 1.2 Hetzner Object Storage

```
1. Hetzner Cloud Console → Object Storage
2. Create Bucket:
   - Name: homelab-external-terraform-state
   - Location: Falkenstein (fsn1)
3. Security → S3 Credentials → Generate Credentials
4. Access Key und Secret Key speichern
```

### 1.3 Cloudflare API Token

```
1. https://dash.cloudflare.com/profile/api-tokens
2. Create Token → Create Custom Token
3. Name: "Homelab Terraform"
4. Permissions:
   - Zone → DNS → Edit
   - Zone → Zone → Read
5. Zone Resources: Include → Specific zone → robinwerner.net
6. Token erstellen und kopieren
```

### 1.4 Cloudflare Zone ID

```
1. https://dash.cloudflare.com
2. robinwerner.net auswählen
3. Rechte Sidebar → API → Zone ID kopieren
```

### 1.5 SSH Key vorbereiten

```bash
# Falls noch kein Key existiert:
ssh-keygen -t ed25519 -C "homelab-external"

# Public Key anzeigen (für GitHub Secret):
cat ~/.ssh/id_ed25519.pub
```

---

## Phase 2: GitHub Secrets konfigurieren (5 Min)

Gehe zu: **Repository → Settings → Secrets and variables → Actions**

Erstelle diese Secrets:

| Secret Name | Wert | Beschreibung |
|-------------|------|--------------|
| `HETZNER_TOKEN` | `hc_xxx...` | Hetzner Cloud API Token |
| `CLOUDFLARE_API_TOKEN` | `xxx...` | Cloudflare API Token |
| `CLOUDFLARE_ZONE_ID` | `xxx...` | Zone ID für robinwerner.net |
| `HETZNER_S3_ACCESS_KEY` | `xxx...` | Object Storage Access Key |
| `HETZNER_S3_SECRET_KEY` | `xxx...` | Object Storage Secret Key |
| `REPO_SSH_URL` | `git@github.com:USER/homelab-external.git` | SSH URL dieses Repos |
| `SSH_PUBLIC_KEY` | `ssh-ed25519 AAAA...` | Dein SSH Public Key (Inhalt!) |

---

## Phase 3: GitHub Environments einrichten (2 Min)

Gehe zu: **Repository → Settings → Environments**

### Environment: `production`
- Required reviewers: Optional
- Deployment branches: `main`

### Environment: `destroy-production`
- Required reviewers: **Aktivieren** (Sicherheit!)
- Deployment branches: `main`

---

## Phase 4: Erstes Deployment (15 Min)

### 4.1 Änderungen pushen

```bash
git add -A
git commit -m "Setup Terraform Infrastructure"
git push
```

### 4.2 Workflow manuell starten

```
1. Repository → Actions → Terraform
2. Run workflow → Branch: main → Action: apply
3. Warten bis "plan" Job durch ist
4. "apply" Job genehmigen (wenn Environment-Protection aktiv)
```

### 4.3 Deploy Key hinzufügen

Nach erfolgreichem Apply siehst du in der **Job Summary** den **Deploy Key**.

```
1. Den Public Key aus der Job Summary kopieren
2. Repository → Settings → Deploy keys → Add deploy key
3. Title: "Homelab Server"
4. Key: (eingefügter Key)
5. Allow write access: NEIN
6. Add key
```

### 4.4 Cloud-Init abwarten

Der Server klont jetzt das Repo. Das dauert ca. 3-5 Minuten.

```bash
# SSH zum Server (IP aus Job Summary)
ssh root@<SERVER_IP>

# Cloud-Init Status prüfen
tail -f /var/log/cloud-init-output.log

# Warten auf: "Cloud-init completed successfully"
```

---

## Phase 5: Headscale konfigurieren (10 Min)

### 5.1 Namespace erstellen

```bash
ssh root@<SERVER_IP>
docker exec headscale headscale namespaces create homelab
```

### 5.2 API Key generieren

```bash
docker exec headscale headscale apikeys create --expiration 365d
# OUTPUT NOTIEREN! z.B.: hskey-1234567890...
```

### 5.3 API Key eintragen

```bash
nano /opt/homelab/.env

# HEADSCALE_API_KEY=hskey-DEIN_KEY_HIER
```

### 5.4 Container neu starten

```bash
cd /opt/homelab
docker compose down
docker compose up -d
```

### 5.5 Testen

- Headscale: https://headscale.homelab.robinwerner.net
- Headplane: https://vpn.homelab.robinwerner.net (Login mit API Key)

---

## Phase 6: Erste Clients verbinden

### 6.1 Pre-Auth Key erstellen

```bash
docker exec headscale headscale preauthkeys create \
  --namespace homelab \
  --expiration 24h \
  --reusable
```

### 6.2 NUC verbinden (Subnet Router)

Auf dem NUC:

```bash
# Tailscale installieren
curl -fsSL https://tailscale.com/install.sh | sh

# Mit Headscale verbinden
sudo tailscale up \
  --login-server=https://headscale.homelab.robinwerner.net \
  --authkey=hskey-auth-DEIN_KEY \
  --advertise-routes=10.0.0.0/24 \
  --accept-dns=false

# IP Forwarding aktivieren
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 6.3 Route freigeben

```bash
# Auf Hetzner Server
docker exec headscale headscale routes list
docker exec headscale headscale routes enable -r 1
```

---

## Troubleshooting

### Container starten nicht

```bash
cd /opt/homelab
docker compose logs -f
```

### Git Clone fehlgeschlagen

```bash
# Deploy Key prüfen
cat /root/.ssh/deploy_key
ssh -T git@github.com

# Manuell klonen
git clone git@github.com:USERNAME/homelab-external.git /opt/homelab-repo
cp -r /opt/homelab-repo/hetzner/* /opt/homelab/
```

### SSL-Zertifikate fehlen

```bash
# Traefik Logs prüfen
docker logs traefik

# acme.json Permissions
chmod 600 /opt/homelab/traefik/certs/acme.json
```

---

## Kosten

| Posten | Kosten/Monat |
|--------|--------------|
| Hetzner CX22 (Falkenstein) | ~5€ |
| Hetzner Object Storage | ~0.50€ |
| **Gesamt** | **~5.50€** |

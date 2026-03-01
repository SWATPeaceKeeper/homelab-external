# Repo Cleanup, Security Hardening & Renovate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure repo, harden all services, pin images, add Renovate auto-updates with cron-based deploy.

**Architecture:** 4 phases — repo restructure, security hardening (Docker/Traefik/SSH/ACL), image pinning + Renovate config, docs update. Each phase is one commit.

**Tech Stack:** Docker Compose, Traefik v3, Headscale, cloud-init, Bash, Renovate

**Design doc:** `docs/plans/2026-03-01-repo-cleanup-security-renovate-design.md`

---

### Task 1: Repo Restructuring

**Files:**
- Move: `README.md` → `docs/README.md`
- Move: `SETUP.md` → `docs/SETUP.md`
- Delete: `MONITORING_KONZEPT_V2.md`
- Delete: `VPN_KONZEPT_HEADSCALE_V1.md`
- Create: `README.md` (new short version)
- Modify: `.gitignore`
- Modify: `docs/README.md:50` (fix SETUP.md link)

**Step 1: Move docs and delete concept files**

```bash
cd /home/robin/repos/homelab-external
git mv README.md docs/README.md
git mv SETUP.md docs/SETUP.md
git rm MONITORING_KONZEPT_V2.md
git rm VPN_KONZEPT_HEADSCALE_V1.md
```

**Step 2: Fix SETUP.md link in docs/README.md**

In `docs/README.md:50`, change:
```
Detaillierte Anleitung: [SETUP.md](SETUP.md)
```
to:
```
Detaillierte Anleitung: [SETUP.md](./SETUP.md)
```

(Already relative, but verify it still works after the move.)

**Step 3: Create new root README.md**

```markdown
# Homelab External

Selbst-gehostete Infrastruktur auf einem Hetzner vServer (~5 EUR/Monat).

VPN (Headscale), Monitoring (Uptime Kuma, Healthchecks), Push-Notifications (ntfy) —
provisioniert mit einem einzigen Shell Script.

## Quick Start

```bash
export HCLOUD_TOKEN="..." CLOUDFLARE_API_TOKEN="..." CLOUDFLARE_ZONE_ID="..."
./bootstrap.sh    # Erstellt alles (~3-5 Min)
./teardown.sh     # Löscht alles
```

## Dokumentation

- [Ausführliche Übersicht](docs/README.md)
- [Setup-Anleitung](docs/SETUP.md)
```

**Step 4: Extend .gitignore**

Add after line 2 (`hetzner/.env`):
```
*.env
.env.*
!hetzner/.env.example
```

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: Move docs to docs/, remove concept files, short root README"
```

---

### Task 2: Docker Compose — Container Hardening

**Files:**
- Modify: `hetzner/docker-compose.yml`

**Step 1: Add security_opt and cap_drop to headscale-postgres (line 69)**

After `restart: unless-stopped` (line 69), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 2: Add security_opt, cap_drop to headscale (line 99)**

After `restart: unless-stopped` (line 99), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 3: Add security_opt, cap_drop to headplane (line 156)**

After `restart: unless-stopped` (line 156), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 4: Add security_opt, cap_drop to tailscale (line 203)**

After `restart: unless-stopped` (line 203), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

Keep existing `cap_add: [NET_ADMIN, SYS_MODULE]` — `cap_drop: ALL` + explicit
`cap_add` is the correct pattern.

**Step 5: Add security_opt, cap_drop to uptime-kuma (line 226)**

After `restart: unless-stopped` (line 226), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 6: Add security_opt, cap_drop to ntfy (line 251)**

After `restart: unless-stopped` (line 251), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 7: Add security_opt, cap_drop to healthchecks (line 290)**

After `restart: unless-stopped` (line 290), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 8: Add security_opt, cap_drop to healthchecks-postgres (line 327)**

After `restart: unless-stopped` (line 327), add:
```yaml
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

**Step 9: Add :ro to headscale config mounts (line 109-111)**

Change:
```yaml
      - ./headscale/config.yaml:/etc/headscale/config.yaml
      - ./headscale/acl.json:/etc/headscale/acl.json
      - ./headscale/dns_records.json:/etc/headscale/dns_records.json
```
to:
```yaml
      - ./headscale/config.yaml:/etc/headscale/config.yaml:ro
      - ./headscale/acl.json:/etc/headscale/acl.json:ro
      - ./headscale/dns_records.json:/etc/headscale/dns_records.json:ro
```

**Step 10: Add :ro to headplane config mounts (lines 158-162)**

Change:
```yaml
      - ./headplane/config.yaml:/etc/headplane/config.yaml
      ...
      - ./headscale/config.yaml:/etc/headscale/config.yaml
      - ./headscale/dns_records.json:/etc/headscale/dns_records.json
      - ./headscale/acl.json:/etc/headscale/acl.json
```
to:
```yaml
      - ./headplane/config.yaml:/etc/headplane/config.yaml:ro
      ...
      - ./headscale/config.yaml:/etc/headscale/config.yaml:ro
      - ./headscale/dns_records.json:/etc/headscale/dns_records.json:ro
      - ./headscale/acl.json:/etc/headscale/acl.json:ro
```

**Step 11: Verify compose config is valid**

```bash
cd /home/robin/repos/homelab-external/hetzner
docker compose config --quiet
```
Expected: No output (valid config). Note: will warn about missing .env — that's OK.

**Step 12: Commit**

```bash
git add hetzner/docker-compose.yml
git commit -m "security: Add no-new-privileges, cap_drop ALL, read-only config mounts"
```

---

### Task 3: Traefik Hardening

**Files:**
- Modify: `hetzner/traefik/traefik.yml`
- Modify: `hetzner/docker-compose.yml` (labels)

**Step 1: Add TLS options to traefik.yml**

After the `certificatesResolvers` section (after line 52), add:

```yaml

# -----------------------------------------------------------------------------
# TLS HARDENING
# -----------------------------------------------------------------------------
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      sniStrict: true
```

**Step 2: Add security-headers and rate-limit middlewares via docker-compose labels**

Security headers and rate-limit are defined as Traefik middlewares in the
docker-compose labels on the Traefik service. Add after the `auth` middleware
definition (line 58):

```yaml
      # Security Headers (global middleware)
      - "traefik.http.middlewares.security-headers.headers.stsSeconds=31536000"
      - "traefik.http.middlewares.security-headers.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.security-headers.headers.stsPreload=true"
      - "traefik.http.middlewares.security-headers.headers.frameDeny=true"
      - "traefik.http.middlewares.security-headers.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.security-headers.headers.referrerPolicy=strict-origin-when-cross-origin"
      - "traefik.http.middlewares.security-headers.headers.permissionsPolicy=camera=(), microphone=(), geolocation=()"
      # Rate Limiting
      - "traefik.http.middlewares.rate-limit.ratelimit.average=50"
      - "traefik.http.middlewares.rate-limit.ratelimit.burst=100"
```

**Step 3: Add security-headers + rate-limit to Traefik dashboard router**

Change line 57:
```yaml
      - "traefik.http.routers.dashboard.middlewares=auth"
```
to:
```yaml
      - "traefik.http.routers.dashboard.middlewares=auth,security-headers,rate-limit"
```

**Step 4: Add security-headers to all other routers**

For each service router, append `security-headers` middleware:

Headscale (line 126): change `middlewares=cors` to `middlewares=cors,security-headers`

Headplane (line 183): add new label:
```yaml
      - "traefik.http.routers.headplane.middlewares=security-headers,rate-limit"
```

Uptime Kuma: add after certresolver label (line 235):
```yaml
      - "traefik.http.routers.uptime.middlewares=security-headers"
```

ntfy: add after certresolver label (line 278):
```yaml
      - "traefik.http.routers.ntfy.middlewares=security-headers"
```

Healthchecks: add after certresolver label (line 321):
```yaml
      - "traefik.http.routers.healthchecks.middlewares=security-headers"
```

**Step 5: Restrict CORS allowheaders**

Change line 127:
```yaml
      - 'traefik.http.middlewares.cors.headers.accesscontrolallowheaders=*'
```
to:
```yaml
      - 'traefik.http.middlewares.cors.headers.accesscontrolallowheaders=Content-Type,Authorization'
```

**Step 6: Verify compose config**

```bash
cd /home/robin/repos/homelab-external/hetzner
docker compose config --quiet
```

**Step 7: Commit**

```bash
git add hetzner/traefik/traefik.yml hetzner/docker-compose.yml
git commit -m "security: Add TLS hardening, security headers, rate limiting, restrict CORS"
```

---

### Task 4: SSH Hardening & ACL Fix

**Files:**
- Modify: `cloud-init.yaml`
- Modify: `hetzner/headscale/acl.json`

**Step 1: Add SSH hardening to cloud-init.yaml**

Add a `write_files` section BEFORE the `runcmd` section (before line 30).
Insert after line 9 (after the header comment block):

```yaml

# -----------------------------------------------------------------------------
# SSH HARDENING
# -----------------------------------------------------------------------------
write_files:
  - path: /etc/ssh/sshd_config.d/hardening.conf
    content: |
      PermitRootLogin prohibit-password
      MaxAuthTries 3
      LoginGraceTime 20
      AllowAgentForwarding no
      AllowTcpForwarding no
      X11Forwarding no
    owner: root:root
    permissions: "0644"
```

Also add to `runcmd` section (after fail2ban start, after line 61):
```yaml
  - systemctl restart sshd
```

**Step 2: Remove SSH port from ACL server group**

In `hetzner/headscale/acl.json`, change the server group dst (lines 44-53):

From:
```json
      "dst": [
        "homelab-network:22",
        "homelab-network:80",
        "homelab-network:443",
        "homelab-network:3000",
        "homelab-network:8080",
        "homelab-network:8123",
        "homelab-network:9090",
        "homelab-network:9100"
      ]
```

To:
```json
      "dst": [
        "homelab-network:80",
        "homelab-network:443",
        "homelab-network:3000",
        "homelab-network:8080",
        "homelab-network:8123",
        "homelab-network:9090",
        "homelab-network:9100"
      ]
```

**Step 3: Commit**

```bash
git add cloud-init.yaml hetzner/headscale/acl.json
git commit -m "security: SSH hardening, remove server SSH access to home network"
```

---

### Task 5: Remove Secrets from Logs

**Files:**
- Modify: `bootstrap.sh`
- Modify: `hetzner/scripts/headscale-setup.sh`

**Step 1: Remove plaintext password from bootstrap.sh output**

Change lines 299-301:
```bash
echo "  Traefik Dashboard (Basic Auth):"
echo "    User:     admin"
echo "    Passwort: ${TRAEFIK_PASSWORD}"
```
to:
```bash
echo "  Traefik Dashboard (Basic Auth):"
echo "    User:     admin"
echo "    Passwort: siehe /opt/homelab-repo/hetzner/.env (TRAEFIK_DASHBOARD_AUTH)"
```

**Step 2: Remove API key logging from headscale-setup.sh**

Change lines 76-78:
```bash
echo ""
echo "=== Headscale Setup abgeschlossen ==="
echo "User:    ${USER}"
echo "API Key: $(grep '^HEADSCALE_API_KEY=' "$ENV_FILE" | cut -d= -f2)"
```
to:
```bash
echo ""
echo "=== Headscale Setup abgeschlossen ==="
echo "User:    ${USER}"
echo "API Key: gesetzt in ${ENV_FILE}"
```

**Step 3: Verify scripts with shellcheck**

```bash
shellcheck bootstrap.sh hetzner/scripts/headscale-setup.sh
```

**Step 4: Commit**

```bash
git add bootstrap.sh hetzner/scripts/headscale-setup.sh
git commit -m "security: Remove plaintext secrets from script output"
```

---

### Task 6: DNS Fallback & Headscale Healthcheck

**Files:**
- Modify: `hetzner/headscale/config.yaml`

**Step 1: Add DNS fallback nameserver**

Change lines 72-74:
```yaml
  nameservers:
    global:
      - 1.1.1.1
```
to:
```yaml
  nameservers:
    global:
      - 1.1.1.1
      - 9.9.9.9
```

**Step 2: Commit**

```bash
git add hetzner/headscale/config.yaml
git commit -m "fix: Add Quad9 as DNS fallback nameserver"
```

---

### Task 7: Image Pinning & Healthchecks

**Files:**
- Modify: `hetzner/docker-compose.yml`

**Step 1: Pin all images to specific versions**

Replace these image tags:

| Line | Old | New |
|------|-----|-----|
| 27 | `traefik:v3.6` | `traefik:v3.6.9` |
| 67 | `postgres:17-alpine` | `postgres:17.9-alpine` |
| 97 | `ghcr.io/juanfont/headscale:stable` | `ghcr.io/juanfont/headscale:v0.28.0` |
| 154 | `ghcr.io/tale/headplane:0.6.2-beta.5` | `ghcr.io/tale/headplane:v0.6.2` |
| 200 | `ghcr.io/tailscale/tailscale:stable` | `ghcr.io/tailscale/tailscale:v1.94.2` |
| 224 | `louislam/uptime-kuma:2` | `louislam/uptime-kuma:2.1.3` |
| 249 | `binwiederhier/ntfy:latest` | `binwiederhier/ntfy:v2.17.0` |
| 288 | `healthchecks/healthchecks:latest` | `healthchecks/healthchecks:v4.0` |
| 325 | `postgres:17-alpine` | `postgres:17.9-alpine` |

**Step 2: Add explicit healthcheck parameters to headscale**

Change lines 116-117:
```yaml
    healthcheck:
        test: ["CMD", "headscale", "health"]
```
to:
```yaml
    healthcheck:
      test: ["CMD", "headscale", "health"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 15s
```

**Step 3: Add healthcheck to healthchecks service**

After the `depends_on` block (after line 316), add:
```yaml
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/api/v3/status/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
```

**Step 4: Add healthcheck to uptime-kuma**

After the volumes block (after line 228), add:
```yaml
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:3001/api/status-page/heartbeat || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s
```

**Step 5: Add healthcheck to tailscale**

After the network_mode line (after line 215), add:
```yaml
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

**Step 6: Verify compose config**

```bash
cd /home/robin/repos/homelab-external/hetzner
docker compose config --quiet
```

**Step 7: Commit**

```bash
git add hetzner/docker-compose.yml
git commit -m "feat: Pin all images to specific versions, add missing healthchecks"
```

---

### Task 8: Renovate Configuration

**Files:**
- Create: `renovate.json`

**Step 1: Create renovate.json**

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    "group:allNonMajor"
  ],
  "schedule": ["after 9am on Monday"],
  "labels": ["dependencies"],
  "packageRules": [
    {
      "description": "Automerge patch updates",
      "matchManagers": ["docker-compose"],
      "matchUpdateTypes": ["patch"],
      "automerge": true
    },
    {
      "description": "Pin postgres to major 17",
      "matchManagers": ["docker-compose"],
      "matchPackageNames": ["postgres"],
      "allowedVersions": "/^17\\./"
    }
  ]
}
```

**Step 2: Commit**

```bash
git add renovate.json
git commit -m "feat: Add Renovate config for Docker image auto-updates"
```

---

### Task 9: Auto-Update Cron Script

**Files:**
- Create: `hetzner/scripts/auto-update.sh`
- Modify: `cloud-init.yaml`

**Step 1: Create auto-update.sh**

```bash
#!/usr/bin/env bash
# ============================================================================
# Homelab External - Auto-Update Script
# ============================================================================
# Prüft ob neue Commits auf origin/main vorliegen und aktualisiert
# Docker Compose automatisch.
#
# Einrichtung: Cron-Job (Dienstag 12:00 UTC, nach Renovate am Montag)
# Log:         /var/log/homelab-update.log
# ============================================================================
set -euo pipefail

REPO_DIR="/opt/homelab-repo"
COMPOSE_DIR="${REPO_DIR}/hetzner"
LOG_FILE="/var/log/homelab-update.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "Starting auto-update"

cd "$REPO_DIR"
git fetch origin main

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
    log "Already up to date"
    exit 0
fi

log "Pulling changes: ${LOCAL:0:7} -> ${REMOTE:0:7}"
git pull origin main

cd "$COMPOSE_DIR"
docker compose pull
docker compose up -d --remove-orphans

log "Update complete"
```

**Step 2: Make executable**

```bash
chmod +x hetzner/scripts/auto-update.sh
```

**Step 3: Add cron job to cloud-init.yaml**

In the `write_files` section (added in Task 4), append:

```yaml
  - path: /etc/cron.d/homelab-update
    content: |
      # Auto-Update: Dienstag 12:00 UTC (nach Renovate am Montag)
      0 12 * * 2 root /opt/homelab-repo/hetzner/scripts/auto-update.sh
    owner: root:root
    permissions: "0644"
```

**Step 4: Verify with shellcheck**

```bash
shellcheck hetzner/scripts/auto-update.sh
```

**Step 5: Commit**

```bash
git add hetzner/scripts/auto-update.sh cloud-init.yaml
git commit -m "feat: Add cron-based auto-update for Docker Compose deployments"
```

---

### Task 10: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/README.md`
- Modify: `docs/SETUP.md`

**Step 1: Update CLAUDE.md**

Key changes:
- Update Services line: remove `Dockge`, update Headplane to `v0.6.2`
- Update "5 subdomains" (already done)
- Add mention of Renovate and auto-update cron
- Add security measures to Key Design Decisions
- Update Repo Structure section to reflect docs/ directory
- Add auto-update.sh to scripts section

**Step 2: Update docs/README.md**

- Update Repo-Struktur section to reflect new structure (docs/, renovate.json)
- Add note about Renovate auto-updates

**Step 3: Update docs/SETUP.md**

- Add note about auto-update cron job in Verwaltung section

**Step 4: Commit**

```bash
git add CLAUDE.md docs/README.md docs/SETUP.md
git commit -m "docs: Update documentation for security hardening, Renovate, new structure"
```

---

## Execution Order

Tasks 1-10 are sequential. Each task is one commit.

| Task | Description | Files |
|------|-------------|-------|
| 1 | Repo restructuring | README.md, SETUP.md, .gitignore, concept docs |
| 2 | Container hardening | docker-compose.yml |
| 3 | Traefik hardening | traefik.yml, docker-compose.yml |
| 4 | SSH + ACL hardening | cloud-init.yaml, acl.json |
| 5 | Secrets from logs | bootstrap.sh, headscale-setup.sh |
| 6 | DNS fallback | headscale/config.yaml |
| 7 | Image pinning + healthchecks | docker-compose.yml |
| 8 | Renovate config | renovate.json |
| 9 | Auto-update cron | auto-update.sh, cloud-init.yaml |
| 10 | Documentation update | CLAUDE.md, docs/README.md, docs/SETUP.md |

**Parallelization options for subagent execution:**
- Tasks 4, 5, 6 are independent (different files) — can run in parallel
- Tasks 8, 9 are independent — can run in parallel
- Tasks 2, 3, 7 all touch docker-compose.yml — must be sequential

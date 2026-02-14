#!/bin/bash
# ============================================================================
# Homelab External - Bootstrap Script
# ============================================================================
# Erstellt die komplette Infrastruktur auf Hetzner Cloud:
#   1. SSH Key hochladen
#   2. Firewall erstellen
#   3. Server mit Cloud-Init erstellen
#   4. DNS Records bei Cloudflare anlegen
#   5. Repo klonen, .env generieren, Docker Compose starten
#   6. Headscale bootstrappen
#
# Voraussetzungen:
#   - hcloud, curl, jq, openssl installiert
#   - HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID gesetzt
#
# Verwendung:
#   export HCLOUD_TOKEN=... CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ZONE_ID=...
#   ./bootstrap.sh
# ============================================================================
set -euo pipefail
trap 'error "Bootstrap fehlgeschlagen! Prüfe den Zustand oder führe ./teardown.sh aus."' ERR

# ---------------------------------------------------------------------------
# KONFIGURATION
# ---------------------------------------------------------------------------
SERVER_NAME="homelab-external"
SERVER_TYPE="cx23"
SERVER_LOCATION="fsn1"
SERVER_IMAGE="ubuntu-24.04"
DOMAIN="robinwerner.net"
SUBDOMAIN_PREFIX="homelab-external"
REPO_URL="https://github.com/SWATPeaceKeeper/homelab-external.git"
SSH_KEY_NAME="${SERVER_NAME}-key"
FIREWALL_NAME="${SERVER_NAME}-firewall"

# DNS Subdomains die angelegt werden
SUBDOMAINS=("headscale" "vpn" "uptime" "ntfy" "hc" "traefik" "dockge")

# ---------------------------------------------------------------------------
# HILFSFUNKTIONEN
# ---------------------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
die()   { error "$*"; exit 1; }

cf_api() {
  local method="$1" endpoint="$2"
  shift 2
  local response
  response=$(curl -s -X "$method" \
    "https://api.cloudflare.com/client/v4${endpoint}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@")

  if ! echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    local msg
    msg=$(echo "$response" | jq -r '.errors[0].message // "Unbekannter Fehler"' 2>/dev/null || echo "Ungültige API-Antwort")
    die "Cloudflare API Fehler: ${msg}"
  fi

  echo "$response"
}

# ---------------------------------------------------------------------------
# 1. VORAUSSETZUNGEN PRÜFEN
# ---------------------------------------------------------------------------
info "Prüfe Voraussetzungen..."

for cmd in hcloud curl jq openssl ssh; do
  command -v "$cmd" >/dev/null 2>&1 || die "'${cmd}' ist nicht installiert."
done

[ -z "${HCLOUD_TOKEN:-}" ] && die "HCLOUD_TOKEN ist nicht gesetzt."
[ -z "${CLOUDFLARE_API_TOKEN:-}" ] && die "CLOUDFLARE_API_TOKEN ist nicht gesetzt."
[ -z "${CLOUDFLARE_ZONE_ID:-}" ] && die "CLOUDFLARE_ZONE_ID ist nicht gesetzt."

ok "Alle Voraussetzungen erfüllt."

# ---------------------------------------------------------------------------
# 2. SSH KEY
# ---------------------------------------------------------------------------
info "SSH Key..."

# Lokalen SSH Key finden
SSH_PUBKEY_FILE=""
for f in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
  if [ -f "$f" ]; then
    SSH_PUBKEY_FILE="$f"
    break
  fi
done
[ -z "$SSH_PUBKEY_FILE" ] && die "Kein SSH Public Key gefunden (~/.ssh/id_ed25519.pub oder id_rsa.pub)."

SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")

# Key bei Hetzner hochladen (oder existierenden finden)
if hcloud ssh-key describe "$SSH_KEY_NAME" >/dev/null 2>&1; then
  ok "SSH Key '${SSH_KEY_NAME}' existiert bereits."
else
  hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key "$SSH_PUBKEY"
  ok "SSH Key '${SSH_KEY_NAME}' hochgeladen."
fi

# ---------------------------------------------------------------------------
# 3. FIREWALL
# ---------------------------------------------------------------------------
info "Firewall..."

if hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
  ok "Firewall '${FIREWALL_NAME}' existiert bereits."
else
  hcloud firewall create --name "$FIREWALL_NAME"

  # Regeln hinzufügen
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 22 --source-ips 0.0.0.0/0 --source-ips ::/0 --description "SSH"
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --source-ips ::/0 --description "HTTP"
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --source-ips ::/0 --description "HTTPS"
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol udp --port 3478 --source-ips 0.0.0.0/0 --source-ips ::/0 --description "DERP/STUN UDP"
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp --port 3478 --source-ips 0.0.0.0/0 --source-ips ::/0 --description "DERP/STUN TCP"

  ok "Firewall '${FIREWALL_NAME}' erstellt."
fi

# ---------------------------------------------------------------------------
# 4. SERVER ERSTELLEN
# ---------------------------------------------------------------------------
info "Server..."

if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  warn "Server '${SERVER_NAME}' existiert bereits."
  SERVER_IP=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')
else
  info "Erstelle Server '${SERVER_NAME}' (${SERVER_TYPE} in ${SERVER_LOCATION})..."

  hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --location "$SERVER_LOCATION" \
    --image "$SERVER_IMAGE" \
    --ssh-key "$SSH_KEY_NAME" \
    --firewall "$FIREWALL_NAME" \
    --user-data-from-file "$(dirname "$0")/cloud-init.yaml"

  SERVER_IP=$(hcloud server describe "$SERVER_NAME" -o json | jq -r '.public_net.ipv4.ip')
  ok "Server erstellt: ${SERVER_IP}"
fi

info "Server IP: ${SERVER_IP}"

# ---------------------------------------------------------------------------
# 5. DNS RECORDS (Cloudflare)
# ---------------------------------------------------------------------------
info "DNS Records..."

for sub in "${SUBDOMAINS[@]}"; do
  FQDN="${sub}.${SUBDOMAIN_PREFIX}.${DOMAIN}"

  # Prüfe ob Record existiert
  EXISTING=$(cf_api GET "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${FQDN}" | jq -r '.result | length')

  if [ "$EXISTING" -gt "0" ]; then
    # Record updaten
    RECORD_ID=$(cf_api GET "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${FQDN}" | jq -r '.result[0].id')
    cf_api PUT "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${RECORD_ID}" \
      -d "{\"type\":\"A\",\"name\":\"${sub}.${SUBDOMAIN_PREFIX}\",\"content\":\"${SERVER_IP}\",\"ttl\":300,\"proxied\":false}" >/dev/null
    ok "${FQDN} → ${SERVER_IP} (aktualisiert)"
  else
    cf_api POST "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
      -d "{\"type\":\"A\",\"name\":\"${sub}.${SUBDOMAIN_PREFIX}\",\"content\":\"${SERVER_IP}\",\"ttl\":300,\"proxied\":false}" >/dev/null
    ok "${FQDN} → ${SERVER_IP} (erstellt)"
  fi
done

# ---------------------------------------------------------------------------
# 6. WARTE AUF SSH
# ---------------------------------------------------------------------------
info "Warte auf SSH-Bereitschaft..."

for i in $(seq 1 60); do
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@${SERVER_IP}" true 2>/dev/null; then
    ok "SSH bereit."
    break
  fi
  if [ "$i" -eq 60 ]; then
    die "SSH nicht bereit nach 5 Minuten."
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# 7. WARTE AUF CLOUD-INIT
# ---------------------------------------------------------------------------
info "Warte auf Cloud-Init-Abschluss..."

for i in $(seq 1 60); do
  if ssh -o BatchMode=yes "root@${SERVER_IP}" "cloud-init status --wait" 2>/dev/null | grep -q "done"; then
    ok "Cloud-Init abgeschlossen."
    break
  fi
  if [ "$i" -eq 60 ]; then
    die "Cloud-Init nicht abgeschlossen nach 5 Minuten."
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# 8. REPO KLONEN
# ---------------------------------------------------------------------------
info "Klone Repository..."

ssh "root@${SERVER_IP}" "
  if [ -d /opt/homelab-repo/.git ]; then
    cd /opt/homelab-repo && git pull
  else
    rm -rf /opt/homelab-repo
    git clone ${REPO_URL} /opt/homelab-repo
  fi
"
ok "Repository geklont."

# ---------------------------------------------------------------------------
# 9. .ENV GENERIEREN
# ---------------------------------------------------------------------------
info "Generiere .env..."

POSTGRES_PASSWORD=$(openssl rand -hex 16)
HEALTHCHECKS_SECRET=$(openssl rand -hex 25)
TRAEFIK_PASSWORD=$(openssl rand -base64 12)

# htpasswd generieren (lokal, braucht htpasswd oder openssl)
if command -v htpasswd >/dev/null 2>&1; then
  TRAEFIK_AUTH=$(htpasswd -nb admin "$TRAEFIK_PASSWORD")
else
  # Fallback: auf dem Server generieren (apache2-utils via cloud-init installiert)
  TRAEFIK_AUTH=$(ssh "root@${SERVER_IP}" "htpasswd -nb admin '${TRAEFIK_PASSWORD}'")
fi

# $ zu $$ escapen für Docker Compose
TRAEFIK_AUTH_ESCAPED=$(echo "$TRAEFIK_AUTH" | sed 's/\$/\$\$/g')

GENERATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat <<EOF | ssh "root@${SERVER_IP}" "cat > /opt/homelab-repo/hetzner/.env"
# Generiert von bootstrap.sh am ${GENERATED_DATE}
DOMAIN=${DOMAIN}
SUBDOMAIN_PREFIX=${SUBDOMAIN_PREFIX}
TRAEFIK_DASHBOARD_AUTH=${TRAEFIK_AUTH_ESCAPED}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
HEADSCALE_API_KEY=
TS_AUTHKEY=
HEALTHCHECKS_SECRET=${HEALTHCHECKS_SECRET}
HEALTHCHECKS_SMTP_PASSWORD=
TZ=Europe/Berlin
EOF
ok ".env generiert."

# ---------------------------------------------------------------------------
# 10. DOCKER COMPOSE STARTEN
# ---------------------------------------------------------------------------
info "Starte Docker Compose..."

ssh "root@${SERVER_IP}" "cd /opt/homelab-repo/hetzner && docker compose up -d"
ok "Docker Compose gestartet."

# ---------------------------------------------------------------------------
# 11. HEADSCALE BOOTSTRAP
# ---------------------------------------------------------------------------
info "Headscale Bootstrap..."

ssh "root@${SERVER_IP}" "bash /opt/homelab-repo/hetzner/scripts/headscale-setup.sh"
ok "Headscale Bootstrap abgeschlossen."

# ---------------------------------------------------------------------------
# ZUSAMMENFASSUNG
# ---------------------------------------------------------------------------
echo ""
echo "============================================================================"
echo "  HOMELAB EXTERNAL - SETUP ABGESCHLOSSEN"
echo "============================================================================"
echo ""
echo "  Server IP:  ${SERVER_IP}"
echo "  SSH:        ssh root@${SERVER_IP}"
echo ""
echo "  URLs:"
for sub in "${SUBDOMAINS[@]}"; do
  printf "    %-12s https://%s.%s.%s\n" "${sub}:" "${sub}" "${SUBDOMAIN_PREFIX}" "${DOMAIN}"
done
echo ""
echo "  Traefik Dashboard:"
echo "    User:     admin"
echo "    Passwort: ${TRAEFIK_PASSWORD}"
echo ""
echo "  Verbleibende manuelle Schritte:"
echo "    1. ntfy Admin:        ssh root@${SERVER_IP} 'docker exec -it ntfy ntfy user add --role=admin admin'"
echo "    2. Healthchecks Admin: ssh root@${SERVER_IP} 'docker exec -it healthchecks ./manage.py createsuperuser'"
echo ""
echo "============================================================================"

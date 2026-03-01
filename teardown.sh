#!/bin/bash
# ============================================================================
# Homelab External - Teardown Script
# ============================================================================
# Löscht die komplette Infrastruktur:
#   - Hetzner Server
#   - Hetzner Firewall
#   - Hetzner SSH Key
#   - Cloudflare DNS Records
#
# Voraussetzungen:
#   - hcloud, curl, jq installiert
#   - HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID gesetzt
#
# Verwendung:
#   export HCLOUD_TOKEN=... CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ZONE_ID=...
#   ./teardown.sh
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# KONFIGURATION
# ---------------------------------------------------------------------------
SERVER_NAME="homelab-external"
DOMAIN="robinwerner.net"
SUBDOMAIN_PREFIX="homelab-external"
SSH_KEY_NAME="${SERVER_NAME}-key"
FIREWALL_NAME="${SERVER_NAME}-firewall"

SUBDOMAINS=("headscale" "uptime" "ntfy" "hc" "traefik")

# ---------------------------------------------------------------------------
# HILFSFUNKTIONEN
# ---------------------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

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
    error "Cloudflare API Fehler: ${msg}"
    return 1
  fi

  echo "$response"
}

# ---------------------------------------------------------------------------
# VORAUSSETZUNGEN
# ---------------------------------------------------------------------------
for cmd in hcloud curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { error "'${cmd}' ist nicht installiert."; exit 1; }
done

[ -z "${HCLOUD_TOKEN:-}" ] && { error "HCLOUD_TOKEN ist nicht gesetzt."; exit 1; }
[ -z "${CLOUDFLARE_API_TOKEN:-}" ] && { error "CLOUDFLARE_API_TOKEN ist nicht gesetzt."; exit 1; }
[ -z "${CLOUDFLARE_ZONE_ID:-}" ] && { error "CLOUDFLARE_ZONE_ID ist nicht gesetzt."; exit 1; }

# ---------------------------------------------------------------------------
# BESTÄTIGUNG
# ---------------------------------------------------------------------------
echo ""
echo "============================================================================"
echo "  WARNUNG: Dies löscht die GESAMTE Infrastruktur!"
echo "============================================================================"
echo ""
echo "  Folgende Ressourcen werden gelöscht:"
echo "    - Server:   ${SERVER_NAME}"
echo "    - Firewall: ${FIREWALL_NAME}"
echo "    - SSH Key:  ${SSH_KEY_NAME}"
echo "    - DNS:      ${#SUBDOMAINS[@]} A-Records (*.${SUBDOMAIN_PREFIX}.${DOMAIN})"
echo ""
echo "  Alle Daten auf dem Server gehen UNWIDERRUFLICH verloren!"
echo ""
read -rp "  Zum Bestätigen 'yes' eingeben: " CONFIRM
echo ""

if [ "$CONFIRM" != "yes" ]; then
  info "Abgebrochen."
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. SERVER LÖSCHEN
# ---------------------------------------------------------------------------
info "Lösche Server..."

if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
  hcloud server delete "$SERVER_NAME"
  ok "Server '${SERVER_NAME}' gelöscht."
else
  warn "Server '${SERVER_NAME}' nicht gefunden."
fi

# ---------------------------------------------------------------------------
# 2. FIREWALL LÖSCHEN
# ---------------------------------------------------------------------------
info "Lösche Firewall..."

if hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
  hcloud firewall delete "$FIREWALL_NAME"
  ok "Firewall '${FIREWALL_NAME}' gelöscht."
else
  warn "Firewall '${FIREWALL_NAME}' nicht gefunden."
fi

# ---------------------------------------------------------------------------
# 3. SSH KEY LÖSCHEN
# ---------------------------------------------------------------------------
info "Lösche SSH Key..."

if hcloud ssh-key describe "$SSH_KEY_NAME" >/dev/null 2>&1; then
  hcloud ssh-key delete "$SSH_KEY_NAME"
  ok "SSH Key '${SSH_KEY_NAME}' gelöscht."
else
  warn "SSH Key '${SSH_KEY_NAME}' nicht gefunden."
fi

# ---------------------------------------------------------------------------
# 4. DNS RECORDS LÖSCHEN
# ---------------------------------------------------------------------------
info "Lösche DNS Records..."

for sub in "${SUBDOMAINS[@]}"; do
  FQDN="${sub}.${SUBDOMAIN_PREFIX}.${DOMAIN}"

  RECORDS=$(cf_api GET "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${FQDN}")
  COUNT=$(echo "$RECORDS" | jq -r '.result | length')

  if [ "$COUNT" -gt "0" ]; then
    RECORD_ID=$(echo "$RECORDS" | jq -r '.result[0].id')
    cf_api DELETE "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${RECORD_ID}" >/dev/null
    ok "${FQDN} gelöscht."
  else
    warn "${FQDN} nicht gefunden."
  fi
done

# ---------------------------------------------------------------------------
# ABSCHLUSS
# ---------------------------------------------------------------------------
echo ""
echo "============================================================================"
echo "  TEARDOWN ABGESCHLOSSEN"
echo "============================================================================"
echo ""
echo "  Alle Ressourcen wurden gelöscht."
echo "  Zum Neuaufbau: ./bootstrap.sh"
echo ""
echo "============================================================================"

#!/bin/bash
# ============================================================================
# Headscale Bootstrap Script
# ============================================================================
# Erstellt Headscale User + API Key und schreibt den Key in .env
# Kann mehrfach ausgeführt werden (idempotent).
#
# Verwendung:
#   Lokal via SSH:  ssh root@SERVER 'bash /opt/homelab-repo/hetzner/scripts/headscale-setup.sh'
#   Auf dem Server: bash /opt/homelab-repo/hetzner/scripts/headscale-setup.sh
# ============================================================================
set -euo pipefail

COMPOSE_DIR="/opt/homelab-repo/hetzner"
ENV_FILE="${COMPOSE_DIR}/.env"
CONTAINER="headscale"
USER="homelab"

# ---------------------------------------------------------------------------
# Warte bis Headscale healthy ist
# ---------------------------------------------------------------------------
echo "Warte auf Headscale..."
for i in $(seq 1 30); do
  if docker exec "$CONTAINER" headscale health 2>/dev/null; then
    echo "Headscale ist bereit."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "FEHLER: Headscale nicht bereit nach 30 Versuchen." >&2
    exit 1
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# User erstellen (ignoriert "already exists" Fehler)
# ---------------------------------------------------------------------------
echo "Erstelle User '${USER}'..."
if docker exec "$CONTAINER" headscale users create "$USER" 2>&1 | grep -q "already exists"; then
  echo "User '${USER}' existiert bereits."
else
  echo "User '${USER}' erstellt."
fi

# ---------------------------------------------------------------------------
# API Key erstellen und in .env schreiben
# ---------------------------------------------------------------------------
# Prüfe ob bereits ein API Key in .env steht
if grep -q "^HEADSCALE_API_KEY=.\+" "$ENV_FILE" 2>/dev/null; then
  echo "API Key existiert bereits in .env - überspringe."
else
  echo "Erstelle API Key..."
  API_KEY=$(docker exec "$CONTAINER" headscale apikeys create --expiration 365d 2>&1 | tail -1)

  if [ -z "$API_KEY" ]; then
    echo "FEHLER: API Key konnte nicht erstellt werden." >&2
    exit 1
  fi

  # In .env schreiben
  if grep -q "^HEADSCALE_API_KEY=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^HEADSCALE_API_KEY=.*|HEADSCALE_API_KEY=${API_KEY}|" "$ENV_FILE"
  else
    echo "HEADSCALE_API_KEY=${API_KEY}" >> "$ENV_FILE"
  fi
  echo "API Key in .env geschrieben."

  # Headplane neu starten damit es den neuen Key nutzt
  echo "Starte Headplane neu..."
  cd "$COMPOSE_DIR"
  docker compose restart headplane
  echo "Headplane neu gestartet."
fi

echo ""
echo "=== Headscale Setup abgeschlossen ==="
echo "User:    ${USER}"
echo "API Key: $(grep '^HEADSCALE_API_KEY=' "$ENV_FILE" | cut -d= -f2)"

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

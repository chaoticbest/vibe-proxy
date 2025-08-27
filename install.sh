#!/usr/bin/env bash
set -euo pipefail

# ------------------
# Defaults / args
# ------------------
DOMAIN=""           # e.g., vibes.chaoticbest.com (optional)
EMAIL=""            # ACME email (optional, used if DOMAIN set)
HUB_REPO="https://github.com/chaoticbest/vibe-hub.git"
CLI_REPO="https://github.com/chaoticbest/vibe-cli.git"

usage() {
  cat <<USAGE
Usage: $0 [-d DOMAIN] [-e EMAIL] [-h HUB_REPO] [-c CLI_REPO]

Options:
  -d  Domain (enables HTTPS via Let's Encrypt). If omitted, HTTP by IP works.
  -e  Email for Let's Encrypt (recommended when -d is set)
  -h  Git repo for Vibe Hub (Dockerfile required). Default: ${HUB_REPO}
  -c  Git repo for Vibe CLI. Default: ${CLI_REPO}
USAGE
}

while getopts ":d:e:h:c:" opt; do
  case "$opt" in
    d) DOMAIN="$OPTARG" ;;
    e) EMAIL="$OPTARG" ;;
    h) HUB_REPO="$OPTARG" ;;
    c) CLI_REPO="$OPTARG" ;;
    :) echo "Missing argument for -$OPTARG" >&2; usage; exit 1 ;;
    \?) usage; exit 1 ;;
  esac
done

printf "\n==> Domain: %s\n" "${DOMAIN:-<none>}"
printf "==> ACME Email: %s\n" "${EMAIL:-<none>}"
printf "==> Hub repo: %s\n" "$HUB_REPO"
printf "==> CLI repo: %s\n\n" "$CLI_REPO"

# ------------------
# Helpers
# ------------------
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }

# ------------------
# Packages & Docker
# ------------------
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git jq

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker Engine + Compose v2"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # sane log rotation
  sudo mkdir -p /etc/docker
  echo '{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}' | sudo tee /etc/docker/daemon.json >/dev/null
  sudo systemctl enable --now docker
fi

# ------------------
# Folders & network
# ------------------
sudo mkdir -p /srv/vibes/{proxy/letsencrypt,static,apps,registry,blog,hub}
sudo touch /srv/vibes/proxy/letsencrypt/acme.json
sudo chmod 600 /srv/vibes/proxy/letsencrypt/acme.json
sudo chown -R "$USER":"$USER" /srv/vibes

docker network ls | grep -q vibes_net || docker network create vibes_net

# Save .env (informational; compose uses inline labels)
cat >/srv/vibes/proxy/.env <<ENV
DOMAIN=${DOMAIN}
ACME_EMAIL=${EMAIL}
ENVd

# ------------------
# Compose file (Traefik + Static + Hub)
# ------------------
cat >/srv/vibes/proxy/docker-compose.yml <<'YML'
version: "3.9"

networks:
  vibes_net:
    external: true

services:
  traefik:
    image: traefik:v3.1
    restart: unless-stopped
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      # entrypoints
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      # ACME (HTTP-01) for TLS
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
      - --accesslog=true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /srv/vibes/proxy/letsencrypt:/letsencrypt
    networks: [vibes_net]
    labels:
      - traefik.enable=true

  static:
    image: caddy:2
    restart: unless-stopped
    command: caddy file-server --root /srv/static
    volumes:
      - /srv/vibes/static:/srv/static:ro
    networks: [vibes_net]
    labels:
      - traefik.enable=true
      # Middlewares: add slash, strip /app, compress
      - traefik.http.middlewares.addslash.redirectregex.regex=^/app/([^/]+)$
      - traefik.http.middlewares.addslash.redirectregex.replacement=/app/$1/
      - traefik.http.middlewares.addslash.redirectregex.permanent=true
      - traefik.http.middlewares.static-strip.stripprefix.prefixes=/app
      - traefik.http.middlewares.compress.compress=true
      # HTTP catch-all (works by IP or any host)
      - traefik.http.routers.static-http.rule=PathPrefix(`/app/`)
      - traefik.http.routers.static-http.entrypoints=web
      - traefik.http.routers.static-http.priority=10
      - traefik.http.routers.static-http.middlewares=addslash,static-strip,compress
      # HTTPS (domain-specific) — harmless if DOMAIN empty; router simply won't match
      - traefik.http.routers.static-https.rule=Host(`${DOMAIN}`) && PathPrefix(`/app/`)
      - traefik.http.routers.static-https.entrypoints=websecure
      - traefik.http.routers.static-https.tls=true
      - traefik.http.routers.static-https.tls.certresolver=le
      - traefik.http.routers.static-https.priority=10
      - traefik.http.routers.static-https.middlewares=addslash,static-strip,compress

  hub:
    image: vibe-hub:latest
    restart: unless-stopped
    environment:
      - PORT=8080
      - REGISTRY_PATH=/data/registry/apps.json
    volumes:
      - /srv/vibes/registry:/data/registry:ro
    networks: [vibes_net]
    labels:
      - traefik.enable=true
      # HTTP catch-all
      - traefik.http.routers.hub-http.rule=PathPrefix(`/`)
      - traefik.http.routers.hub-http.entrypoints=web
      - traefik.http.routers.hub-http.priority=1
      - traefik.http.routers.hub-http.middlewares=compress
      # HTTPS (domain-specific)
      - traefik.http.routers.hub-https.rule=Host(`${DOMAIN}`) && PathPrefix(`/`)
      - traefik.http.routers.hub-https.entrypoints=websecure
      - traefik.http.routers.hub-https.tls=true
      - traefik.http.routers.hub-https.tls.certresolver=le
      - traefik.http.routers.hub-https.priority=1
      - traefik.http.routers.hub-https.middlewares=compress
      - traefik.http.middlewares.compress.compress=true
YML

# ------------------
# Build Hub image
# ------------------
if [ ! -d /srv/vibes/hub/.git ]; then
  git clone "$HUB_REPO" /srv/vibes/hub
else
  git -C /srv/vibes/hub pull --ff-only
fi

docker build -t vibe-hub:latest /srv/vibes/hub

# ------------------
# Bring up the stack
# ------------------
cd /srv/vibes/proxy
require_cmd docker
require_cmd docker-compose || true

docker compose up -d
sleep 2
docker compose ps

# ------------------
# Install pipx + vibe CLI
# ------------------
if ! command -v pipx >/dev/null 2>&1; then
  sudo apt-get install -y pipx
fi

# If running as root (e.g., cloud-init), install pipx globally
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  export PIPX_HOME=/usr/local/pipx
  export PIPX_BIN_DIR=/usr/local/bin
fi

pipx ensurepath || true

# Fresh install/upgrade from repo
if pipx list 2>/dev/null | grep -q vibe-cli; then
  pipx uninstall vibe-cli || true
fi
pipx install "git+${CLI_REPO}"

# ------------------
# Done
# ------------------
IP=$(curl -sS ifconfig.me || echo "<server-ip>")
echo
echo "✅ Vibe Proxy up."
echo "   - HTTP:  http://$IP/"
if [ -n "$DOMAIN" ]; then
  echo "   - HTTPS: https://$DOMAIN/  (DNS must point here for certs)"
fi
echo "✅ vibe CLI installed at: $(command -v vibe || echo "$HOME/.local/bin/vibe")"
echo "   Try: vibe list"
echo
echo "Smoke test:"
echo "  sudo mkdir -p /srv/vibes/static/hello && echo '<h1>ok</h1>' | sudo tee /srv/vibes/static/hello/index.html >/dev/null"
echo "  Open: http://$IP/app/hello/"
if [ -n "$DOMAIN" ]; then
  echo "  Or:   https://$DOMAIN/app/hello/"
fi
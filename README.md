# vibe-proxy

Turn any clean Ubuntu box into a Vibe Hub in \~1 command:

- Traefik reverse proxy (HTTP by IP; optional HTTPS for your domain)
- Static server for `/app/*` (Caddy)
- Vibe Hub app at `/`
- Vibe CLI installed via **pipx**

---

## Quick start (installer)

```bash
# Domain is optional; HTTP by IP will work even without it
curl -fsSL https://raw.githubusercontent.com/chaoticbest/vibe-proxy/main/install.sh \
  | bash -s -- \
    -d {DOMAIN_NAME} \
    -e {CERTIFICATE_EMAIL} \
    -h https://github.com/chaoticbest/vibes-hub.git \
    -c https://github.com/chaoticbest/vibe-cli.git
```

---

## Files in this repo

```
.
├── README.md                # this file
├── install.sh               # one-command installer (Docker, Proxy, Hub, CLI)
├── cloud-init.user-data     # EC2 user-data to auto-install on boot
├── LICENSE                  # MIT
└── compose-example.yml      # reference Traefik+Static+Hub compose
```

## Updates

```bash
# Update Hub and restart
cd /srv/vibes/hub && git pull --ff-only
docker build -t vibes-hub:latest /srv/vibes/hub
cd /srv/vibes/proxy && docker compose up -d

# Update CLI
pipx upgrade vibe-cli
```

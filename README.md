# Vibe Proxy

Turn any clean Ubuntu box into a Vibe Hub with a single command. This project provides a complete setup including:

- **Traefik reverse proxy** (HTTP by IP; optional HTTPS for your domain)
- **Static file server** for `/app/*` routes (Caddy)
- **Vibe Hub application** at the root path
- **Vibe CLI** installed via pipx

## Quick Start

### One-Command Installation

```bash
curl -fsSL https://raw.githubusercontent.com/chaoticbest/vibe-proxy/main/install.sh \
  | bash -s -- \
    -d {DOMAIN_NAME} \
    -e {CERTIFICATE_EMAIL} \
    -h https://github.com/chaoticbest/vibe-hub.git \
    -c https://github.com/chaoticbest/vibe-cli.git
```

**Parameters:**

- `-d` Domain name (optional - enables HTTPS via Let's Encrypt)
- `-e` Email for Let's Encrypt certificates (recommended when using a domain)
- `-h` Git repository for Vibe Hub (default: `https://github.com/chaoticbest/vibe-hub.git`)
- `-c` Git repository for Vibe CLI (default: `https://github.com/chaoticbest/vibe-cli.git`)

> **Note:** If no domain is provided, the setup will work with HTTP by IP address.

## Project Structure

```
.
├── README.md                # This documentation
├── install.sh               # One-command installer script
├── uninstall.sh             # Cleanup script to remove the installation
├── compose-example.yml      # Reference Docker Compose configuration
└── LICENSE                  # MIT License
```

## Maintenance

### Updating Components

**Update Vibe Hub:**

```bash
cd /srv/vibes/hub && git pull --ff-only
docker build -t vibes-hub:latest /srv/vibes/hub
cd /srv/vibes/proxy && docker compose up -d
```

**Update Vibe CLI:**

```bash
pipx upgrade vibe-cli
```

### Uninstalling

To completely remove the Vibe Proxy installation:

```bash
curl -fsSL https://raw.githubusercontent.com/chaoticbest/vibe-proxy/main/uninstall.sh | bash
```

Or run the uninstall script manually:

```bash
cd /srv/vibes/proxy && docker compose down -v
sudo rm -rf /srv/vibes
docker network rm vibes_net
pipx uninstall vibe-cli
```

## Architecture

The setup consists of three main services:

1. **Traefik** - Reverse proxy with automatic HTTPS via Let's Encrypt
2. **Caddy** - Static file server for `/app/*` routes
3. **Vibe Hub** - Main application served at the root path

All services are containerized and managed via Docker Compose, with proper networking and volume management.

## License

MIT License - see [LICENSE](LICENSE) file for details.

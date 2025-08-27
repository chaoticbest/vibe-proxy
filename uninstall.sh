# stop and remove stack
cd /srv/vibes/proxy && docker compose down -v || true
# remove files
sudo rm -rf /srv/vibes
# (optional) remove docker network
docker network rm vibes_net || true
# (optional) remove pipx-installed vibe CLI
pipx uninstall vibe-cli || true
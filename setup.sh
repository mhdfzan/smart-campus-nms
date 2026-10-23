#!/usr/bin/env bash
# One-command setup: checks prerequisites, starts the stack, provisions OpenNMS, enables fast polling, verifies.
# Usage: bash setup.sh [--no-fast-polling]
set -uo pipefail
cd "$(dirname "$0")" || exit 1

FAST=1
for a in "$@"; do
  case "$a" in
    --no-fast-polling) FAST=0 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "Unknown option: $a"; exit 1 ;;
  esac
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

say "Checking prerequisites"
command -v docker  >/dev/null 2>&1 || die "Docker is not installed. See docs/SETUP.md section 2."
command -v curl    >/dev/null 2>&1 || die "curl is missing. Run: sudo apt install -y curl"
command -v python3 >/dev/null 2>&1 || die "python3 is missing. Run: sudo apt install -y python3"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is missing. Run: sudo apt install -y docker-compose-v2"
docker info >/dev/null 2>&1 || die "Cannot talk to Docker. Either Docker is not running (try: sudo service docker start), or your user is not in the 'docker' group (run: sudo usermod -aG docker \$USER, then close and reopen the terminal)."

mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$mem_mb" -lt 6000 ]; then
  echo "WARNING: only ${mem_mb} MB RAM is visible. OpenNMS needs about 6-8 GB. It may be very slow or crash. (WSL users: see docs/SETUP.md, .wslconfig)"
fi

if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then
  busy=""
  for p in 8980 3000 9090 9100 9200 8081 8082; do
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$" && busy="$busy $p"
  done
  [ -z "$busy" ] || die "These ports are already in use:$busy . Stop whatever uses them (or a previous copy of this project: docker compose down) and retry."
fi

mkdir -p opennms/overlay   # must exist and be owned by you before Docker mounts it
say "Building and starting containers (first run: 5-10 minutes)"
docker compose up -d --build || die "docker compose failed. Scroll up for the first error message."

say "Provisioning devices into OpenNMS (waits for OpenNMS, 3-5 minutes on first start)"
bash opennms/provision.sh || die "OpenNMS provisioning failed."

if [ "$FAST" -eq 1 ]; then
  say "Enabling 30-second polling in OpenNMS (restarts OpenNMS, 3-5 minutes)"
  bash opennms/fast-polling.sh || die "Fast polling setup failed. Re-run: bash opennms/fast-polling.sh"
fi

say "Verifying"
sleep 20
bash scripts/check_stack.sh
rc=$?

cat <<MSG

Setup finished.
  Grafana     http://localhost:3000        admin / campus123   (dashboard: Smart Campus Network Overview)
  OpenNMS     http://localhost:8980/opennms  admin / admin
  Prometheus  http://localhost:9090

Next: bash scripts/run_tests.sh        (automated tests, see docs/TESTING.md)
MSG
[ $rc -eq 0 ] || echo "Some checks failed. Wait 2 minutes and run: bash scripts/check_stack.sh   If it still fails: bash scripts/collect_logs.sh"
exit $rc

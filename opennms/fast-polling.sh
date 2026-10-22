#!/usr/bin/env bash
# Make OpenNMS poll every 30 s instead of 5 min so outage alarms appear quickly. Restarts OpenNMS (3-5 min).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
mkdir -p opennms/overlay
OUT=opennms/overlay/poller-configuration.xml

docker compose cp opennms:/opt/opennms/etc/poller-configuration.xml "$OUT" >/dev/null \
  || { echo "ERROR: cannot copy poller config. Is the 'opennms' container running? (docker compose ps)" >&2; exit 1; }
sed -i 's/interval="300000"/interval="30000"/g' "$OUT"
echo "Applying 30 s polling and restarting OpenNMS..."
docker compose restart opennms >/dev/null || { echo "ERROR: restart failed" >&2; exit 1; }

waited=0
until curl -fs --max-time 10 -u "${AUTH:-admin:admin}" "${ONMS:-http://localhost:8980/opennms}/rest/info" >/dev/null 2>&1; do
  sleep 10; waited=$((waited+10))
  [ "$waited" -ge 900 ] && { echo "ERROR: OpenNMS not back after 15 min. See: docker compose logs opennms | tail -50" >&2; exit 1; }
done
n=$(docker compose exec -T opennms grep -c 'interval="30000"' /opt/opennms/etc/poller-configuration.xml 2>/dev/null || echo 0)
echo "Fast polling active ($n interval entries at 30 s)."

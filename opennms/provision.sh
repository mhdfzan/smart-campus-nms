#!/usr/bin/env bash
# Provision the simulated campus devices into OpenNMS through its REST API. Safe to run repeatedly.
set -uo pipefail
ONMS=${ONMS:-http://localhost:8980/opennms}
AUTH=${AUTH:-admin:admin}
FS=CampusLab
MAX_WAIT=${MAX_WAIT:-1200}   # seconds

echo "Waiting for OpenNMS (first start can take 3-5 minutes)..."
waited=0
until curl -fs --max-time 10 -u "$AUTH" "$ONMS/rest/info" >/dev/null 2>&1; do
  sleep 10; waited=$((waited+10))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    echo "ERROR: OpenNMS did not become ready within ${MAX_WAIT}s. Run: docker compose logs opennms | tail -50" >&2
    exit 1
  fi
done

mk_node() { # label ip category
cat <<XML
  <node foreign-id="$1" node-label="$1">
    <interface ip-addr="$2" status="1" snmp-primary="P">
      <monitored-service service-name="ICMP"/>
      <monitored-service service-name="SNMP"/>
    </interface>
    <category name="$3"/>
  </node>
XML
}

REQ=$(mktemp)
trap 'rm -f "$REQ"' EXIT
cat > "$REQ" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<model-import xmlns="http://xmlns.opennms.org/xsd/config/model-import" foreign-source="$FS">
$(mk_node core-router 172.28.0.10 Routers)
$(mk_node switch-admin 172.28.0.11 Switches)
$(mk_node switch-academic 172.28.0.12 Switches)
$(mk_node dc-server 172.28.0.13 Servers)
</model-import>
XML

curl -fsS -u "$AUTH" -H 'Content-Type: application/xml' -X POST --data @"$REQ" "$ONMS/rest/requisitions" >/dev/null \
  || { echo "ERROR: could not upload requisition (wrong OpenNMS password?)" >&2; exit 1; }
curl -fsS -u "$AUTH" -X PUT "$ONMS/rest/requisitions/$FS/import" >/dev/null \
  || { echo "ERROR: could not import requisition" >&2; exit 1; }
echo "Requisition '$FS' imported. The 4 nodes appear in OpenNMS (Inventory > Nodes) within about a minute."

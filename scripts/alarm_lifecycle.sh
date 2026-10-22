#!/usr/bin/env bash
# OpenNMS alarm lifecycle via REST.  Usage: bash scripts/alarm_lifecycle.sh list | ack <id> | unack <id> | escalate <id> | clear <id>
ONMS=${ONMS:-http://localhost:8980/opennms}; AUTH=${AUTH:-admin:admin}
put() { curl -fsS -u "$AUTH" -X PUT -d "$2" "$ONMS/rest/alarms/$1" >/dev/null; }
case "${1:-list}" in
  list)     curl -fsS -u "$AUTH" -H 'Accept: application/json' "$ONMS/rest/alarms?limit=20&orderBy=id&order=desc" \
              | python3 "$(dirname "$0")/helper.py" list_alarms ;;
  ack)      put "${2:?alarm id}" "ack=true"      && echo "alarm $2 acknowledged" ;;
  unack)    put "${2:?alarm id}" "ack=false"     && echo "alarm $2 un-acknowledged" ;;
  escalate) put "${2:?alarm id}" "escalate=true" && echo "alarm $2 escalated" ;;
  clear)    put "${2:?alarm id}" "clear=true"    && echo "alarm $2 cleared" ;;
  *) sed -n '2,2p' "$0" ;;
esac

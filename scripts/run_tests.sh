#!/usr/bin/env bash
# Automated test runner.
#   bash scripts/run_tests.sh            basic checks, no faults injected (about 2 min)
#   bash scripts/run_tests.sh faults     + interface / router / exporter failures with recovery (about 10 min)
#   bash scripts/run_tests.sh alarms     OpenNMS alarm lifecycle: create, acknowledge, clear (5-20 min)
#   bash scripts/run_tests.sh full       everything incl. SNMP outage and CPU load (30-60 min)
# Results are printed and saved in test-results/results-<time>.md
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

GROUP=${1:-basic}
case "$GROUP" in basic|faults|alarms|full) ;; *) sed -n '2,7p' "$0"; exit 2 ;; esac

PROM=${PROM:-http://localhost:9090}
ONMS=${ONMS:-http://localhost:8980/opennms}
AUTH=${AUTH:-admin:admin}
GRAF=${GRAF:-http://localhost:3000}
GAUTH=${GAUTH:-admin:campus123}
RC1=http://localhost:8081/restconf/data/ietf-interfaces:interfaces
RC2=http://localhost:8082/restconf/data/ietf-interfaces:interfaces

if grep -q 'interval="30000"' opennms/overlay/poller-configuration.xml 2>/dev/null; then ALARM_TIMEOUT=420; else ALARM_TIMEOUT=1200; fi

mkdir -p test-results
REPORT="test-results/results-$(date +%Y%m%d-%H%M%S).md"
PASS=0; FAIL=0; WARN=0; SKIP=0
DETAIL=""; OVERRIDE=""; ALARM_ID=""; FAULT_MS=0; DOTS=0

{
  echo "# Test results ($GROUP)"
  echo
  echo "- Date: $(date '+%F %T %Z')"
  echo "- Host: $(uname -sr)"
  echo "- Commit: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)"
  echo "- OpenNMS alarm timeout: ${ALARM_TIMEOUT}s"
  echo
  echo "| ID | Test | Result | Time | Detail |"
  echo "|---|---|---|---|---|"
} > "$REPORT"

# ---------------------------------------------------------------- helpers
helper() { python3 scripts/helper.py "$@"; }
pq() { curl -fsS --max-time 10 -G "$PROM/api/v1/query" --data-urlencode "query=$1" 2>/dev/null | helper first_value; }
pq_is() { [ "$(pq "$1")" = "$2" ]; }
firing() { [ -n "$(pq "ALERTS{alertname=\"$1\",alertstate=\"firing\"}")" ]; }
not_firing() { ! firing "$1"; }
wait_until() { local t=$1; shift; local end=$((SECONDS+t)); while [ "$SECONDS" -lt "$end" ]; do "$@" && return 0; printf '.'; DOTS=1; sleep 5; done; return 1; }
onms_get() { curl -fsS --max-time 20 -u "$AUTH" -H 'Accept: application/json' "$ONMS$1"; }
alarms_list() { onms_get "/rest/alarms?limit=100&orderBy=id&order=desc"; }
find_alarm() { alarms_list 2>/dev/null | helper find_alarm "$1" "$2" "$3"; }
alarm_field() { alarms_list 2>/dev/null | helper alarm_field "$1" "$2"; }
alarm_put() { curl -fsS --max-time 20 -u "$AUTH" -X PUT -d "$2" "$ONMS/rest/alarms/$1" >/dev/null; }
is_acked() { [ "$(alarm_field "$ALARM_ID" ackUser)" = "admin" ]; }
is_cleared() { [ "$(alarm_field "$ALARM_ID" severity)" = "CLEARED" ]; }
sim() { curl -fsS --max-time 10 -X POST "http://localhost:8081/control?interface=GigabitEthernet0/1&state=$1" >/dev/null; }

record() { # id name status detail
  local c=""
  if [ "$DOTS" -eq 1 ]; then echo; DOTS=0; fi
  case "$3" in PASS) c=32 ;; FAIL) c=31 ;; WARN) c=33 ;; *) c=36 ;; esac
  printf '\033[%sm[%s] %-4s\033[0m %s  %s\n' "$c" "$1" "$3" "$2" "$4"
  printf '| %s | %s | %s | %s | %s |\n' "$1" "$2" "$3" "$(date +%T)" "${4//|//}" >> "$REPORT"
  case "$3" in PASS) PASS=$((PASS+1)) ;; FAIL) FAIL=$((FAIL+1)) ;; WARN) WARN=$((WARN+1)) ;; SKIP) SKIP=$((SKIP+1)) ;; esac
}
run() { # id name function
  DETAIL=""; OVERRIDE=""
  echo "... [$1] $2"
  if "$3"; then record "$1" "$2" "${OVERRIDE:-PASS}" "$DETAIL"; else record "$1" "$2" FAIL "$DETAIL"; fi
}

cleanup() {
  curl -fsS --max-time 5 -X POST "http://localhost:8081/control?interface=all&state=up" >/dev/null 2>&1
  docker compose start switch-admin edge-router-2 node-exporter >/dev/null 2>&1
  docker unpause switch-academic >/dev/null 2>&1
  docker rm -f cpuload >/dev/null 2>&1
}
trap cleanup EXIT
trap 'echo; echo "Interrupted: restoring services..."; exit 130' INT TERM

# ---------------------------------------------------------------- basic tests
t01() {
  local out rc
  out=$(bash scripts/check_stack.sh 2>&1); rc=$?
  DETAIL=$(echo "$out" | grep FAIL | tr '\n' ' ')
  return $rc
}
t02() {
  wait_until 60 pq_is 'min(up)' 1
  local rc=$?
  DETAIL="targets=$(pq 'count(up)'), min(up)=$(pq 'min(up)')"
  [ "$rc" -eq 0 ] && [ "$(pq 'count(up)')" -ge 3 ]
}
t03() {
  local labels total missing="" want
  labels=$(onms_get /rest/nodes 2>/dev/null | helper node_labels)
  total=$(echo "$labels" | grep -c .)
  for want in core-router switch-admin switch-academic dc-server; do
    echo "$labels" | grep -qx "$want" || missing="$missing $want"
  done
  DETAIL=${missing:+"missing nodes:$missing"}
  DETAIL=${DETAIL:-"all 4 campus nodes present ($total nodes in total; extras such as OpenNMS's own server node are normal)"}
  [ -z "$missing" ]
}
t04() {
  local bad="" pair ip want got
  for pair in 172.28.0.10:Cisco 172.28.0.11:Juniper 172.28.0.12:Arista 172.28.0.13:Linux; do
    ip=${pair%%:*}; want=${pair##*:}
    got=$(docker compose exec -T core-router snmpget -v2c -c public -Oqv "$ip" 1.3.6.1.2.1.1.1.0 2>&1)
    echo "$got" | grep -qi "$want" || bad="$bad $ip(expected $want, got: ${got:0:40})"
  done
  DETAIL=${bad:-"all 4 devices answer SNMP with the expected vendor string"}
  [ -z "$bad" ]
}
t05() {
  local bad=""
  curl -fsS --max-time 10 -u labuser:labpass "$RC1" | grep -q 'GigabitEthernet0/1' || bad="$bad edge-router-1"
  curl -fsS --max-time 10 -u labuser:labpass "$RC2" | grep -q 'GigabitEthernet0/1' || bad="$bad edge-router-2"
  DETAIL=${bad:+"failed:$bad"}; DETAIL=${DETAIL:-"both RESTCONF endpoints return interface data"}
  [ -z "$bad" ]
}
t06() {
  local c1 c2
  c1=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$RC1")
  c2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -u labuser:wrong "$RC1")
  DETAIL="no credentials -> HTTP $c1, wrong password -> HTTP $c2 (expected 401, 401)"
  [ "$c1" = 401 ] && [ "$c2" = 401 ]
}
t07() {
  wait_until 90 pq_is 'campus_device_up{device="edge-router-1"}' 1 && wait_until 60 pq_is 'campus_device_up{device="edge-router-2"}' 1
  local rc=$?
  local n; n=$(curl -fsS --max-time 10 localhost:9200/metrics 2>/dev/null | grep -c '^campus_device_interface_oper_status')
  DETAIL="exporter reports $n interface status series (expected 6)"
  [ "$rc" -eq 0 ] && [ "$n" -ge 6 ]
}
t08() {
  local ok=1
  curl -fsS --max-time 10 -u "$GAUTH" "$GRAF/api/dashboards/uid/campus-overview" | grep -q 'Smart Campus Network Overview' || { DETAIL="dashboard not found"; ok=0; }
  if [ $ok -eq 1 ]; then
    curl -fsS --max-time 10 -u "$GAUTH" -G "$GRAF/api/datasources/proxy/uid/prometheus/api/v1/query" --data-urlencode query=up | grep -q '"status":"success"' \
      || { DETAIL="Grafana cannot query Prometheus"; ok=0; }
  fi
  [ $ok -eq 1 ] && DETAIL="dashboard provisioned; Grafana can query Prometheus"
  [ $ok -eq 1 ]
}

# ---------------------------------------------------------------- fault tests (Prometheus / Grafana)
t09() {
  local Q='campus_device_interface_oper_status{device="edge-router-1",interface="GigabitEthernet0/1"}' t0=$SECONDS d1 d2
  sim down || { DETAIL="cannot reach RESTCONF simulator"; return 1; }
  wait_until 90 pq_is "$Q" 0 || { DETAIL="interface metric never dropped to 0"; return 1; }
  d1=$((SECONDS-t0))
  wait_until 180 firing InterfaceDown || { DETAIL="InterfaceDown alert did not fire in 180s"; return 1; }
  d2=$((SECONDS-t0))
  sim up
  wait_until 90 pq_is "$Q" 1 || { DETAIL="metric did not recover"; return 1; }
  wait_until 180 not_firing InterfaceDown || { DETAIL="alert did not resolve"; return 1; }
  DETAIL="metric went down after ${d1}s, alert fired after ${d2}s, then recovered"
}
t10() {
  local Q='campus_device_up{device="edge-router-2"}' t0=$SECONDS d1 d2
  docker compose stop edge-router-2 >/dev/null 2>&1 || { DETAIL="cannot stop edge-router-2"; return 1; }
  wait_until 90 pq_is "$Q" 0 || { DETAIL="campus_device_up never dropped to 0"; return 1; }
  d1=$((SECONDS-t0))
  wait_until 180 firing DeviceUnreachable || { DETAIL="DeviceUnreachable alert did not fire"; return 1; }
  d2=$((SECONDS-t0))
  docker compose start edge-router-2 >/dev/null 2>&1
  wait_until 120 pq_is "$Q" 1 || { DETAIL="router did not recover"; return 1; }
  wait_until 180 not_firing DeviceUnreachable || { DETAIL="alert did not resolve"; return 1; }
  DETAIL="device down after ${d1}s, alert after ${d2}s, then recovered"
}
t11() {
  local Q='up{job="campus-linux"}' t0=$SECONDS d1 d2
  docker compose stop node-exporter >/dev/null 2>&1 || { DETAIL="cannot stop node-exporter"; return 1; }
  wait_until 90 pq_is "$Q" 0 || { DETAIL="target never went down"; return 1; }
  d1=$((SECONDS-t0))
  wait_until 180 firing ExporterTargetDown || { DETAIL="ExporterTargetDown alert did not fire"; return 1; }
  d2=$((SECONDS-t0))
  docker compose start node-exporter >/dev/null 2>&1
  wait_until 120 pq_is "$Q" 1 || { DETAIL="target did not recover"; return 1; }
  wait_until 180 not_firing ExporterTargetDown || { DETAIL="alert did not resolve"; return 1; }
  DETAIL="target down after ${d1}s, alert after ${d2}s, then recovered"
}

# ---------------------------------------------------------------- OpenNMS alarm lifecycle
t12() {
  FAULT_MS=$(( $(date +%s) * 1000 )); ALARM_ID=""
  docker compose stop switch-admin >/dev/null 2>&1 || { DETAIL="cannot stop switch-admin"; return 1; }
  local t0=$SECONDS
  while [ -z "$ALARM_ID" ] && [ $((SECONDS-t0)) -lt "$ALARM_TIMEOUT" ]; do
    ALARM_ID=$(find_alarm switch-admin "nodeDown|interfaceDown|nodeLostService" "$FAULT_MS")
    [ -n "$ALARM_ID" ] || { printf '.'; DOTS=1; sleep 10; }
  done
  [ -n "$ALARM_ID" ] || { DETAIL="no OpenNMS alarm for switch-admin within ${ALARM_TIMEOUT}s (see Alarms page)"; return 1; }
  DETAIL="fault at $(date -d "@$((FAULT_MS/1000))" +%T), alarm id $ALARM_ID after $((SECONDS-t0))s"
}
t13() {
  [ -n "$ALARM_ID" ] || { DETAIL="no alarm from T12"; return 1; }
  alarm_put "$ALARM_ID" "ack=true" || { DETAIL="acknowledge request failed"; return 1; }
  wait_until 60 is_acked || { DETAIL="alarm $ALARM_ID not showing acknowledged by admin"; return 1; }
  DETAIL="alarm $ALARM_ID acknowledged by admin"
}
t14() {
  docker compose start switch-admin >/dev/null 2>&1
  [ -n "$ALARM_ID" ] || { DETAIL="no alarm from T12 (device restarted anyway)"; return 1; }
  local t0=$SECONDS
  if wait_until "$ALARM_TIMEOUT" is_cleared; then
    DETAIL="device restored; alarm $ALARM_ID cleared automatically after $((SECONDS-t0))s"
    return 0
  fi
  alarm_put "$ALARM_ID" "clear=true"; sleep 5
  if is_cleared; then
    OVERRIDE=WARN; DETAIL="no automatic clear within ${ALARM_TIMEOUT}s; alarm $ALARM_ID cleared manually via API"
    return 0
  fi
  DETAIL="alarm $ALARM_ID could not be cleared"; return 1
}
t15() {
  local id="" t0=$SECONDS
  FAULT_MS=$(( $(date +%s) * 1000 ))
  docker pause switch-academic >/dev/null 2>&1 || { DETAIL="cannot pause switch-academic"; return 1; }
  while [ -z "$id" ] && [ $((SECONDS-t0)) -lt "$ALARM_TIMEOUT" ]; do
    id=$(find_alarm switch-academic "SNMP" "$FAULT_MS"); [ -n "$id" ] || { printf '.'; DOTS=1; sleep 10; }
  done
  docker unpause switch-academic >/dev/null 2>&1
  [ -n "$id" ] || { DETAIL="no SNMP outage alarm for switch-academic within ${ALARM_TIMEOUT}s"; return 1; }
  DETAIL="SNMP outage alarm $id after $((SECONDS-t0))s; device restored"
}
t16() {
  bash scripts/demo_failures.sh cpu-load >/dev/null 2>&1 || { DETAIL="cannot start CPU load"; return 1; }
  wait_until 420 firing HighCpuUsage || { DETAIL="HighCpuUsage did not fire in 420s"; return 1; }
  bash scripts/demo_failures.sh cpu-stop >/dev/null 2>&1
  wait_until 300 not_firing HighCpuUsage || { DETAIL="alert did not resolve after load stopped"; return 1; }
  DETAIL="CPU alert fired under load and resolved afterwards"
}

# ---------------------------------------------------------------- run
echo "Running test group: $GROUP   (report: $REPORT)"
echo "Each test waits 1-5 minutes and prints a dot every few seconds. Please do NOT press Ctrl+C unless you want to abort."
run T01 "Stack health (all endpoints answer)" t01
if [ "$FAIL" -gt 0 ]; then
  echo "Stack is not healthy; stopping. Wait a few minutes (OpenNMS starts slowly), or run: bash scripts/collect_logs.sh"
else
  case "$GROUP" in basic|full)
    run T02 "Prometheus targets all UP" t02
    run T03 "OpenNMS discovered the 4 campus nodes" t03
    run T04 "Vendor identification over SNMP" t04
    run T05 "RESTCONF access with valid credentials" t05
    run T06 "RESTCONF rejects missing/wrong credentials" t06
    run T07 "Exporter publishes NETCONF/RESTCONF metrics" t07
    run T08 "Grafana dashboard and datasource" t08 ;;
  esac
  case "$GROUP" in faults|full)
    run T09 "Interface failure and recovery (InterfaceDown alert)" t09
    run T10 "Router unreachable and recovery (DeviceUnreachable alert)" t10
    run T11 "Exporter failure and recovery (ExporterTargetDown alert)" t11 ;;
  esac
  case "$GROUP" in alarms|full)
    run T12 "OpenNMS alarm created on device failure" t12
    run T13 "Alarm acknowledged by operator" t13
    run T14 "Device recovery and alarm cleared" t14 ;;
  esac
  if [ "$GROUP" = full ]; then
    run T15 "SNMP service outage detected by OpenNMS" t15
    run T16 "High CPU alert" t16
  fi
fi

{ echo; echo "**Summary:** $PASS passed, $FAIL failed, $WARN warnings, $SKIP skipped"; } >> "$REPORT"
echo
echo "Summary: $PASS passed, $FAIL failed, $WARN warnings, $SKIP skipped"
echo "Report saved: $REPORT"
[ "$FAIL" -eq 0 ]

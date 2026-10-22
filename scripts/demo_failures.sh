#!/usr/bin/env bash
# Failure / recovery demonstrations.  Usage: bash scripts/demo_failures.sh <name>
#   device-down  device-up     stop/start switch-admin            (OpenNMS node-down alarm)
#   snmp-down    snmp-up       pause/unpause switch-academic      (OpenNMS SNMP service outage, ping still works)
#   iface-down   iface-up      edge-router-1 Gi0/1 down/up        (Grafana + Prometheus InterfaceDown)
#   router-down  router-up     stop/start edge-router-2           (Prometheus DeviceUnreachable)
#   cpu-load     cpu-stop      5-minute CPU stress                (Prometheus HighCpuUsage)
#   exporter-down exporter-up  stop/start node-exporter           (Prometheus ExporterTargetDown)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ts() { date '+%F %T %Z'; }
case "${1:-help}" in
  device-down)   echo "$(ts) stopping switch-admin";          docker compose stop switch-admin ;;
  device-up)     echo "$(ts) starting switch-admin";          docker compose start switch-admin ;;
  snmp-down)     echo "$(ts) pausing switch-academic";       docker pause switch-academic ;;
  snmp-up)       echo "$(ts) unpausing switch-academic";     docker unpause switch-academic ;;
  iface-down)    echo "$(ts) edge-router-1 Gi0/1 -> down";   curl -fsS -X POST "http://localhost:8081/control?interface=GigabitEthernet0/1&state=down"; echo ;;
  iface-up)      echo "$(ts) edge-router-1 Gi0/1 -> up";     curl -fsS -X POST "http://localhost:8081/control?interface=GigabitEthernet0/1&state=up"; echo ;;
  router-down)   echo "$(ts) stopping edge-router-2";        docker compose stop edge-router-2 ;;
  router-up)     echo "$(ts) starting edge-router-2";        docker compose start edge-router-2 ;;
  cpu-load)      echo "$(ts) starting CPU load for 5 minutes"
                 docker rm -f cpuload >/dev/null 2>&1 || true
                 docker run -d --rm --name cpuload alpine sh -c 'n=$(nproc); i=0; while [ $i -lt $n ]; do timeout 300 sh -c "while :; do :; done" & i=$((i+1)); done; wait' ;;
  cpu-stop)      echo "$(ts) stopping CPU load";              docker rm -f cpuload ;;
  exporter-down) echo "$(ts) stopping node-exporter";         docker compose stop node-exporter ;;
  exporter-up)   echo "$(ts) starting node-exporter";         docker compose start node-exporter ;;
  *) sed -n '2,8p' "$0" ;;
esac

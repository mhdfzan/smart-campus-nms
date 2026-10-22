#!/usr/bin/env bash
# Quick health check of every component. Exit code 1 if anything fails.
bad=0
chk() { # name, curl args...
  local name=$1; shift
  if curl -fs -o /dev/null --max-time 10 "$@"; then echo "OK    $name"; else echo "FAIL  $name"; bad=1; fi
}
chk "OpenNMS web UI"        http://localhost:8980/opennms/login.jsp
chk "Prometheus"            http://localhost:9090/-/ready
chk "Grafana"               http://localhost:3000/api/health
chk "node-exporter"         http://localhost:9100/metrics
chk "campus-exporter"       http://localhost:9200/metrics
chk "RESTCONF edge-router-1" -u labuser:labpass http://localhost:8081/restconf/data/ietf-interfaces:interfaces
chk "RESTCONF edge-router-2" -u labuser:labpass http://localhost:8082/restconf/data/ietf-interfaces:interfaces
exit $bad

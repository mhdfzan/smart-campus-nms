#!/usr/bin/env bash
# Bundle diagnostics into one text file to send to the project owner when something fails.
cd "$(dirname "$0")/.." || exit 1
OUT="diagnostics-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "### date";       date
  echo "### uname";      uname -a
  echo "### memory";     free -m 2>/dev/null
  echo "### docker";     docker version --format '{{.Server.Version}}' 2>&1; docker compose version 2>&1
  echo "### git commit"; git rev-parse --short HEAD 2>&1
  echo "### compose ps"; docker compose ps -a 2>&1
  echo "### images";     docker compose images 2>&1
  echo "### stack check"; bash scripts/check_stack.sh 2>&1
  for s in opennms campus-exporter prometheus grafana node-exporter db edge-router-1 edge-router-2; do
    echo; echo "### logs: $s (last 80 lines)"; docker compose logs --no-color --tail=80 "$s" 2>&1
  done
} > "$OUT" 2>&1
echo "Wrote $OUT  -- send this file to the project owner."

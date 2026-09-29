#!/usr/bin/env bash
#
# list-k3d-clusters.sh
#
# Lists all k3d clusters and whether each one is currently up or down.
# Read-only -- doesn't start, stop, or delete anything.
#
# Usage:
#   ./list-k3d-clusters.sh
#
set -euo pipefail

if ! command -v k3d >/dev/null 2>&1; then
  echo "ERROR: k3d is not installed. Install it with: brew install k3d" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot reach the Docker Engine API. Is Rancher Desktop running," >&2
  echo "       with Container Engine set to 'dockerd (moby)'?" >&2
  exit 1
fi

ROWS="$(k3d cluster list -o json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for c in data:
    name = c.get("name", "")
    servers_running = c.get("serversRunning", 0)
    servers_count = c.get("serversCount", 0)
    agents_running = c.get("agentsRunning", 0)
    agents_count = c.get("agentsCount", 0)
    status = "Up" if servers_running > 0 else "Down"
    print(f"{name}|{status}|{servers_running}/{servers_count}|{agents_running}/{agents_count}")
' 2>/dev/null || true)"

if [[ -z "${ROWS}" ]]; then
  echo "No k3d clusters found."
  exit 0
fi

printf "%-20s %-6s %-10s %-10s\n" "NAME" "STATUS" "SERVERS" "AGENTS"
while IFS='|' read -r NAME STATUS SERVERS AGENTS; do
  [[ -n "${NAME}" ]] || continue
  printf "%-20s %-6s %-10s %-10s\n" "${NAME}" "${STATUS}" "${SERVERS}" "${AGENTS}"
done <<< "${ROWS}"

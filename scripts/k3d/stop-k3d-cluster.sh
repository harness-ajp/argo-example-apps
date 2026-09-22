#!/usr/bin/env bash
#
# stop-k3d-cluster.sh
#
# Stops a k3d cluster (containers paused/stopped, NOT deleted -- state and
# workloads are preserved and come back with start-k3d-cluster.sh).
#
# Usage:
#   ./stop-k3d-cluster.sh              # shows a menu of currently-running clusters
#   ./stop-k3d-cluster.sh <name>        # stops this cluster directly, no menu
#
set -euo pipefail

TARGET_ARG="${1:-}"

if ! command -v k3d >/dev/null 2>&1; then
  echo "ERROR: k3d is not installed. Install it with: brew install k3d" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot reach the Docker Engine API. Is Rancher Desktop running," >&2
  echo "       with Container Engine set to 'dockerd (moby)'?" >&2
  exit 1
fi

# ---- Gather cluster names + running state ----------------------------------
# (Using a plain read loop instead of `mapfile`/`readarray`, since macOS ships
# bash 3.2 by default and those builtins require bash 4+.)
ALL_NAMES=()
ALL_RUNNING=()
while IFS='|' read -r NAME RUNNING; do
  [[ -n "${NAME}" ]] || continue
  ALL_NAMES+=("${NAME}")
  ALL_RUNNING+=("${RUNNING}")
done < <(k3d cluster list -o json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
for c in data:
    name = c.get("name", "")
    running = c.get("serversRunning", 0) > 0
    print(f"{name}|{1 if running else 0}")
' 2>/dev/null || true)

if [[ ${#ALL_NAMES[@]} -eq 0 ]]; then
  echo "No k3d clusters found."
  exit 0
fi

TARGET=""

if [[ -n "${TARGET_ARG}" ]]; then
  # ---- A cluster name was given on the command line -- validate and skip the menu ----
  for n in "${ALL_NAMES[@]}"; do
    if [[ "${n}" == "${TARGET_ARG}" ]]; then
      TARGET="${n}"
      break
    fi
  done

  if [[ -z "${TARGET}" ]]; then
    echo "ERROR: No cluster named '${TARGET_ARG}'." >&2
    echo >&2
    echo "Existing k3d clusters:" >&2
    for n in "${ALL_NAMES[@]}"; do
      echo "  - ${n}" >&2
    done
    exit 1
  fi
else
  # ---- No argument -- present a menu of currently-running clusters --------
  RUNNING_NAMES=()
  for i in "${!ALL_NAMES[@]}"; do
    [[ "${ALL_RUNNING[$i]}" == "1" ]] && RUNNING_NAMES+=("${ALL_NAMES[$i]}")
  done

  if [[ ${#RUNNING_NAMES[@]} -eq 0 ]]; then
    echo "No running k3d clusters to stop."
    exit 0
  fi

  echo "Running k3d clusters:"
  echo
  for i in "${!RUNNING_NAMES[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${RUNNING_NAMES[$i]}"
  done
  echo "   0) Cancel"
  echo

  read -r -p "Select a cluster to stop [0-${#RUNNING_NAMES[@]}]: " CHOICE

  if [[ ! "${CHOICE}" =~ ^[0-9]+$ ]] || (( CHOICE < 0 || CHOICE > ${#RUNNING_NAMES[@]} )); then
    echo "Invalid selection." >&2
    exit 1
  fi

  if [[ "${CHOICE}" -eq 0 ]]; then
    echo "Cancelled -- nothing was stopped."
    exit 0
  fi

  TARGET="${RUNNING_NAMES[$((CHOICE - 1))]}"
fi

echo "Stopping cluster '${TARGET}'..."
k3d cluster stop "${TARGET}"
echo "Done. Bring it back with: ./start-k3d-cluster.sh ${TARGET}"

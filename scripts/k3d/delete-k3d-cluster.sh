#!/usr/bin/env bash
#
# delete-k3d-cluster.sh
#
# Lists your existing k3d clusters and lets you pick one (by number) to
# delete, with a confirmation prompt before anything is destroyed.
#
# Usage:
#   ./delete-k3d-cluster.sh              # interactive menu
#   ./delete-k3d-cluster.sh <name>        # skip the menu, target this cluster directly
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

# ---- Gather cluster names ---------------------------------------------------
# (Using a plain read loop instead of `mapfile`/`readarray`, since macOS ships
# bash 3.2 by default and those builtins require bash 4+.)
CLUSTERS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && CLUSTERS+=("${line}")
done < <(k3d cluster list -o json | python3 -c '
import json, sys
data = json.load(sys.stdin)
for c in data:
    print(c["name"])
' 2>/dev/null || true)

if [[ ${#CLUSTERS[@]} -eq 0 ]]; then
  echo "No k3d clusters found."
  exit 0
fi

TARGET=""

if [[ -n "${TARGET_ARG}" ]]; then
  # ---- A cluster name was given on the command line -- validate and skip the menu ----
  for c in "${CLUSTERS[@]}"; do
    if [[ "${c}" == "${TARGET_ARG}" ]]; then
      TARGET="${c}"
      break
    fi
  done

  if [[ -z "${TARGET}" ]]; then
    echo "ERROR: No cluster named '${TARGET_ARG}'." >&2
    echo >&2
    echo "Existing k3d clusters:" >&2
    for c in "${CLUSTERS[@]}"; do
      echo "  - ${c}" >&2
    done
    exit 1
  fi
else
  # ---- No argument -- present a numbered menu ------------------------------
  echo "Existing k3d clusters:"
  echo
  for i in "${!CLUSTERS[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${CLUSTERS[$i]}"
  done
  echo "   0) Cancel"
  echo

  read -r -p "Select a cluster to delete [0-${#CLUSTERS[@]}]: " CHOICE

  if [[ ! "${CHOICE}" =~ ^[0-9]+$ ]] || (( CHOICE < 0 || CHOICE > ${#CLUSTERS[@]} )); then
    echo "Invalid selection." >&2
    exit 1
  fi

  if [[ "${CHOICE}" -eq 0 ]]; then
    echo "Cancelled -- nothing was deleted."
    exit 0
  fi

  TARGET="${CLUSTERS[$((CHOICE - 1))]}"
fi

echo
echo "You selected: ${TARGET}"
kubectl get nodes --context "k3d-${TARGET}" 2>/dev/null || true
echo
read -r -p "Type the cluster name to confirm deletion of '${TARGET}': " CONFIRM

if [[ "${CONFIRM}" != "${TARGET}" ]]; then
  echo "Name did not match -- aborting. Nothing was deleted."
  exit 1
fi

echo "Deleting cluster '${TARGET}'..."
k3d cluster delete "${TARGET}"
echo "Done."

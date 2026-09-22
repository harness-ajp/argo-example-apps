#!/usr/bin/env bash
#
# create-k3d-cluster.sh
#
# Creates a k3d (k3s-in-Docker) cluster: 1 server node + 4 agent nodes.
# Maps host ports 80/443 to the cluster's built-in load balancer so LAN
# devices can reach ingress (e.g. via your bespin.net wildcard DNS entry
# pointed at this Mac's IP), just like your existing Rancher Desktop setup.
#
# If K3S_IMAGE isn't set and you're running this in a terminal, you'll be
# prompted with a menu of recent k3s releases (pulled live from GitHub,
# grouped into Stable / Pre-release-RC) to pick from -- pick 0 to just use
# k3d's own default image. Automated/non-interactive runs skip the prompt.
#
# Requirements:
#   - k3d installed (brew install k3d)
#   - curl and python3 (both ship with macOS) -- only needed for the
#     interactive version picker; the script still works without network
#     access if you skip that prompt (choose 0) or pin K3S_IMAGE yourself.
#   - A working Docker Engine API endpoint. If you're using Rancher Desktop
#     as the backend, its container engine must be set to "dockerd (moby)"
#     in Preferences > Container Engine -- k3d talks to the real Docker API
#     and will NOT work against Rancher Desktop's containerd/nerdctl mode.
#
# Usage:
#   ./create-k3d-cluster.sh [cluster-name]
#
#   CLUSTER_NAME=my-cluster ./create-k3d-cluster.sh
#   K3S_IMAGE=rancher/k3s:v1.28.5-k3s1 ./create-k3d-cluster.sh   # skip the prompt, pin directly
#
set -euo pipefail

# ---- Config (override via env vars or the positional arg) -----------------
CLUSTER_NAME="${1:-${CLUSTER_NAME:-homelab}}"
SERVERS="${SERVERS:-1}"
AGENTS="${AGENTS:-4}"
API_PORT="${API_PORT:-127.0.0.1:6550}"   # explicit host avoids k3d writing a bare "0.0.0.0" server address
                                          # into kubeconfig, which isn't connectable and causes an EOF/
                                          # "unable to connect" error. Port 6550 avoids clashing with
                                          # Rancher Desktop's own 6443 API if it's still running.
HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="${HTTPS_PORT:-443}"
TIMEOUT="${TIMEOUT:-120s}"
K3S_IMAGE="${K3S_IMAGE:-}"   # optional pin, e.g. "rancher/k3s:v1.28.5-k3s1"
                             # leave unset and run interactively to be prompted
                             # with a version picker instead (see below).
STABLE_COUNT="${STABLE_COUNT:-15}"       # how many stable releases to list
PRERELEASE_COUNT="${PRERELEASE_COUNT:-6}" # how many RC/pre-releases to list

# ---- Preflight checks -------------------------------------------------------
if ! command -v k3d >/dev/null 2>&1; then
  echo "ERROR: k3d is not installed. Install it with: brew install k3d" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed. Install it with: brew install kubectl" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot reach the Docker Engine API. If you're on Rancher Desktop," >&2
  echo "       confirm Preferences > Container Engine is set to 'dockerd (moby)'," >&2
  echo "       and that Rancher Desktop is running." >&2
  exit 1
fi

# ---- Handle an existing cluster of the same name ---------------------------
if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
  read -r -p "Cluster '${CLUSTER_NAME}' already exists. Delete and recreate it? [y/N] " REPLY
  if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
    k3d cluster delete "${CLUSTER_NAME}"
  else
    echo "Aborting -- leaving existing cluster '${CLUSTER_NAME}' untouched."
    exit 1
  fi
fi

# ---- Auto-pick free ports for anything already taken ----------------------
# API_PORT/HTTP_PORT/HTTPS_PORT all default to fixed values, so a second
# cluster created while a first one is still running would otherwise collide
# on all three. Instead of failing, scan upward from each requested port and
# take the first one that's actually free -- this naturally reuses a "hole"
# left by a deleted cluster (e.g. if 6550 and 6552 are taken but 6551 was
# freed up, 6551 is what gets picked) rather than just going to the top.
port_in_use() {
  local port="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
  local rc=$?
  exec 3>&- 2>/dev/null || true
  return "${rc}"
}

find_free_port() {
  local candidate="$1"
  local tries="${2:-200}"
  local n=0
  while (( n < tries )); do
    if ! port_in_use "${candidate}"; then
      echo "${candidate}"
      return 0
    fi
    candidate=$((candidate + 1))
    n=$((n + 1))
  done
  return 1
}

API_HOST="${API_PORT%:*}"
API_PORT_REQUESTED="${API_PORT##*:}"
API_PORT_NUM="$(find_free_port "${API_PORT_REQUESTED}")" \
  || { echo "ERROR: no free port found near ${API_PORT_REQUESTED} for the API server." >&2; exit 1; }
API_PORT="${API_HOST}:${API_PORT_NUM}"

HTTP_PORT_REQUESTED="${HTTP_PORT}"
HTTP_PORT="$(find_free_port "${HTTP_PORT_REQUESTED}")" \
  || { echo "ERROR: no free port found near ${HTTP_PORT_REQUESTED} for HTTP ingress." >&2; exit 1; }

HTTPS_PORT_REQUESTED="${HTTPS_PORT}"
HTTPS_PORT="$(find_free_port "${HTTPS_PORT_REQUESTED}")" \
  || { echo "ERROR: no free port found near ${HTTPS_PORT_REQUESTED} for HTTPS ingress." >&2; exit 1; }

[[ "${API_PORT_NUM}" != "${API_PORT_REQUESTED}" ]] && echo "Note: API port ${API_PORT_REQUESTED} was in use -- using ${API_PORT_NUM} instead."
[[ "${HTTP_PORT}" != "${HTTP_PORT_REQUESTED}" ]] && echo "Note: HTTP port ${HTTP_PORT_REQUESTED} was in use -- using ${HTTP_PORT} instead."
[[ "${HTTPS_PORT}" != "${HTTPS_PORT_REQUESTED}" ]] && echo "Note: HTTPS port ${HTTPS_PORT_REQUESTED} was in use -- using ${HTTPS_PORT} instead."

# ---- Interactively pick a k3s version, if none was pinned -----------------
# Only prompts when running attached to a terminal, so scripted/automated
# runs (K3S_IMAGE unset, stdin not a tty) silently fall back to k3d's
# default image instead of hanging on a read.
if [[ -z "${K3S_IMAGE}" && -t 0 ]]; then
  echo "Fetching available k3s versions from GitHub..."
  RELEASES_JSON="$(curl -sf -H "User-Agent: create-k3d-cluster-script" \
    "https://api.github.com/repos/k3s-io/k3s/releases?per_page=100" || true)"

  MENU_TAGS=()
  MENU_SECTIONS=()
  if [[ -n "${RELEASES_JSON}" ]]; then
    while IFS='|' read -r SECTION TAG; do
      [[ -n "${TAG}" ]] || continue
      MENU_SECTIONS+=("${SECTION}")
      MENU_TAGS+=("${TAG}")
    done < <(printf '%s' "${RELEASES_JSON}" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
stable = [r['tag_name'] for r in data if not r.get('prerelease')]
pre = [r['tag_name'] for r in data if r.get('prerelease')]
for t in stable[:${STABLE_COUNT}]:
    print('STABLE|' + t.replace('+', '-'))
for t in pre[:${PRERELEASE_COUNT}]:
    print('PRE|' + t.replace('+', '-'))
" 2>/dev/null)
  fi

  if [[ ${#MENU_TAGS[@]} -gt 0 ]]; then
    echo
    echo "Available k3s versions:"
    echo
    CURRENT_SECTION=""
    for i in "${!MENU_TAGS[@]}"; do
      if [[ "${MENU_SECTIONS[$i]}" != "${CURRENT_SECTION}" ]]; then
        if [[ "${MENU_SECTIONS[$i]}" == "STABLE" ]]; then
          echo "-- Stable --"
        else
          echo "-- Pre-release / RC --"
        fi
        CURRENT_SECTION="${MENU_SECTIONS[$i]}"
      fi
      printf "  %2d) %s\n" "$((i + 1))" "${MENU_TAGS[$i]}"
    done
    echo "   0) Use k3d's default (no version pin)"
    echo

    read -r -p "Select a k3s version [0-${#MENU_TAGS[@]}]: " VERSION_CHOICE

    if [[ "${VERSION_CHOICE}" =~ ^[0-9]+$ ]] && (( VERSION_CHOICE >= 1 && VERSION_CHOICE <= ${#MENU_TAGS[@]} )); then
      K3S_IMAGE="rancher/k3s:${MENU_TAGS[$((VERSION_CHOICE - 1))]}"
    elif [[ "${VERSION_CHOICE}" != "0" ]]; then
      echo "Invalid selection -- using k3d's default image." >&2
    fi
  else
    echo "Could not fetch/parse the k3s release list (offline, or GitHub" >&2
    echo "unreachable/rate-limited) -- continuing with k3d's default image." >&2
  fi
fi

# ---- Create the cluster -----------------------------------------------------
CREATE_ARGS=(
  "${CLUSTER_NAME}"
  --servers "${SERVERS}"
  --agents "${AGENTS}"
  --api-port "${API_PORT}"
  -p "${HTTP_PORT}:80@loadbalancer"
  -p "${HTTPS_PORT}:443@loadbalancer"
  --wait
  --timeout "${TIMEOUT}"
)
if [[ -n "${K3S_IMAGE}" ]]; then
  CREATE_ARGS+=(--image "${K3S_IMAGE}")
fi

echo "Creating k3d cluster '${CLUSTER_NAME}' (${SERVERS} server + ${AGENTS} agents)${K3S_IMAGE:+, image ${K3S_IMAGE}}..."

k3d cluster create "${CREATE_ARGS[@]}"

# ---- Force a reachable server address into the kubeconfig -----------------
# Belt-and-suspenders: in some environments k3d writes "0.0.0.0" into the
# kubeconfig's "server:" field regardless of the host given to --api-port
# above (0.0.0.0 is a bind-wildcard, not something a client can connect
# *to*, and produces the "unable to connect to the server: EOF" error).
# Force it to something actually reachable rather than trusting k3d got it
# right. (API_PORT_NUM was already computed above during the port check.)
kubectl config set-cluster "k3d-${CLUSTER_NAME}" --server="https://127.0.0.1:${API_PORT_NUM}"

# ---- Verify ------------------------------------------------------------------
kubectl config use-context "k3d-${CLUSTER_NAME}"

# ---- Label agent nodes as "worker" -----------------------------------------
# k3s labels server nodes with node-role.kubernetes.io/control-plane (and
# master) automatically, but leaves agent nodes with no role label at all --
# they'd show ROLES=<none> in `kubectl get nodes`. Tag anything that isn't a
# control-plane node as "worker" so the role is actually visible.
AGENT_NODE_NAMES="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}')"
if [[ -n "${AGENT_NODE_NAMES}" ]]; then
  # shellcheck disable=SC2086  # intentional word-splitting: one node name per arg
  kubectl label node ${AGENT_NODE_NAMES} node-role.kubernetes.io/worker= --overwrite >/dev/null
fi

echo
echo "Cluster '${CLUSTER_NAME}' is up. Nodes:"
kubectl get nodes -o wide

echo
echo "Context set to k3d-${CLUSTER_NAME}. Ingress on this cluster's load balancer"
echo "is reachable on host ports ${HTTP_PORT}/${HTTPS_PORT}."
if [[ "${HTTP_PORT}" == "80" && "${HTTPS_PORT}" == "443" ]]; then
  echo "Point your *.bespin.net wildcard DNS record at this Mac's LAN IP to reach"
  echo "it from other devices, same as your current setup."
else
  echo "These are non-standard ports (80/443 were already taken by another"
  echo "cluster), so your *.bespin.net wildcard DNS record won't reach this one --"
  echo "it's only reachable directly at https://<this-mac-ip>:${HTTPS_PORT}."
fi
echo
echo "To tear it down later: k3d cluster delete ${CLUSTER_NAME}"

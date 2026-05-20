#!/usr/bin/env bash
# Tear down an instance previously added with ./scripts/add-instance.sh.
#
# Usage:
#   ./scripts/remove-instance.sh <N> [--purge] [--yes]
#
#   --purge    also delete instances/instance-N/ data (otherwise kept).
#   --yes      skip the interactive confirmation prompt.
#
# Always:
#   - Stops + removes the agent and webui containers (if running)
#   - Removes the named volume hermes-agent-src-N
#   - Removes the managed YAML blocks from docker-compose.yml
#   - Removes HERMES_WEBUI_PASSWORD_N from .env

source "$(dirname "$0")/lib/common.sh"

require_cmd python3 awk
# `docker` is optional: when missing we still tear down the compose/.env/
# data side of the instance and just skip the container/volume cleanup.
HAVE_DOCKER=1
command -v docker >/dev/null 2>&1 || { HAVE_DOCKER=0; warn "docker not in PATH — will skip container and volume cleanup"; }

PURGE=0
YES=0
N=""

while (( $# )); do
  case "$1" in
    --purge) PURGE=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help)
      sed -n '2,11p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$N" ]]; then
        N="$1"
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[[ -n "$N" ]] || die "usage: $0 <N> [--purge] [--yes]"
validate_instance_number "$N"

if ! instance_block_exists "$N" && [[ ! -d "$(instance_dir "$N")" ]]; then
  warn "instance-${N} is not present in docker-compose.yml and has no data directory — nothing to do"
  exit 0
fi

if (( YES == 0 )); then
  printf 'About to remove instance-%s. Containers will be stopped. Continue? [y/N] ' "$N"
  read -r ans
  [[ "$ans" =~ ^[yY]$ ]] || die "aborted"
fi

# --- containers + volume ----------------------------------------------------
if (( HAVE_DOCKER == 1 )); then
  log "stopping containers for instance-${N}"
  (cd "$PROJECT_ROOT" && docker compose rm -fsv "hermes-webui-${N}" "hermes-agent-${N}" 2>/dev/null) || true

  # Compose prefixes the volume name with the project name; try both forms.
  project_name="$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | sed 's/^_*//;s/_*$//')"
  for vol in "${project_name}_hermes-agent-src-${N}" "hermes-agent-src-${N}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
      docker volume rm "$vol" >/dev/null && log "removed docker volume $vol"
    fi
  done
else
  warn "skipping container/volume cleanup (docker not available)"
fi

# --- docker-compose.yml -----------------------------------------------------
delete_between_markers "$COMPOSE_FILE" ">>> instance-${N} BEGIN >>>" "<<< instance-${N} END <<<"
delete_between_markers "$COMPOSE_FILE" ">>> volume-${N} BEGIN >>>"   "<<< volume-${N} END <<<"
log "removed instance-${N} blocks from docker-compose.yml"

# --- .env -------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
  tmp="$(mktemp)"
  awk -v n="$N" '
    $0 ~ "^HERMES_WEBUI_PASSWORD_" n "=" { next }
    { print }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
  log "removed HERMES_WEBUI_PASSWORD_${N} from .env"
fi

# --- data directory --------------------------------------------------------
if (( PURGE == 1 )); then
  if [[ -d "$(instance_dir "$N")" ]]; then
    rm -rf "$(instance_dir "$N")"
    log "deleted instances/instance-${N}/"
  fi
else
  log "data preserved at instances/instance-${N}/ (use --purge to delete)"
fi

log "instance-${N} removed."

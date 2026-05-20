#!/usr/bin/env bash
# Append a new (hermes-agent + hermes-webui) instance to the stack.
#
# Usage:
#   ./scripts/add-instance.sh <N> <webui-password>
#
# What it does:
#   1. Creates instances/instance-N/{hermes-home,workspace}/
#   2. Renders config.yaml from config/hermes-config.yaml template
#   3. Appends HERMES_WEBUI_PASSWORD_N=... to .env (if missing)
#   4. Inserts the agent+webui service block and the named volume into
#      docker-compose.yml between the managed-section markers.
#
# Idempotent: if the instance already exists, exits with a clear error.

source "$(dirname "$0")/lib/common.sh"

require_cmd python3

if (( $# != 2 )); then
  cat <<USAGE >&2
usage: $0 <instance-number> <webui-password>

  instance-number   positive integer (1..999)
  webui-password    password used to log into the WebUI for this instance

example:
  $0 3 's3cret-pa55'
USAGE
  exit 2
fi

N="$1"
PASSWORD="$2"

validate_instance_number "$N"

# Reject characters that would corrupt the single-quoted env entry.
if [[ "$PASSWORD" == *$'\n'* ]]; then
  die "password must not contain newlines"
fi
if [[ -z "$PASSWORD" ]]; then
  die "password must not be empty"
fi

if instance_block_exists "$N"; then
  die "instance-${N} already exists in docker-compose.yml — remove it first with ./scripts/remove-instance.sh ${N}"
fi

[[ -f "$ENV_FILE" ]] || die ".env not found — run ./scripts/bootstrap.sh first"
[[ -f "$COMPOSE_FILE" ]] || die "docker-compose.yml not found"

# --- 1. Filesystem layout ---------------------------------------------------
mkdir -p "$(instance_home_dir "$N")" "$(instance_work_dir "$N")"
log "created instances/instance-${N}/{hermes-home,workspace}/"

# --- 2. .env entry ----------------------------------------------------------
# Escape ' in password for single-quoted shell literal.
escaped_pw="${PASSWORD//\'/\'\\\'\'}"
env_line="HERMES_WEBUI_PASSWORD_${N}='${escaped_pw}'"

if grep -q "^HERMES_WEBUI_PASSWORD_${N}=" "$ENV_FILE"; then
  warn "HERMES_WEBUI_PASSWORD_${N} already present in .env — leaving existing value untouched"
else
  # Ensure a trailing newline before appending.
  [[ -s "$ENV_FILE" && -z "$(tail -c1 "$ENV_FILE")" ]] || printf '\n' >> "$ENV_FILE"
  printf '%s\n' "$env_line" >> "$ENV_FILE"
  # Re-assert owner-only permissions in case .env was created by hand.
  chmod 600 "$ENV_FILE"
  log "added HERMES_WEBUI_PASSWORD_${N} to .env"
fi

# --- 3. config.yaml ---------------------------------------------------------
render_instance_config "$N"

# --- 4. docker-compose.yml --------------------------------------------------
volume_block="$(render_volume_block "$N")"
instance_block="$(render_instance_block "$N")"

insert_before_marker "$COMPOSE_FILE" "$VOLUMES_END_MARKER" "$volume_block"
insert_before_marker "$COMPOSE_FILE" "$INSTANCES_END_MARKER" "$instance_block"
log "patched docker-compose.yml with instance-${N}"

webui_p="$(webui_port "$N")"
agent_p="$(agent_port "$N")"

cat <<DONE

Instance ${N} added.

  WebUI:           http://localhost:${webui_p}
  Agent gateway:   http://localhost:${agent_p}
  Data directory:  instances/instance-${N}/

Next:
  docker compose up -d hermes-agent-${N} hermes-webui-${N}

DONE

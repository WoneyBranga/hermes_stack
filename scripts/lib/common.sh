#!/usr/bin/env bash
# Shared helpers for the hermes stack management scripts.
# Source this from every script: `source "$(dirname "$0")/lib/common.sh"`

set -euo pipefail

# Resolve the project root regardless of where the script is invoked from.
# Each caller sources this file from `scripts/lib/`, so root is two dirs up.
# shellcheck disable=SC2155
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
# shellcheck disable=SC2155
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
ENV_EXAMPLE_FILE="${PROJECT_ROOT}/.env.example"
CONFIG_TEMPLATE="${PROJECT_ROOT}/config/hermes-config.yaml"
INSTANCES_DIR="${PROJECT_ROOT}/instances"
SHARED_SKILLS_DIR="${PROJECT_ROOT}/shared-skills"
BACKUPS_DIR="${PROJECT_ROOT}/backups"

# Markers for the managed sections inside docker-compose.yml.
INSTANCES_BEGIN_MARKER="# === BEGIN MANAGED INSTANCES ==="
INSTANCES_END_MARKER="# === END MANAGED INSTANCES ==="
VOLUMES_BEGIN_MARKER="# === BEGIN MANAGED VOLUMES ==="
VOLUMES_END_MARKER="# === END MANAGED VOLUMES ==="

log()   { printf '\033[1;36m[hermes]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[err ]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

# Validate that N is a positive integer (1..999).
validate_instance_number() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "instance number must be a positive integer (got: '${n}')"
  (( n >= 1 && n <= 999 )) || die "instance number out of range 1..999 (got: ${n})"
}

# Compute deterministic host ports for instance N.
webui_port() { echo $((8786 + $1)); }
agent_port() { echo $((8641 + $1)); }

instance_dir()       { echo "${INSTANCES_DIR}/instance-$1"; }
instance_home_dir()  { echo "${INSTANCES_DIR}/instance-$1/hermes-home"; }
instance_work_dir()  { echo "${INSTANCES_DIR}/instance-$1/workspace"; }
instance_skills_dir(){ echo "${INSTANCES_DIR}/instance-$1/hermes-home/skills"; }

# Check whether a managed instance N already exists in the compose file.
instance_block_exists() {
  local n="$1"
  grep -q "^\s*# >>> instance-${n} BEGIN >>>" "$COMPOSE_FILE"
}

# Render the per-instance services block (printed to stdout).
render_instance_block() {
  local n="$1"
  local webui_p agent_p
  webui_p="$(webui_port "$n")"
  agent_p="$(agent_port "$n")"
  cat <<EOF
  # >>> instance-${n} BEGIN >>>
  hermes-agent-${n}:
    <<: *agent-defaults
    container_name: hermes-agent-${n}
    hostname: hermes-agent-${n}
    ports:
      - "127.0.0.1:${agent_p}:8642"
    volumes:
      - ./instances/instance-${n}/hermes-home:/opt/data
      - hermes-agent-src-${n}:/opt/hermes
    environment:
      - HERMES_HOME=/opt/data
      - HERMES_UID=\${HOST_UID:-501}
      - HERMES_GID=\${HOST_GID:-20}
      - LITELLM_BASE_URL=\${LITELLM_BASE_URL}
      - LITELLM_API_KEY=\${LITELLM_API_KEY}
      - HERMES_DEFAULT_MODEL=\${HERMES_DEFAULT_MODEL}
      - OPENAI_BASE_URL=\${LITELLM_BASE_URL}
      - OPENAI_API_KEY=\${LITELLM_API_KEY}

  hermes-webui-${n}:
    <<: *webui-defaults
    container_name: hermes-webui-${n}
    hostname: hermes-webui-${n}
    depends_on:
      - hermes-agent-${n}
    ports:
      - "${webui_p}:8787"
    volumes:
      - ./instances/instance-${n}/hermes-home:/home/hermeswebui/.hermes
      - hermes-agent-src-${n}:/home/hermeswebui/.hermes/hermes-agent:ro
      - ./instances/instance-${n}/workspace:/workspace
    environment:
      - HERMES_WEBUI_HOST=0.0.0.0
      - HERMES_WEBUI_PORT=8787
      - HERMES_WEBUI_STATE_DIR=/home/hermeswebui/.hermes/webui
      - HERMES_WEBUI_PASSWORD=\${HERMES_WEBUI_PASSWORD_${n}:?HERMES_WEBUI_PASSWORD_${n} is required}
      - WANTED_UID=\${HOST_UID:-501}
      - WANTED_GID=\${HOST_GID:-20}
  # <<< instance-${n} END <<<
EOF
}

render_volume_block() {
  local n="$1"
  cat <<EOF
  # >>> volume-${n} BEGIN >>>
  hermes-agent-src-${n}:
  # <<< volume-${n} END <<<
EOF
}

# Insert TEXT into FILE on the line *before* a sentinel line (matched by
# fixed-string equality after trimming leading whitespace). Implemented
# in python so multi-line TEXT works on every awk flavour (BSD awk in
# particular rejects newlines inside `-v var=...`).
insert_before_marker() {
  local file="$1" marker="$2" text="$3"
  HERMES_FILE="$file" HERMES_MARKER="$marker" HERMES_TEXT="$text" \
    python3 - <<'PY'
import os
path   = os.environ["HERMES_FILE"]
marker = os.environ["HERMES_MARKER"]
text   = os.environ["HERMES_TEXT"]
with open(path) as f:
    lines = f.readlines()
out = []
for ln in lines:
    if ln.lstrip().rstrip("\n") == marker:
        if not text.endswith("\n"):
            text += "\n"
        out.append(text)
    out.append(ln)
with open(path, "w") as f:
    f.writelines(out)
PY
}

# Delete the inclusive range of lines between BEGIN_PAT and END_PAT
# (each matched as a fixed substring) from FILE.
delete_between_markers() {
  local file="$1" begin_pat="$2" end_pat="$3"
  HERMES_FILE="$file" HERMES_BEGIN="$begin_pat" HERMES_END="$end_pat" \
    python3 - <<'PY'
import os
path  = os.environ["HERMES_FILE"]
begin = os.environ["HERMES_BEGIN"]
end   = os.environ["HERMES_END"]
with open(path) as f:
    lines = f.readlines()
out = []
skip = False
for ln in lines:
    if not skip and begin in ln:
        skip = True
        continue
    if skip and end in ln:
        skip = False
        continue
    if not skip:
        out.append(ln)
with open(path, "w") as f:
    f.writelines(out)
PY
}

# Render the config.yaml template into instance N's hermes-home,
# substituting placeholders from .env. Skips if the file already exists
# unless FORCE=1 is set in the environment.
render_instance_config() {
  local n="$1"
  local target="$(instance_home_dir "$n")/config.yaml"
  if [[ -f "$target" && "${FORCE:-0}" != "1" ]]; then
    log "config.yaml already present for instance-${n} — skipping (FORCE=1 to overwrite)"
    return 0
  fi
  [[ -f "$ENV_FILE" ]] || die ".env not found — copy .env.example to .env first"
  [[ -f "$CONFIG_TEMPLATE" ]] || die "template missing: $CONFIG_TEMPLATE"

  mkdir -p "$(dirname "$target")"
  # Substitution is done in python so we can:
  #   * parse .env without sourcing it (don't eval user-controlled shell)
  #   * strip surrounding quotes around values (a common .env convention)
  #   * json.dumps each value so quotes/backslashes/etc. in keys or URLs
  #     never break the resulting YAML (the template now uses bare
  #     placeholders — json.dumps supplies its own quoting).
  HERMES_ENV_FILE="$ENV_FILE" \
  python3 - "$CONFIG_TEMPLATE" "$target" <<'PY'
import json, os, re, sys

env_path = os.environ["HERMES_ENV_FILE"]
src, dst = sys.argv[1], sys.argv[2]

def strip_quotes(v):
    v = v.rstrip("\r\n")
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v

wanted = ("HERMES_DEFAULT_MODEL", "LITELLM_API_KEY", "LITELLM_BASE_URL")
values = {}
with open(env_path) as f:
    for line in f:
        m = re.match(r"^([A-Z_][A-Z0-9_]*)=(.*)$", line)
        if m and m.group(1) in wanted:
            values[m.group(1)] = strip_quotes(m.group(2))

missing = [k for k in ("HERMES_DEFAULT_MODEL", "LITELLM_BASE_URL") if not values.get(k)]
if missing:
    sys.exit("missing required key(s) in .env: " + ", ".join(missing))

with open(src) as f:
    body = f.read()
body = body.replace("__HERMES_DEFAULT_MODEL__", json.dumps(values["HERMES_DEFAULT_MODEL"]))
body = body.replace("__LITELLM_API_KEY__",      json.dumps(values.get("LITELLM_API_KEY", "")))
body = body.replace("__LITELLM_BASE_URL__",     json.dumps(values["LITELLM_BASE_URL"]))
with open(dst, "w") as f:
    f.write(body)
PY
  log "rendered $target"
}

# Enumerate every instance number present on disk (from instances/instance-*/).
list_instance_numbers() {
  local d n restore_nullglob
  # `shopt -p` returns 1 when the option is off, so guard with `|| true`
  # to keep `set -e` happy. Preserves the caller's nullglob state.
  restore_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob
  for d in "${INSTANCES_DIR}"/instance-*/; do
    n="${d%/}"
    n="${n##*/instance-}"
    [[ "$n" =~ ^[0-9]+$ ]] && echo "$n"
  done | sort -n
  eval "$restore_nullglob"
}

# Portable replacement for `mapfile -t ARR < <(cmd)` — works on bash 3.2
# (the default on macOS). Reads stdin line-by-line into the named array.
# Usage:  read_lines_into ARR < <(cmd)
read_lines_into() {
  local __name="$1" __line
  eval "$__name=()"
  while IFS= read -r __line; do
    eval "$__name+=( \"\$__line\" )"
  done
}

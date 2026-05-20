#!/usr/bin/env bash
# Bootstrap the multi-hermes stack:
#   - ensure .env exists (copy from .env.example if missing)
#   - render config.yaml for every existing instances/instance-N/ dir
#
# Safe to re-run; existing config.yaml files are preserved unless FORCE=1.
#
# Usage:
#   ./scripts/bootstrap.sh            # render missing config files
#   FORCE=1 ./scripts/bootstrap.sh    # overwrite existing config files

source "$(dirname "$0")/lib/common.sh"

require_cmd python3

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_EXAMPLE_FILE" ]]; then
    die ".env.example not found — cannot bootstrap"
  fi
  cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
  # .env carries per-instance WebUI passwords; keep it owner-readable only.
  chmod 600 "$ENV_FILE"
  warn "created .env from .env.example — edit it before running 'docker compose up'"
fi

read_lines_into instances < <(list_instance_numbers)
if (( ${#instances[@]} == 0 )); then
  warn "no instances found under ${INSTANCES_DIR}/ — nothing to render"
  exit 0
fi

for n in "${instances[@]}"; do
  mkdir -p "$(instance_home_dir "$n")" "$(instance_work_dir "$n")"
  render_instance_config "$n"
done

log "bootstrap complete (${#instances[@]} instance(s) processed)"

#!/usr/bin/env bash
# Tabular overview of every instance discovered in instances/.
#
# Usage:
#   ./scripts/status.sh

source "$(dirname "$0")/lib/common.sh"

# Graceful degradation: if docker is not installed we still list the
# instances discovered on disk, just with an unknown container state.
HAVE_DOCKER=1
if ! command -v docker >/dev/null 2>&1; then
  HAVE_DOCKER=0
  warn "docker not found in PATH — container state will be reported as 'unknown'"
fi

read_lines_into instances < <(list_instance_numbers)

if (( ${#instances[@]} == 0 )); then
  warn "no instances under ${INSTANCES_DIR}/"
  exit 0
fi

# Header
printf '%-4s  %-18s  %-10s  %-32s  %-32s\n' \
  "N" "AGENT STATE" "WEBUI PORT" "WEBUI URL" "DATA DIR"
printf '%-4s  %-18s  %-10s  %-32s  %-32s\n' \
  "----" "------------------" "----------" "--------------------------------" "--------------------------------"

for n in "${instances[@]}"; do
  agent_name="hermes-agent-${n}"
  webui_name="hermes-webui-${n}"
  webui_p="$(webui_port "$n")"

  if (( HAVE_DOCKER == 1 )); then
    agent_state="$(docker inspect -f '{{.State.Status}}' "$agent_name" 2>/dev/null || echo 'not created')"
    webui_state="$(docker inspect -f '{{.State.Status}}' "$webui_name" 2>/dev/null || echo 'not created')"
  else
    agent_state="unknown"; webui_state="unknown"
  fi
  combined="${agent_state}/${webui_state}"

  data_dir="instances/instance-${n}/"
  url="http://localhost:${webui_p}"

  printf '%-4s  %-18s  %-10s  %-32s  %-32s\n' \
    "$n" "$combined" "$webui_p" "$url" "$data_dir"
done

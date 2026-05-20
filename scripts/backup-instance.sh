#!/usr/bin/env bash
# Tar up an instance's data directory.
#
# Usage:
#   ./scripts/backup-instance.sh <N>
#
# Output: backups/instance-<N>-<UTC-timestamp>.tar.gz
#
# Notes:
#   - We DO NOT stop the containers before archiving. SQLite/state files
#     can in theory be mid-write. For a fully consistent backup, stop
#     the instance first:
#         docker compose stop hermes-agent-<N> hermes-webui-<N>
#         ./scripts/backup-instance.sh <N>
#         docker compose start hermes-agent-<N> hermes-webui-<N>

source "$(dirname "$0")/lib/common.sh"

require_cmd tar

if (( $# != 1 )); then
  echo "usage: $0 <instance-number>" >&2
  exit 2
fi

N="$1"
validate_instance_number "$N"

src="$(instance_dir "$N")"
[[ -d "$src" ]] || die "no data directory at $src"

mkdir -p "$BACKUPS_DIR"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="${BACKUPS_DIR}/instance-${N}-${ts}.tar.gz"

# Archive from PROJECT_ROOT so the tarball's internal paths start with
# `instances/instance-N/` — convenient for restoring in place.
( cd "$PROJECT_ROOT" && tar -czf "$out" "instances/instance-${N}" )

size="$(du -h "$out" | cut -f1)"
log "wrote $out ($size)"

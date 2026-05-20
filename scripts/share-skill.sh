#!/usr/bin/env bash
# Copy a skill directory between instances or in/out of shared-skills/.
#
# Usage:
#   ./scripts/share-skill.sh <skill-name> [from] [to]
#
#   <skill-name>   directory name under <src>/hermes-home/skills/ (or under shared-skills/)
#   from           source: instance number, or "shared" (default: "shared")
#   to             destination: instance number, "all", or "shared" (default: "all")
#
# Examples:
#   # Copy from shared-skills/ into every instance:
#   ./scripts/share-skill.sh git-helper
#
#   # Promote a skill from instance 2 into shared-skills/:
#   ./scripts/share-skill.sh my-skill 2 shared
#
#   # Copy from instance 1 → instance 3:
#   ./scripts/share-skill.sh my-skill 1 3
#
#   # Broadcast a skill from instance 1 to all other instances:
#   ./scripts/share-skill.sh my-skill 1 all

source "$(dirname "$0")/lib/common.sh"

if (( $# < 1 || $# > 3 )); then
  sed -n '2,22p' "$0" >&2
  exit 2
fi

SKILL="$1"
FROM="${2:-shared}"
TO="${3:-all}"

[[ "$SKILL" == */* || "$SKILL" == "" || "$SKILL" == "." || "$SKILL" == ".." ]] && \
  die "invalid skill name: '$SKILL'"

# Resolve source path
if [[ "$FROM" == "shared" ]]; then
  src="${SHARED_SKILLS_DIR}/${SKILL}"
else
  validate_instance_number "$FROM"
  src="$(instance_skills_dir "$FROM")/${SKILL}"
fi
[[ -d "$src" ]] || die "source skill not found: $src"

# Resolve destination(s)
declare -a destinations=()
if [[ "$TO" == "shared" ]]; then
  destinations+=("${SHARED_SKILLS_DIR}/${SKILL}")
elif [[ "$TO" == "all" ]]; then
  read_lines_into all < <(list_instance_numbers)
  for n in "${all[@]}"; do
    # Don't copy a source instance onto itself.
    [[ "$FROM" != "shared" && "$n" == "$FROM" ]] && continue
    destinations+=("$(instance_skills_dir "$n")/${SKILL}")
  done
else
  validate_instance_number "$TO"
  destinations+=("$(instance_skills_dir "$TO")/${SKILL}")
fi

if (( ${#destinations[@]} == 0 )); then
  warn "no destinations resolved — nothing to copy"
  exit 0
fi

for dst in "${destinations[@]}"; do
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$dst" ]]; then
    warn "overwriting existing $dst"
    rm -rf "$dst"
  fi
  # cp -R preserves the skill's internal layout. We deliberately don't
  # preserve owner since the target hermes-home may be owned by a
  # different UID under each instance.
  cp -R "$src" "$dst"
  log "copied $SKILL → $dst"
done

log "shared $SKILL to ${#destinations[@]} destination(s)"

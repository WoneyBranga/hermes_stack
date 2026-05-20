# Skill Sharing

Skills are the core extensibility mechanism of hermes-agent. Each instance has its own skill library, but the `share-skill.sh` script makes it easy to promote a skill from one instance to another or to all instances.

## Where Skills Live

Each instance stores its skills inside its `hermes-home`:

```
instances/instance-N/hermes-home/skills/
  my-skill/
    skill.md        # skill instructions / system prompt
    tool.py         # optional tool implementation
    ...
```

You can browse, edit, or add skills directly from the host filesystem — no container access needed.

## The Shared Skills Directory

`shared-skills/` at the project root is a **host-side staging area** managed by `share-skill.sh`. It is not mounted inside containers — all skill distribution happens at the host filesystem level, which avoids permission conflicts with the container init process.

Use `share-skill.sh` to copy a skill from an instance (or `shared-skills/`) to wherever it is needed. The running containers pick up the new skill automatically since `instances/instance-N/hermes-home/` is a bind mount.

## Sharing a Skill

```bash
./scripts/share-skill.sh <skill-name> [from] [to|all]
```

| Argument | Values | Default |
|----------|--------|---------|
| `skill-name` | Name of the skill directory | required |
| `from` | Instance number or `shared` | `shared` |
| `to` | Instance number, `all`, or `shared` | `all` |

### Examples

```bash
# Share a skill from instance 1 to all other instances
./scripts/share-skill.sh my-skill 1 all

# Copy from instance 2 to instance 5 only
./scripts/share-skill.sh my-skill 2 5

# Promote a skill to the shared-skills/ library (read-only baseline for all)
./scripts/share-skill.sh my-skill 3 shared

# Copy from shared-skills/ to a specific instance
./scripts/share-skill.sh my-skill shared 4
```

## Recommended Workflow

1. **Develop** a skill inside one instance (`instances/instance-1/hermes-home/skills/my-skill/`)
2. **Test** it by interacting with that instance's webui
3. **Share** to all once it is stable: `./scripts/share-skill.sh my-skill 1 all`
4. **Optionally stage** in `shared-skills/` as a host-side baseline: `./scripts/share-skill.sh my-skill 1 shared`

## Security Notes

- Skill names are validated: `/`, `..`, empty strings, and `.` are rejected to prevent path traversal.
- Skills copied between instances are full directory copies — all files inside the skill directory are included.
- Editing a skill in one instance after sharing does **not** automatically propagate the update; run `share-skill.sh` again.

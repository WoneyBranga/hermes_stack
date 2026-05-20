# Hermes Multi-Instance Stack

A platform for running multiple independent [hermes-agent](https://github.com/NousResearch/hermes-agent) instances, each with its own [hermes-webui](https://github.com/nesquena/hermes-webui) frontend. All agents route through a shared [LiteLLM](https://github.com/BerriAI/litellm) proxy, giving you centralised LLM control over every session.

## Architecture

```
Browser → http://localhost:8787  ──► hermes-webui-1 ──┐
Browser → http://localhost:8788  ──► hermes-webui-2 ──┤  shared hermes-net
Browser → http://localhost:878N  ──► hermes-webui-N ──┤
                                                        ▼
                                  hermes-agent-1/2/N ──► LiteLLM proxy
                                                           (your endpoint)

Each instance shares a bind-mounted hermes-home:
  instances/instance-N/hermes-home/   ← sessions, skills, memories, config
  instances/instance-N/workspace/     ← agent workspace files
```

Each webui+agent pair shares an isolated `hermes-home` directory on the host, so data never leaks between instances. The `shared-skills/` directory is the one exception — skills placed there are visible (read-only) to all webuis.

## Prerequisites

- Docker + Docker Compose v2
- Python 3 (for bootstrap templating — no install needed beyond system python)
- bash 3.2+ (macOS default is fine)

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
$EDITOR .env          # set LITELLM_BASE_URL, passwords, HOST_UID/GID

# 2. Render per-instance configs
./scripts/bootstrap.sh

# 3. Start the stack
docker compose up -d

# 4. Open in browser
open http://localhost:8787   # instance 1
open http://localhost:8788   # instance 2
```

## Port Mapping

| Instance | WebUI URL                         | Agent Gateway (loopback only) |
|----------|-----------------------------------|-------------------------------|
| 1        | http://\<server-ip\>:8787         | localhost:8642                |
| 2        | http://\<server-ip\>:8788         | localhost:8643                |
| N        | http://\<server-ip\>:8786+N       | localhost:8641+N              |

WebUI ports bind to all interfaces (`0.0.0.0`) and are accessible from the network. Agent gateway ports bind to `127.0.0.1` (loopback only) — external access to the agent API is not needed since the webui handles that internally. Password protection is enforced on every webui.

## Instance Data

Each instance stores its data in a bind-mounted directory you can access directly:

```
instances/
  instance-1/
    hermes-home/          # agent data (sessions, skills, memories, config.yaml, .env)
    workspace/            # file workspace visible inside the agent
  instance-2/
    ...
```

Files are owned by `HOST_UID:HOST_GID` (set in `.env`). You can read, copy or edit any file directly — changes are picked up by the running agent.

## Scripts Reference

| Script | Usage | Description |
|--------|-------|-------------|
| `bootstrap.sh` | `./scripts/bootstrap.sh` | Create `.env` from example and render `config.yaml` for all instances |
| `add-instance.sh` | `./scripts/add-instance.sh <N> <password>` | Add a new instance (idempotent) |
| `remove-instance.sh` | `./scripts/remove-instance.sh <N> [--purge] [--yes]` | Remove an instance; `--purge` deletes data |
| `share-skill.sh` | `./scripts/share-skill.sh <skill> [from] [to\|all]` | Copy a skill between instances |
| `status.sh` | `./scripts/status.sh` | Show status table for all instances |
| `backup-instance.sh` | `./scripts/backup-instance.sh <N>` | Create a tarball backup of an instance |

See [docs/SCALING.md](docs/SCALING.md) for scaling instructions and [docs/SKILL_SHARING.md](docs/SKILL_SHARING.md) for skill management.

## Configuration

All configuration lives in `.env`. See [docs/ENV_REFERENCE.md](docs/ENV_REFERENCE.md) for the full variable reference.

The most important variables to set before first run:

```env
LITELLM_BASE_URL=http://host.docker.internal:4000/v1
LITELLM_API_KEY=sk-your-key
HERMES_DEFAULT_MODEL=gpt-4o-mini
HOST_UID=501    # run: id -u
HOST_GID=20     # run: id -g
HERMES_WEBUI_PASSWORD_1=your-secure-password
HERMES_WEBUI_PASSWORD_2=another-secure-password
```

## Agent Privileges

Each `hermes-agent` container runs from a locally-built image (`docker/hermes-agent/Dockerfile`) that extends the upstream `nousresearch/hermes-agent` with passwordless `sudo` for the in-container `hermes` user. This lets every instance install OS packages, language runtimes, and other system tooling on demand:

```bash
sudo apt-get update && sudo apt-get install -y <package>
```

The agent process itself still runs under `HOST_UID:HOST_GID` via the upstream entrypoint's `gosu` drop, so files written to `hermes-home/` and `workspace/` keep correct host ownership. `docker compose up -d` builds the image automatically on first run; rebuild explicitly with:

```bash
docker compose build hermes-agent-1
```

## LiteLLM Integration

Every hermes-agent instance connects exclusively to your LiteLLM proxy. The proxy is configured once in `.env` via `LITELLM_BASE_URL` and `LITELLM_API_KEY`, then injected into each instance's `config.yaml` at bootstrap time.

LiteLLM must be reachable from inside the Docker network:
- **Same host (macOS/Linux):** `http://host.docker.internal:4000/v1`
- **Sibling Docker service:** `http://litellm:4000/v1` (attach litellm to `hermes-net`)
- **External/cloud:** `https://litellm.example.com/v1`

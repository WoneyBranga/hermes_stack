# Environment Variable Reference

All variables are defined in `.env` (created from `.env.example` by `bootstrap.sh`). The file is owner-readable only (`chmod 600`) to protect passwords.

## Global Variables

### LiteLLM Proxy

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LITELLM_BASE_URL` | Yes | `http://host.docker.internal:4000/v1` | Base URL of your LiteLLM proxy (OpenAI-compatible). All agent instances connect here. |
| `LITELLM_API_KEY` | Yes | `sk-litellm-change-me` | Master key for the LiteLLM proxy. Leave as placeholder only for unauthenticated dev proxies. |
| `HERMES_DEFAULT_MODEL` | Yes | `gpt-4o-mini` | Model alias to request from LiteLLM. Must match a model declared in the proxy's `config.yaml`. |

**LiteLLM URL scenarios:**

```env
# LiteLLM on the same host (macOS/Linux, outside Docker)
LITELLM_BASE_URL=http://host.docker.internal:4000/v1

# LiteLLM as a sibling Docker service on hermes-net
LITELLM_BASE_URL=http://litellm:4000/v1

# LiteLLM hosted externally
LITELLM_BASE_URL=https://litellm.example.com/v1
```

### Host Permissions

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HOST_UID` | Yes | `501` | UID of the host user. Bind-mounted files will be owned by this UID. Run `id -u` to get yours. |
| `HOST_GID` | Yes | `20` | GID of the host user. Run `id -g` to get yours. |

> **macOS note:** UIDs on macOS typically start at 501 (not 1000 as on Linux). Using the wrong UID causes the agent to fail writing to `hermes-home`.

```bash
# Get correct values for your machine
echo "HOST_UID=$(id -u)"
echo "HOST_GID=$(id -g)"
```

## Per-Instance Variables

### WebUI Passwords

| Variable | Required | Description |
|----------|----------|-------------|
| `HERMES_WEBUI_PASSWORD_N` | Yes | Password for instance N's web interface. The `docker-compose.yml` uses `${VAR:?}` expansion — the stack will refuse to start if this is empty. |

`add-instance.sh` appends the new password variable automatically. You can also add them manually:

```env
HERMES_WEBUI_PASSWORD_3=my-secure-password
```

Password rules enforced by `add-instance.sh`:
- Cannot be empty
- Cannot contain newlines
- Single quotes in passwords are correctly escaped

### Per-Instance LiteLLM API keys

| Variable | Required | Description |
|----------|----------|-------------|
| `LITELLM_API_KEY_N` | Yes for instances added via `add-instance.sh` | API key used by instance N to authenticate on LiteLLM. New instance blocks in `docker-compose.yml` require this variable. |

`add-instance.sh` appends this variable automatically for each new instance:

```env
LITELLM_API_KEY_3=sk-instance-3
```

## Variables Injected into Containers

These are set by `docker-compose.yml` and derived from the `.env` variables above. You do not set them directly in `.env`.

### hermes-agent containers

| Variable | Source | Description |
|----------|--------|-------------|
| `HERMES_HOME` | hardcoded `/opt/data` | Agent data directory inside the container |
| `HERMES_UID` | `${HOST_UID}` | Remaps the agent's internal user to match the host |
| `HERMES_GID` | `${HOST_GID}` | Remaps the agent's internal group |
| `LITELLM_BASE_URL` | `${LITELLM_BASE_URL}` | Passed through to agent config |
| `LITELLM_API_KEY` | `${LITELLM_API_KEY_N}` for instances added via script (fallback to global `LITELLM_API_KEY` in rendered `config.yaml`) | Passed through to agent config |
| `HERMES_DEFAULT_MODEL` | `${HERMES_DEFAULT_MODEL}` | Passed through to agent config |
| `OPENAI_BASE_URL` | `${LITELLM_BASE_URL}` | OpenAI-compat alias — covers code paths that use the OpenAI SDK directly |
| `OPENAI_API_KEY` | `${LITELLM_API_KEY_N}` for instances added via script | OpenAI-compat alias |

### hermes-webui containers

| Variable | Source | Description |
|----------|--------|-------------|
| `HERMES_WEBUI_HOST` | `0.0.0.0` | Bind address (all interfaces inside the container; host exposure is controlled by `ports`) |
| `HERMES_WEBUI_PORT` | `8787` | Internal listen port (always 8787; host port differs per instance) |
| `HERMES_WEBUI_STATE_DIR` | `/home/hermeswebui/.hermes/webui` | Where the webui stores sessions and settings |
| `HERMES_WEBUI_PASSWORD` | `${HERMES_WEBUI_PASSWORD_N}` | Per-instance password; required |
| `WANTED_UID` | `${HOST_UID}` | UID remapping for bind-mount compatibility |
| `WANTED_GID` | `${HOST_GID}` | GID remapping for bind-mount compatibility |

## Per-Instance config.yaml

Each instance gets a rendered `instances/instance-N/hermes-home/config.yaml` created by `bootstrap.sh` (or `add-instance.sh`). It is derived from `config/hermes-config.yaml` with the following placeholders substituted from `.env`:

| Placeholder | Substituted from |
|-------------|-----------------|
| `__LITELLM_BASE_URL__` | `LITELLM_BASE_URL` |
| `__LITELLM_API_KEY__` | `LITELLM_API_KEY_N` (fallback to global `LITELLM_API_KEY`) |
| `__HERMES_DEFAULT_MODEL__` | `HERMES_DEFAULT_MODEL` |

To re-render configs after changing `.env` values:

```bash
FORCE=1 ./scripts/bootstrap.sh
```

# Scaling the Hermes Stack

The stack starts with 2 instances and can scale to 20+ with a single command per instance.

## Adding an Instance

```bash
./scripts/add-instance.sh <N> <webui-password> <litellm-api-key>

# Examples
./scripts/add-instance.sh 3 'my-secure-pass' 'sk-instance-3'
./scripts/add-instance.sh 10 'another-pass' 'sk-instance-10'
```

The script:
1. Creates `instances/instance-N/{hermes-home,workspace}/`
2. Renders `config.yaml` with LiteLLM settings from `.env`
3. Appends `HERMES_WEBUI_PASSWORD_N` and `LITELLM_API_KEY_N` to `.env`
4. Inserts the `hermes-agent-N` + `hermes-webui-N` service blocks into `docker-compose.yml`

Then start the new instance:

```bash
docker compose up -d hermes-agent-N hermes-webui-N
```

The script is idempotent: re-running for an existing instance exits with an error and changes nothing.

## Removing an Instance

```bash
# Stop and remove from compose, keep data on disk
./scripts/remove-instance.sh 3

# Stop, remove from compose, and delete all instance data
./scripts/remove-instance.sh 3 --purge --yes
```

## Scaling Example: 2 → 5 Instances

```bash
for N in 3 4 5; do
  ./scripts/add-instance.sh $N "password-for-instance-$N" "sk-instance-$N"
done
docker compose up -d hermes-agent-3 hermes-webui-3 \
                     hermes-agent-4 hermes-webui-4 \
                     hermes-agent-5 hermes-webui-5
```

Verify all are running:

```bash
./scripts/status.sh
```

## Port Allocation

Ports are allocated deterministically:

| Instance N | WebUI port  | Agent gateway port |
|-----------|-------------|-------------------|
| 1         | 8787        | 8642              |
| 2         | 8788        | 8643              |
| 3         | 8789        | 8644              |
| N         | 8786 + N    | 8641 + N          |

This supports up to instance 999 without port collisions (below 9785/9640).

## Resource Considerations (10–20 Instances)

Each hermes-agent + hermes-webui pair typically needs:
- ~512 MB RAM per pair (varies by model and session activity)
- Negligible CPU when idle; spikes during LLM streaming

For 20 instances: plan for ~10 GB RAM on the Docker host. Monitor with:

```bash
docker stats --no-stream
```

## Upgrading the Agent Image

The `hermes-agent-src-N` named volume is populated once from the image on first `docker compose up`. After pulling a new image, the volume must be removed to pick up the update:

```bash
# For a single instance
docker compose down hermes-agent-3 hermes-webui-3
docker volume rm poc_hermes_hermes-agent-src-3   # prefix = project dir name, lowercased
docker compose up -d hermes-agent-3 hermes-webui-3

# For all instances at once (replace with your instance numbers)
docker compose down
for N in 1 2 3; do
  docker volume rm poc_hermes_hermes-agent-src-$N
done
docker compose up -d
```

> The project volume prefix (`poc_hermes_`) is derived from the directory name Docker Compose uses. Adjust if your directory is named differently.

# Extends the upstream hermes-agent image so the in-container `hermes`
# user can escalate to root via passwordless sudo. This is required so
# each agent instance can install OS packages (apt), global pip/npm
# packages, and other system-level tooling on demand while the agent
# process itself still runs as a non-root UID mapped to HOST_UID/GID
# (preserving correct ownership of the bind-mounted hermes-home and
# workspace directories on the host).
FROM nousresearch/hermes-agent:latest

USER root

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo \
 && rm -rf /var/lib/apt/lists/* \
 && echo 'hermes ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/hermes-nopasswd \
 && chmod 0440 /etc/sudoers.d/hermes-nopasswd

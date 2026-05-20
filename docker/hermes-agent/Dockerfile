# Extends the upstream hermes-agent image so the in-container `hermes`
# user can escalate to root via passwordless sudo. This is required so
# each agent instance can install OS packages (apt), global pip/npm
# packages, and other system-level tooling on demand while the agent
# process itself still runs as a non-root UID mapped to HOST_UID/GID
# (preserving correct ownership of the bind-mounted hermes-home and
# workspace directories on the host).
FROM nousresearch/hermes-agent:latest

# Corporate proxy support for the build itself (apt-get reaching debian
# mirrors). Wired from docker-compose.yml `build.args`, which in turn
# pulls from proxy.env / shell env. Scoped to the RUN below so the proxy
# is NOT baked into the final image layers — runtime proxy is injected
# separately via `env_file: proxy.env` in the service definition.
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
ARG NO_PROXY=

USER root

RUN http_proxy="${HTTP_PROXY}" https_proxy="${HTTPS_PROXY}" no_proxy="${NO_PROXY}" \
    HTTP_PROXY="${HTTP_PROXY}" HTTPS_PROXY="${HTTPS_PROXY}" NO_PROXY="${NO_PROXY}" \
    apt-get update \
 && http_proxy="${HTTP_PROXY}" https_proxy="${HTTPS_PROXY}" no_proxy="${NO_PROXY}" \
    HTTP_PROXY="${HTTP_PROXY}" HTTPS_PROXY="${HTTPS_PROXY}" NO_PROXY="${NO_PROXY}" \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends sudo \
 && rm -rf /var/lib/apt/lists/* \
 && echo 'hermes ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/hermes-nopasswd \
 && chmod 0440 /etc/sudoers.d/hermes-nopasswd

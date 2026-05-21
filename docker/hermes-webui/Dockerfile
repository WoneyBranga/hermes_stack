# Extends the upstream hermes-webui image so the in-container
# `hermeswebui` user can escalate to root via passwordless sudo. The
# hermes shell tool executes inside this container (not in the agent),
# so the webui is where users need package-install capability. The
# upstream image explicitly does not ship sudo for hardening — this
# layer adds it back for our trusted single-tenant deployment model.
FROM ghcr.io/nesquena/hermes-webui:latest

# Corporate proxy support for the build itself — same pattern as the
# agent Dockerfile. Wired from docker-compose `build.args` which pulls
# from proxy.env / shell env. Scoped to the RUN below so credentials
# are not baked into final image layers; runtime proxy is injected
# separately via env_file: proxy.env.
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
 && mkdir -p /etc/sudoers.d \
 && echo 'hermeswebui ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/hermeswebui-nopasswd \
 && chmod 0440 /etc/sudoers.d/hermeswebui-nopasswd

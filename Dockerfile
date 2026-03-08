FROM python:3.11-alpine

ARG HERMES_REF=main

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin

# System deps: git, curl, QEMU (TCG for ARM64), Node.js, build tools for pip packages
RUN apk add --no-cache \
    git curl ca-certificates bash \
    qemu-system-aarch64 qemu-img \
    nodejs npm \
    gcc musl-dev linux-headers libffi-dev

# Gondolin CLI
RUN npm install -g @earendil-works/gondolin

WORKDIR /opt
RUN git clone --recurse-submodules --depth 1 --branch ${HERMES_REF} https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent

WORKDIR /opt/hermes-agent
RUN pip install --no-cache-dir -e ".[mcp,pty]" \
 && pip install --no-cache-dir -e "./mini-swe-agent"

# Symlink git into /usr/local/bin so it's available inside the Gondolin VM
RUN ln -s /usr/bin/git /usr/local/bin/git

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["chat"]

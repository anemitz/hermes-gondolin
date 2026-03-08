#!/usr/bin/env bash
set -euo pipefail
umask 077

# --- Copy Hermes config ---
mkdir -p /root/.hermes
if [[ -f /config/config.yaml ]]; then
  cp /config/config.yaml /root/.hermes/config.yaml
  cp /config/config.yaml /opt/hermes-agent/cli-config.yaml
fi

# --- Persist hermes state to /workspace ---
mkdir -p /workspace/sessions
ln -sfn /workspace/sessions /root/.hermes/sessions
ln -sfn /workspace/state.db /root/.hermes/state.db

# --- Persist memories and soul to /workspace ---
mkdir -p /workspace/memories
ln -sfn /workspace/memories /root/.hermes/memories
if [[ -f /workspace/SOUL.md ]]; then
  ln -sfn /workspace/SOUL.md /root/.hermes/SOUL.md
fi

# --- Read provider.env ---
# SECRET_<name>=<key>   → stored for --host-secret
# HOSTS_<name>=<hosts>  → comma-separated hostnames for that secret
# ALLOW_HOST[S]=<hosts> → extra hosts to allow (no secret needed)
# Anything else          → passed as --env
ENV_FILE="${PROVIDER_ENV_FILE:-/run/secrets/provider.env}"
declare -A secrets=()
declare -A hosts=()
declare -a env_flags=()
declare -a allow_flags=()
auto_approve=false

# strip leading/trailing whitespace without xargs (glob-safe)
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# split comma-separated values into --allow-host flags
add_allow_hosts() {
  IFS=',' read -ra items <<< "$1"
  for h in "${items[@]}"; do
    h="$(trim "$h")"
    [[ -n "$h" ]] && allow_flags+=(--allow-host "$h")
  done
}

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key="$(trim "$key")"
    value="$(trim "$value")"
    [[ -z "$key" || -z "$value" ]] && continue

    if [[ "$key" == SECRET_* ]]; then
      secrets["${key#SECRET_}"]="$value"
    elif [[ "$key" == HOSTS_* ]]; then
      hosts["${key#HOSTS_}"]="$value"
    elif [[ "$key" == "ALLOW_HOSTS" || "$key" == "ALLOW_HOST" ]]; then
      add_allow_hosts "$value"
    elif [[ "$key" == "AUTO_APPROVE" && "$value" == "true" ]]; then
      auto_approve=true
    else
      env_flags+=(--env "$key=$value")
    fi
  done < "$ENV_FILE"
fi

# --- Build --host-secret flags and auto-allow secret hosts ---
declare -a secret_flags=()

for name in "${!secrets[@]}"; do
  host_list="${hosts[$name]:-}"
  if [[ -z "$host_list" ]]; then
    echo "WARNING: SECRET_${name} has no matching HOSTS_${name} — skipping" >&2
    continue
  fi
  secret_flags+=(--host-secret "${name}@${host_list}=${secrets[$name]}")
  IFS=',' read -ra host_array <<< "$host_list"
  for host in "${host_array[@]}"; do
    host="$(trim "$host")"
    [[ -z "$host" ]] && continue
    allow_flags+=(--allow-host "$host")
  done
done

# --- Build hermes command ---
declare -a hermes_cmd=(/usr/local/bin/hermes)
if [[ "$1" == "run" ]]; then
  hermes_cmd+=($HERMES_CMD)
elif [[ -n "${HERMES_SESSION:-}" ]]; then
  hermes_cmd+=(--resume "$HERMES_SESSION")
else
  hermes_cmd+=("$@")
fi

# --- Auto-approve: remove hardcoded HERMES_INTERACTIVE from cli.py ---
if [[ "$auto_approve" == true ]]; then
  sed -i '/os\.environ\[.HERMES_INTERACTIVE.\]/d' /opt/hermes-agent/cli.py
fi

# --- Launch Hermes inside Gondolin micro-VM ---
exec gondolin bash \
  "${secret_flags[@]}" \
  "${allow_flags[@]}" \
  "${env_flags[@]}" \
  --mount-hostfs /opt/hermes-agent:/opt/hermes-agent \
  --mount-hostfs /workspace:/workspace \
  --mount-hostfs /root/.hermes:/root/.hermes \
  --mount-hostfs /usr/local/bin:/usr/local/bin:ro \
  --mount-hostfs /usr/local/lib:/usr/local/lib:ro \
  --mount-hostfs /usr/lib:/usr/lib:ro \
  --mount-hostfs /usr/libexec/git-core:/usr/libexec/git-core:ro \
  -- \
  "${hermes_cmd[@]}"

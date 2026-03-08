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

# --- Read provider.env ---
# SECRET_<name>=<key>  → stored for --host-secret
# HOSTS_<name>=<hosts> → comma-separated hostnames for that secret
# Anything else        → passed as --env
ENV_FILE="${PROVIDER_ENV_FILE:-/run/secrets/provider.env}"
declare -A secrets=()
declare -A hosts=()
declare -a env_flags=()

if [[ -f "$ENV_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | xargs)"
    [[ -z "$key" || -z "$value" ]] && continue

    if [[ "$key" == SECRET_* ]]; then
      name="${key#SECRET_}"
      secrets["$name"]="$value"
    elif [[ "$key" == HOSTS_* ]]; then
      name="${key#HOSTS_}"
      hosts["$name"]="$value"
    else
      env_flags+=(--env "$key=$value")
    fi
  done < "$ENV_FILE"
fi

# --- Build --host-secret flags from paired SECRET_/HOSTS_ entries ---
declare -a secret_flags=()

for name in "${!secrets[@]}"; do
  secret_val="${secrets[$name]}"
  host_list="${hosts[$name]:-}"
  if [[ -z "$host_list" ]]; then
    echo "WARNING: SECRET_${name} has no matching HOSTS_${name} — skipping" >&2
    continue
  fi
  IFS=',' read -ra host_array <<< "$host_list"
  for host in "${host_array[@]}"; do
    host="$(echo "$host" | xargs)"
    [[ -z "$host" ]] && continue
    secret_flags+=(--host-secret "${name}@${host}=${secret_val}")
  done
done

# --- Build hermes command ---
declare -a hermes_cmd=(/usr/local/bin/hermes)
if [[ "$1" == "run" ]]; then
  # Pass HERMES_CMD args directly to hermes (e.g., "sessions", "--help")
  hermes_cmd+=($HERMES_CMD)
elif [[ -n "${HERMES_SESSION:-}" ]]; then
  hermes_cmd+=(--resume "$HERMES_SESSION")
else
  hermes_cmd+=("$@")
fi

# --- Launch Hermes inside Gondolin micro-VM ---
exec gondolin bash \
  "${secret_flags[@]}" \
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

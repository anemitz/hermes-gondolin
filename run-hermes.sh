#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-shell}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STACK_DIR="${STACK_DIR:-$SCRIPT_DIR}"
IMAGE="${IMAGE:-hermes-gondolin:latest}"
COLIMA_PROFILE="${COLIMA_PROFILE:-hermes}"
COLIMA_VM_TYPE="${COLIMA_VM_TYPE:-vz}"
COLIMA_ARCH="${COLIMA_ARCH:-aarch64}"
COLIMA_CPU="${COLIMA_CPU:-6}"
COLIMA_MEMORY="${COLIMA_MEMORY:-12}"
COLIMA_DISK="${COLIMA_DISK:-80}"
PLATFORM="${PLATFORM:-linux/arm64}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

seed_file_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "Created $dst"
  fi
}

init_stack() {
  mkdir -p "$STACK_DIR"/{workspace,config,secrets}
  chmod 700 "$STACK_DIR/secrets" || true

  seed_file_if_missing "$SCRIPT_DIR/secrets/provider.env.example" "$STACK_DIR/secrets/provider.env"

  chmod 600 "$STACK_DIR/secrets/provider.env" || true

  cat > "$STACK_DIR/config/config.yaml" <<YAML
terminal:
  backend: pty
  cwd: /workspace
YAML

  echo "Wrote $STACK_DIR/config/config.yaml"
  echo "Stack initialized at $STACK_DIR"
}

ensure_colima_running() {
  if ! colima status --profile "$COLIMA_PROFILE" 2>/dev/null | grep -qi "running"; then
    echo "Starting Colima profile '$COLIMA_PROFILE'..."
    if ! colima start --profile "$COLIMA_PROFILE" --vm-type "$COLIMA_VM_TYPE" --arch "$COLIMA_ARCH" --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK" --nested-virtualization; then
      if [[ "$COLIMA_VM_TYPE" == "vz" ]]; then
        echo "vz start failed; falling back to qemu..."
        colima start --profile "$COLIMA_PROFILE" --vm-type qemu --arch "$COLIMA_ARCH" --cpu "$COLIMA_CPU" --memory "$COLIMA_MEMORY" --disk "$COLIMA_DISK"
      else
        exit 1
      fi
    fi
  fi
}

set_docker_context_for_profile() {
  local ctx
  if docker context ls --format '{{.Name}}' | grep -qx "colima-${COLIMA_PROFILE}"; then
    ctx="colima-${COLIMA_PROFILE}"
  elif docker context ls --format '{{.Name}}' | grep -qx "colima"; then
    ctx="colima"
  else
    echo "Could not find a Colima docker context."
    docker context ls || true
    exit 1
  fi

  docker context use "$ctx" >/dev/null
}

build_image() {
  echo "Building image: $IMAGE"
  docker build --platform "$PLATFORM" -t "$IMAGE" "$SCRIPT_DIR"
}

warn_if_no_keys() {
  if ! grep -Eq '^SECRET_[A-Za-z_]+=' "$STACK_DIR/secrets/provider.env"; then
    cat <<EOF
WARNING: No SECRET_ entry detected in $STACK_DIR/secrets/provider.env
Add at least one secret pair, for example:
  SECRET_OPENROUTER=sk-or-...
  HOSTS_OPENROUTER=openrouter.ai
EOF
  fi
}

run_shell() {
  warn_if_no_keys

  echo "Launching Hermes inside Gondolin VM..."
  docker run --rm -it \
    --name hermes \
    --platform "$PLATFORM" \
    --privileged \
    -v "$STACK_DIR/workspace:/workspace" \
    -v "$STACK_DIR/config:/config:ro" \
    -v "$STACK_DIR/secrets:/run/secrets:ro" \
    -v hermes-gondolin-cache:/root/.cache/gondolin \
    -e PROVIDER_ENV_FILE=/run/secrets/provider.env \
    -e HERMES_SESSION="${HERMES_SESSION:-}" \
    "$IMAGE"
}

show_status() {
  echo "Colima status:"
  colima status --profile "$COLIMA_PROFILE" || true
  echo
  echo "Docker context:"
  docker context show || true
  echo
  echo "Docker ps (top 10):"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | sed -n '1,11p' || true
}

stop_colima() {
  echo "Stopping Colima profile '$COLIMA_PROFILE'..."
  colima stop --profile "$COLIMA_PROFILE"
}

restart_colima() {
  stop_colima || true
  ensure_colima_running
  set_docker_context_for_profile
}

main() {
  need_cmd colima
  need_cmd docker
  need_cmd git

  case "$ACTION" in
    init)
      init_stack
      ;;
    build)
      init_stack
      ensure_colima_running
      set_docker_context_for_profile
      build_image
      ;;
    shell)
      init_stack
      ensure_colima_running
      set_docker_context_for_profile
      if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        build_image
      fi
      run_shell
      ;;
    down)
      stop_colima
      ;;
    restart)
      restart_colima
      ;;
    status)
      ensure_colima_running
      set_docker_context_for_profile
      show_status
      ;;
    *)
      echo "Usage: $0 {init|build|shell|down|restart|status}"
      exit 1
      ;;
  esac
}

main "$@"

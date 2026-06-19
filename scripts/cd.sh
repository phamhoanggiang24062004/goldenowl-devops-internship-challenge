#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "CD script failed at line ${LINENO}. Check the log above for the failing step." >&2' ERR

APP_DIR="${APP_DIR:-src}"
IMAGE_NAME="${IMAGE_NAME:-goldenowl-devops-internship-challenge}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse HEAD)}"
CONTAINER_NAME="${CONTAINER_NAME:-Nodejs-app-container}"
APP_CONTAINER_NAMES="${APP_CONTAINER_NAMES:-$CONTAINER_NAME goldenowl-nodejs-app Nodejs-app-container}"
HOST_PORT="${HOST_PORT:-3000}"
CONTAINER_PORT="${CONTAINER_PORT:-3000}"
EC2_SSH_PORT="${EC2_SSH_PORT:-22}"

log() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    echo "Missing required environment variable: $1" >&2
    exit 1
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

shell_quote() {
  printf '%q' "$1"
}

build_and_push_image() {
  require_command docker
  require_env DOCKERHUB_USERNAME
  require_env DOCKERHUB_TOKEN

  local tag_latest tag_sha
  tag_latest="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:latest"
  tag_sha="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  log "Print Docker build details"
  docker version
  docker buildx version
  echo "context=./${APP_DIR}"
  echo "push=true"
  echo "tag_latest=${tag_latest}"
  echo "tag_sha=${tag_sha}"
  ls -la "./${APP_DIR}"

  log "Login to Docker Hub"
  printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin

  log "Build Docker image"
  docker build \
    --tag "$tag_latest" \
    --tag "$tag_sha" \
    "./${APP_DIR}"

  log "Push Docker image"
  docker push "$tag_latest"
  docker push "$tag_sha"
}

prepare_ssh_key() {
  require_command ssh
  require_command ssh-keyscan
  require_command getent
  require_env EC2_HOST
  require_env EC2_USER
  require_env EC2_SSH_PRIVATE_KEY

  EC2_HOST="$(trim "$EC2_HOST")"
  EC2_USER="$(trim "$EC2_USER")"
  EC2_SSH_PORT="$(trim "$EC2_SSH_PORT")"

  if [[ "$EC2_HOST" == *"://"* || "$EC2_HOST" == *"@"* || "$EC2_HOST" == *"/"* ]]; then
    echo "EC2_HOST must be only a hostname or public IP, for example 18.141.1.2 or ec2-x-x-x-x.ap-southeast-1.compute.amazonaws.com." >&2
    echo "Do not include protocol, username, path, or an ssh command." >&2
    exit 1
  fi

  if ! [[ "$EC2_SSH_PORT" =~ ^[0-9]+$ ]]; then
    echo "EC2_SSH_PORT must be a number, for example 22." >&2
    exit 1
  fi

  log "Resolve VM host"
  if ! getent hosts "$EC2_HOST" >/dev/null; then
    echo "Cannot resolve EC2_HOST. Check that the GitHub secret EC2_HOST is a valid public IP or public DNS name." >&2
    echo "If this VM is private-only, GitHub-hosted runners cannot SSH to it directly." >&2
    exit 1
  fi

  log "Prepare SSH key"
  mkdir -p ~/.ssh
  printf '%s\n' "$EC2_SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
  chmod 600 ~/.ssh/deploy_key

  log "Add VM host key to known_hosts"
  if ! ssh-keyscan -T 10 -p "$EC2_SSH_PORT" "$EC2_HOST" >> ~/.ssh/known_hosts; then
    echo "ssh-keyscan failed. Check that port ${EC2_SSH_PORT} is open from the internet and the VM SSH service is running." >&2
    exit 1
  fi
}

deploy_to_vm() {
  local remote_env
  remote_env="DOCKERHUB_USERNAME=$(shell_quote "$DOCKERHUB_USERNAME")"
  remote_env+=" DOCKERHUB_TOKEN=$(shell_quote "$DOCKERHUB_TOKEN")"
  remote_env+=" IMAGE_NAME=$(shell_quote "$IMAGE_NAME")"
  remote_env+=" IMAGE_TAG=$(shell_quote "$IMAGE_TAG")"
  remote_env+=" CONTAINER_NAME=$(shell_quote "$CONTAINER_NAME")"
  remote_env+=" APP_CONTAINER_NAMES=$(shell_quote "$APP_CONTAINER_NAMES")"
  remote_env+=" HOST_PORT=$(shell_quote "$HOST_PORT")"
  remote_env+=" CONTAINER_PORT=$(shell_quote "$CONTAINER_PORT")"

  log "Deploy application via SSH"
  if ! ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=20 \
    -o ServerAliveInterval=10 \
    -o ServerAliveCountMax=3 \
    -i ~/.ssh/deploy_key \
    -p "$EC2_SSH_PORT" \
    "${EC2_USER}@${EC2_HOST}" \
    "${remote_env} bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail
echo "Remote deploy started on $(hostname)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Missing required command on remote VM: docker" >&2
  exit 1
fi

DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
  else
    echo "Current remote user cannot run Docker. Add the user to the docker group or allow passwordless sudo for docker." >&2
    exit 1
  fi
fi

IMAGE="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Deploying image: ${IMAGE}"
echo "Container name: ${CONTAINER_NAME}"
echo "Port mapping: ${HOST_PORT}:${CONTAINER_PORT}"

echo "Login to Docker Hub on remote VM"
printf '%s' "$DOCKERHUB_TOKEN" | $DOCKER login --username "$DOCKERHUB_USERNAME" --password-stdin

echo "Pull image"
$DOCKER pull "$IMAGE"

for app_container_name in $APP_CONTAINER_NAMES; do
  if $DOCKER ps -a --format '{{.Names}}' | grep -Fxq "$app_container_name"; then
    echo "Stop existing app container: ${app_container_name}"
    $DOCKER stop "$app_container_name" || true
    echo "Remove existing app container: ${app_container_name}"
    $DOCKER rm "$app_container_name"
  fi
done

APP_IMAGE_CONTAINER_IDS="$($DOCKER ps -a -q --filter "ancestor=${DOCKERHUB_USERNAME}/${IMAGE_NAME}")"
if [[ -n "$APP_IMAGE_CONTAINER_IDS" ]]; then
  echo "Remove existing app containers created from image ${DOCKERHUB_USERNAME}/${IMAGE_NAME}"
  $DOCKER stop $APP_IMAGE_CONTAINER_IDS || true
  $DOCKER rm $APP_IMAGE_CONTAINER_IDS
fi

echo "Start new container"
if ! $DOCKER run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "$IMAGE"; then
  echo "Failed to start container. Port/process diagnostics:" >&2
  $DOCKER ps -a >&2 || true
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "sport = :${HOST_PORT}" >&2 || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${HOST_PORT}" -sTCP:LISTEN >&2 || true
  fi
  exit 1
fi

$DOCKER ps --filter "name=${CONTAINER_NAME}"
echo "Remote deploy completed"
REMOTE_SCRIPT
  then
    echo "SSH deploy failed. Common causes: wrong EC2_USER, private key mismatch, port 22 blocked in security group, or remote Docker permission issue." >&2
    exit 1
  fi
}

build_and_push_image
prepare_ssh_key
deploy_to_vm

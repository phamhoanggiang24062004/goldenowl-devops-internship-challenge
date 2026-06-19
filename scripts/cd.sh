#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-src}"
IMAGE_NAME="${IMAGE_NAME:-goldenowl-devops-internship-challenge}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse HEAD)}"
CONTAINER_NAME="${CONTAINER_NAME:-goldenowl-nodejs-app}"
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
  require_env EC2_HOST
  require_env EC2_USER
  require_env EC2_SSH_PRIVATE_KEY

  mkdir -p ~/.ssh
  printf '%s\n' "$EC2_SSH_PRIVATE_KEY" > ~/.ssh/deploy_key
  chmod 600 ~/.ssh/deploy_key
  ssh-keyscan -p "$EC2_SSH_PORT" "$EC2_HOST" >> ~/.ssh/known_hosts
}

deploy_to_vm() {
  local remote_env
  remote_env="DOCKERHUB_USERNAME=$(shell_quote "$DOCKERHUB_USERNAME")"
  remote_env+=" DOCKERHUB_TOKEN=$(shell_quote "$DOCKERHUB_TOKEN")"
  remote_env+=" IMAGE_NAME=$(shell_quote "$IMAGE_NAME")"
  remote_env+=" IMAGE_TAG=$(shell_quote "$IMAGE_TAG")"
  remote_env+=" CONTAINER_NAME=$(shell_quote "$CONTAINER_NAME")"
  remote_env+=" HOST_PORT=$(shell_quote "$HOST_PORT")"
  remote_env+=" CONTAINER_PORT=$(shell_quote "$CONTAINER_PORT")"

  log "Deploy application via SSH"
  ssh \
    -i ~/.ssh/deploy_key \
    -p "$EC2_SSH_PORT" \
    "${EC2_USER}@${EC2_HOST}" \
    "${remote_env} bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

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

printf '%s' "$DOCKERHUB_TOKEN" | $DOCKER login --username "$DOCKERHUB_USERNAME" --password-stdin
$DOCKER pull "$IMAGE"

if $DOCKER ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  $DOCKER stop "$CONTAINER_NAME"
  $DOCKER rm "$CONTAINER_NAME"
fi

$DOCKER run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${HOST_PORT}:${CONTAINER_PORT}" \
  "$IMAGE"

$DOCKER ps --filter "name=${CONTAINER_NAME}"
REMOTE_SCRIPT
}

build_and_push_image
prepare_ssh_key
deploy_to_vm

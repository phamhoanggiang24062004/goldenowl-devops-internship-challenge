#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-src}"

log() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

log "Print Node.js setup details"
require_command node
require_command npm

cd "$APP_DIR"

echo "working_directory=$(pwd)"
node --version
npm --version
npm config get cache
ls -la

log "Install dependencies"
npm ci --loglevel=verbose

log "Run tests"
npm test

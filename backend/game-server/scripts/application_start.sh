#!/bin/bash
# CodeDeploy ApplicationStart — install deps, restart PM2, verify /health.
# Requires /etc/fighting-game.env on the instance (see fighting-game.env.example).
set -euo pipefail

APP_DIR="/home/ubuntu/fighting-game-server"
ENV_FILE="/etc/fighting-game.env"

cd "$APP_DIR"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

export COGNITO_REGION="${COGNITO_REGION:-ap-southeast-1}"
export COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:?COGNITO_USER_POOL_ID required — create $ENV_FILE on the instance}"
export MATCHES_TABLE="${MATCHES_TABLE:-ActiveMatches}"
export PORT="${PORT:-9000}"

npm ci --omit=dev 2>/dev/null || npm install --omit=dev

if ! command -v pm2 >/dev/null 2>&1; then
  sudo npm install -g pm2
fi

pm2 delete fighting-game-server 2>/dev/null || true
pm2 start server.js --name fighting-game-server
pm2 save

curl -sf "http://127.0.0.1:${PORT}/health"

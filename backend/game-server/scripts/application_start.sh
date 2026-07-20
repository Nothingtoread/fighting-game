#!/bin/bash
# CodeDeploy ApplicationStart — install deps, restart PM2, verify /health.
# Requires /etc/fighting-game.env on the instance (see fighting-game.env.example).
set -euo pipefail

APP_DIR="/home/ubuntu/fighting-game-server"
BUNDLED_ENV="$APP_DIR/fighting-game.env"
ENV_FILE="/etc/fighting-game.env"

cd "$APP_DIR"

set -a
if [[ -f "$BUNDLED_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$BUNDLED_ENV"
elif [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
set +a

export COGNITO_REGION="${COGNITO_REGION:-ap-southeast-1}"
export COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:?COGNITO_USER_POOL_ID required — set in fighting-game.env (CI) or $ENV_FILE on the instance}"
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

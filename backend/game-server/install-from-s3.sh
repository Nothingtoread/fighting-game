#!/bin/bash
# Legacy SSM deploy fallback. Prefer CodeDeploy (appspec.yml + scripts/application_*.sh).
# Runs on EC2 via SSM. Env: ASSETS_BUCKET, COGNITO_USER_POOL_ID
set -euo pipefail
APP_DIR="${APP_DIR:-/home/ubuntu/fighting-game-server}"
BUCKET="${ASSETS_BUCKET:?ASSETS_BUCKET required}"
POOL="${COGNITO_USER_POOL_ID:?COGNITO_USER_POOL_ID required}"

sudo mkdir -p "$APP_DIR"
cd "$APP_DIR"
aws s3 cp "s3://${BUCKET}/deploy/game-server.zip" /tmp/game-server.zip
unzip -o /tmp/game-server.zip -d "$APP_DIR"
npm ci --omit=dev 2>/dev/null || npm install --omit=dev
export COGNITO_REGION=ap-southeast-1
export COGNITO_USER_POOL_ID="$POOL"
export PORT=9000
if ! command -v pm2 >/dev/null; then
  sudo npm install -g pm2
fi
pm2 delete fighting-game-server 2>/dev/null || true
pm2 start server.js --name fighting-game-server
pm2 save
curl -sf "http://127.0.0.1:9000/health"

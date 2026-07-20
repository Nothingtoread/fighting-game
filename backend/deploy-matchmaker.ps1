# Deploy FightingGameMatchmaker — Phase 1 warm-pool wsEndpoint assignment
# Run from repo root:  powershell -ExecutionPolicy Bypass -File backend\deploy-matchmaker.ps1
$ErrorActionPreference = "Stop"
$Region = "ap-southeast-1"
$FunctionName = "FightingGameMatchmaker"
$Root = Split-Path -Parent $PSScriptRoot
$DeployDir = Join-Path $env:TEMP "fg-mm-deploy"
$ZipPath = Join-Path $DeployDir "matchmaker.zip"

Remove-Item -Recurse -Force $DeployDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
Copy-Item (Join-Path $Root "backend\lambda-matchmaker.mjs") (Join-Path $DeployDir "index.mjs")
Compress-Archive -Path (Join-Path $DeployDir "index.mjs") -DestinationPath $ZipPath -Force

Write-Host "1/3 Updating function code..."
aws lambda update-function-code `
  --function-name $FunctionName `
  --zip-file "fileb://$ZipPath" `
  --region $Region | Out-Null

Write-Host "2/3 Waiting for code update..."
aws lambda wait function-updated --function-name $FunctionName --region $Region

Write-Host "3/3 Updating config (timeout=10, env vars)..."
aws lambda update-function-configuration `
  --function-name $FunctionName `
  --timeout 10 `
  --environment "Variables={QUEUE_TABLE=MatchmakingQueue,MATCHES_TABLE=ActiveMatches,WS_ENDPOINT=ws://54.151.177.184:9000,GAME_SERVER_TAG_KEY=Role,GAME_SERVER_TAG_VALUE=FightingGameServer,WS_PORT=9000}" `
  --region $Region | Out-Null

aws lambda wait function-updated --function-name $FunctionName --region $Region

aws lambda get-function-configuration --function-name $FunctionName --region $Region `
  --query '{Timeout:Timeout,CodeSize:CodeSize,Handler:Handler,Runtime:Runtime,Env:Environment.Variables,LastUpdateStatus:LastUpdateStatus}' `
  --output json

Write-Host ""
Write-Host "Deploy complete. Node.js 22 runtime includes AWS SDK v3 (no node_modules zip needed)."

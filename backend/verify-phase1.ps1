# Verify Phase 1 - tagged game servers + health + IAM
# Run: powershell -ExecutionPolicy Bypass -File backend\verify-phase1.ps1
$ErrorActionPreference = "Continue"
$Region = "ap-southeast-1"

Write-Host "=== IAM: EC2 Describe on MatchMaker role ==="
$iamOk = $false
try {
  $iam = aws iam get-role-policy `
    --role-name FightingGameMatchmaker-role-5ps4pdke `
    --policy-name FightingGameMatchmakerEC2Describe `
    --region $Region `
    --output json 2>&1
  if ($LASTEXITCODE -eq 0) {
    $iamOk = $true
    Write-Host "OK: FightingGameMatchmakerEC2Describe attached"
  }
} catch {}
if (-not $iamOk) {
  Write-Host "MISSING: attach backend/iam-ec2-describe-policy.json to FightingGameMatchmaker-role-5ps4pdke"
}

Write-Host ""
Write-Host "=== Tagged running game servers (Lambda discovery) ==="
$instancesJson = aws ec2 describe-instances --region $Region --filters "Name=tag:Role,Values=FightingGameServer" "Name=instance-state-name,Values=running" --output json
$all = ($instancesJson | ConvertFrom-Json).Reservations | ForEach-Object { $_.Instances } | ForEach-Object {
  [PSCustomObject]@{ Id = $_.InstanceId; Ip = $_.PublicIpAddress; Type = $_.InstanceType }
}

if (-not $all -or $all.Count -eq 0) {
  Write-Host "WARNING: No running instances with tag Role=FightingGameServer."
  Write-Host "Tag EC2: aws ec2 create-tags --resources i-0d110a1e699bab029 --tags Key=Role,Value=FightingGameServer"
} else {
  $all | Format-Table -AutoSize
  foreach ($inst in $all) {
    if ($inst.Ip) {
      Write-Host ""
      Write-Host "Health: http://$($inst.Ip):9000/health"
      try {
        $r = Invoke-WebRequest -Uri "http://$($inst.Ip):9000/health" -TimeoutSec 8 -UseBasicParsing
        Write-Host "  Status: $($r.StatusCode)  Body: $($r.Content)"
      } catch {
        Write-Host "  FAILED: $($_.Exception.Message)"
      }
    }
  }
}

Write-Host ""
Write-Host "=== Lambda config ==="
aws lambda get-function-configuration --function-name FightingGameMatchmaker --region $Region --output json | ConvertFrom-Json | Select-Object Timeout, @{N='Env';E={$_.Environment.Variables}} | Format-List

Write-Host ""
Write-Host "=== Manual match test ==="
Write-Host "1. Login testplayer1 + testplayer2, both Find Match"
Write-Host "2. DynamoDB ActiveMatches: wsEndpoint should match a tagged IP above"
Write-Host "3. Look for instanceId, assignedAt, status=active on match rows"

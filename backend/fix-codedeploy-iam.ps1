# Apply CodeDeploy IAM fixes for Phase 2 CI/CD.
# Run from repo root: powershell -ExecutionPolicy Bypass -File backend\fix-codedeploy-iam.ps1
$ErrorActionPreference = "Stop"
$Region = "ap-southeast-1"
$AccountId = "508768431157"
$Root = Split-Path -Parent $PSScriptRoot
$PolicyFile = Join-Path $Root "backend\iam-github-deploy-policy.json"
$InstancePolicyFile = Join-Path $Root "backend\iam-ec2-game-server-instance-policy.json"
$Ec2TrustFile = Join-Path $Root "backend\iam-codedeploy-ec2-trust.json"

Write-Host "=== 1/5 GitHubActionsFightingGameDeploy inline policy ==="
aws iam put-role-policy `
  --role-name GitHubActionsFightingGameDeploy `
  --policy-name GitHubActions `
  --policy-document "file://$PolicyFile"
Write-Host "Updated GitHubActions with codedeploy:ListDeployments."

Write-Host "=== 2/5 Remove misplaced policy from Lambda CodeDeploy service role ==="
$lambdaSvcPolicies = aws iam list-role-policies --role-name CodeDeployServiceRoleForLambda --query PolicyNames --output json | ConvertFrom-Json
if ($lambdaSvcPolicies -contains "CodeDeployPolicy") {
  aws iam delete-role-policy --role-name CodeDeployServiceRoleForLambda --policy-name CodeDeployPolicy
  Write-Host "Removed CodeDeployPolicy from CodeDeployServiceRoleForLambda."
} else {
  Write-Host "CodeDeployPolicy not on CodeDeployServiceRoleForLambda."
}

Write-Host "=== 3/5 EC2 CodeDeploy service role ==="
$roleExists = $false
try {
  aws iam get-role --role-name CodeDeployServiceRoleForEC2 | Out-Null
  $roleExists = $true
} catch {
  $roleExists = $false
}
if (-not $roleExists) {
  aws iam create-role `
    --role-name CodeDeployServiceRoleForEC2 `
    --assume-role-policy-document "file://$Ec2TrustFile" `
    --description "CodeDeploy service role for EC2 game-server fleet" | Out-Null
  Write-Host "Created CodeDeployServiceRoleForEC2."
} else {
  Write-Host "CodeDeployServiceRoleForEC2 already exists."
}
aws iam attach-role-policy `
  --role-name CodeDeployServiceRoleForEC2 `
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole 2>$null
Write-Host "Attached AWSCodeDeployRole."

Write-Host "=== 4/5 EC2 deployment group service role ==="
aws deploy update-deployment-group `
  --application-name FightingGameServerDeploy `
  --current-deployment-group-name FightingGameServer-fleet `
  --service-role-arn "arn:aws:iam::${AccountId}:role/CodeDeployServiceRoleForEC2" `
  --region $Region | Out-Null
Write-Host "FightingGameServer-fleet uses CodeDeployServiceRoleForEC2."

Write-Host "=== 5/5 EC2 instance S3 read policy ==="
aws iam put-role-policy `
  --role-name FightingGameServerInstanceRole `
  --policy-name S3ReadDeployZip `
  --policy-document "file://$InstancePolicyFile"
Write-Host "Updated FightingGameServerInstanceRole S3ReadDeployZip."

Write-Host ""
Write-Host "ListDeployments simulation:"
aws iam simulate-principal-policy `
  --policy-source-arn "arn:aws:iam::${AccountId}:role/GitHubActionsFightingGameDeploy" `
  --action-names codedeploy:ListDeployments `
  --resource-arns "arn:aws:codedeploy:${Region}:${AccountId}:deploymentgroup:FightingGameMatchmakerDeploy/FightingGameMatchmaker-live" `
  --query "EvaluationResults[0].EvalDecision" `
  --output text

Write-Host ""
Write-Host "Done. Re-run GitHub Actions Deploy workflow."

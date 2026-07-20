# Phase 1 — ASG Spot warm pool + MatchMaker assignment

**Date:** 2026-07-20  
**Account:** `508768431157`  
**Region:** `ap-southeast-1`  
**Operator IAM:** `lethanhnhon`

## Goal

Replace hardcoded `WS_ENDPOINT` as the sole source of truth with **warm-pool discovery**: MatchMaker selects a running EC2 instance tagged `Role=FightingGameServer` and writes `wsEndpoint` (+ optional `instanceId`) into `ActiveMatches`. Client contract unchanged (`{ roomId, playerSlot, wsEndpoint }`).

## Live baseline (from inventory)

| Item | Value |
|------|--------|
| VPC | `vpc-09a82bd7e81714079` |
| Public subnets | `subnet-0da5c1428f9e96980` (1a), `subnet-06756dd1fda043257` (1b), `subnet-0e49ce056d87f552f` (1c) |
| Existing game EC2 | `i-0d110a1e699bab029` / `54.151.177.184` / `t3.small` |
| Security group | `sg-096a41cd239e4254a` (`FightingGameServerSG`) — TCP 9000 open |
| Key pair | `FightingGameServer` |
| Source AMI (pre-bake) | `ami-0532913178263be11` |
| MatchMaker Lambda | `FightingGameMatchmaker` (nodejs22.x, not VPC-attached) |
| Lambda role | `FightingGameMatchmaker-role-5ps4pdke` |

## Provisioned resources (fill as created)

| Resource | ID / name |
|----------|-----------|
| Baked AMI | `ami-028351109384f4e6e` (`FightingGameServer-phase1-20260720`) |
| Launch template | `FightingGameServerLT` |
| Auto Scaling Group | `FightingGameServerASG` |
| Existing instance tag | `Role=FightingGameServer` |

## ASG settings

- Instance type: `t3.small` (Spot)
- Min / Desired / Max: `1` / `1` / `2`
- Subnets: all three public subnets above
- Security group: `FightingGameServerSG` only
- Tags (propagate): `Name=FightingGameServer`, `Role=FightingGameServer`, `Project=FightingGame`

## MatchMaker behavior

1. On pair: `DescribeInstances` filter `tag:Role=FightingGameServer` + `running`
2. Pick lexicographically first `instanceId` with a public IP → `ws://<ip>:9000`
3. Write `wsEndpoint`, `instanceId`, `assignedAt`, `status=active` on both match rows
4. If none found: fall back to env `WS_ENDPOINT`; if still empty, re-queue with message (no empty endpoint)

## Deploy Lambda

```powershell
cd backend
npm ci
# zip index.mjs + node_modules (handler file must be named index.mjs at zip root)
aws lambda update-function-code --function-name FightingGameMatchmaker --zip-file fileb://matchmaker.zip --region ap-southeast-1
aws lambda update-function-configuration --function-name FightingGameMatchmaker --timeout 10 --region ap-southeast-1
```

## Verify

```powershell
# Health of current server
Invoke-WebRequest http://54.151.177.184:9000/health -UseBasicParsing

# Tag discovery (what Lambda sees)
aws ec2 describe-instances --region ap-southeast-1 --filters "Name=tag:Role,Values=FightingGameServer" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].{Id:InstanceId,Ip:PublicIpAddress}"
```

Then two Cognito users Find Match and confirm `wsEndpoint` in ActiveMatches matches a tagged instance IP.

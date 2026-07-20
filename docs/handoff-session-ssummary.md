# Fighting Game AWS — Session Handoff Summary
**Date:** 2026-07-20  
**Account:** `508768431157`  
**Region:** `ap-southeast-1`  
**Repo:** https://github.com/Nothingtoread/fighting-game  
**Local path:** `c:\Users\Admin\Downloads\fighting-game-master`  
**Operator IAM:** `lethanhnhon`
---
## Key idea (one paragraph)
This is a **browser-based 2-player fighting game** with a **live-service AWS backend**. Players load the **game client from S3** (static site), **log in via Cognito**, **matchmake via API Gateway → Lambda → DynamoDB**, then connect **WebSocket to an EC2/ASG Spot game server** for input relay. Architecture has four flows: **A** (auth + S3 assets), **R** (matchmaking + live session), **C** (CI/CD deploy), **E** (post-match async analytics). **EC2 does not host the browser game** — only the WebSocket relay on port 9000. The playable UI lives on **S3**.
---
## Architecture (runtime)
Browser (S3 static client) → Cognito login (JWT) → API Gateway POST /join, GET /check → Lambda FightingGameMatchmaker → DynamoDB MatchmakingQueue + ActiveMatches → Client opens wsEndpoint from match payload → EC2/ASG Spot :9000 (WebSocket server.js)


**Frozen client contract:** `{ roomId, playerSlot, wsEndpoint }` — see `docs/phase0-contracts.md`.
---
## AWS resource inventory
| Resource | ID / Value |
|----------|------------|
| Cognito User Pool | `ap-southeast-1_phYoaMUPC` |
| App Client ID | `73ipqvvo7h3u0j3elfqlj23jo3` |
| Identity Pool | `ap-southeast-1:a5d743b9-e4a4-45d2-9cb1-9d214cee574c` |
| API Gateway | `https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod` |
| Lambda MatchMaker | `FightingGameMatchmaker` (nodejs22.x, handler `index.handler`, timeout 10s) |
| Lambda role | `FightingGameMatchmaker-role-5ps4pdke` |
| DynamoDB | `MatchmakingQueue`, `ActiveMatches` (PK: `playerId`) |
| VPC | `vpc-09a82bd7e81714079` |
| Public subnets | `subnet-0da5c1428f9e96980` (1a), `subnet-06756dd1fda043257` (1b), `subnet-0e49ce056d87f552f` (1c) |
| SG (game) | `sg-096a41cd239e4254a` (`FightingGameServerSG`) — TCP 9000, SSH 22 |
| EC2 (original) | `i-0d110a1e699bab029` → `54.151.177.184` (t3.small, On-Demand) |
| EC2 (ASG Spot) | `i-0dc2d586ddc346aaf` → `47.129.204.237` (t3.small) |
| Key pair | `FightingGameServer` |
| AMI (Phase 1 bake) | `ami-028351109384f4e6e` (`FightingGameServer-phase1-20260720`) |
| Test users | `testplayer1`, `testplayer2` / `TestPass123!` |
**Tags on game fleet:** `Role=FightingGameServer`, `Project=FightingGame`
**Lambda env (after Phase 1 deploy):**
`QUEUE_TABLE`, `MATCHES_TABLE`, `WS_ENDPOINT` (fallback), `GAME_SERVER_TAG_KEY=Role`, `GAME_SERVER_TAG_VALUE=FightingGameServer`, `WS_PORT=9000`
**S3 bucket (Phase 2 — name from guide):** `fighting-game-assets-508768431157` (confirm you created this)
---
## Phases — DONE
### Phase 0 — Baseline & contracts ✅
- [x] `docs/phase0-contracts.md` — frozen API, DynamoDB, WebSocket schemas
- [x] Locked decisions: warm pool, EC2 writes post-match (Phase 3), rematch vs Streams constraint
- [x] Smoke: EC2 `/health` 200, API `/join` without token → 401
- [ ] Optional: authenticated `/join`+`/check` in CloudShell; teammate sign-off §9
### Phase 1 — ASG Spot + MatchMaker assignment ✅ (mostly)
- [x] Tag existing EC2 `Role=FightingGameServer`
- [x] ASG Spot instance running with health OK (`47.129.204.237`)
- [x] IAM `FightingGameMatchmakerEC2Describe` on Lambda role
- [x] `backend/lambda-matchmaker.mjs` — `resolveGameEndpoint()` via `DescribeInstances`
- [x] Lambda deployed (`backend/deploy-matchmaker.ps1`)
- [x] `backend/verify-phase1.ps1` — two tagged instances, both health 200
- [x] `docs/phase1-asg.md`
- [ ] Optional: terminate old On-Demand EC2 once Spot-only is trusted
- [ ] Optional: confirm Launch Template + ASG names in Console and document
### Gameplay (prior teammates) ✅
- [x] Cognito + API Gateway + DynamoDB matchmaking
- [x] EC2 WebSocket server + PM2
- [x] Client netcode fixes (playerSlot Number, wsEndpoint, rematch clearSession)
- [x] 2-player online on separate machines (when using local serve + config.js)
---
## Phases — IN PROGRESS
### Phase 2 — Flow C CI/CD 🔄
**Goal:** push `master` → S3 client + Lambda + game-server zip → SSM on fleet
**Repo files added:**
- `.github/workflows/deploy.yml`
- `.github/workflows/ci.yml` (syntax check)
- `backend/game-server/server.js` + `package.json` + `install-from-s3.sh`
- `scripts/generate-config.js`
- `docs/phase2-cicd.md`
**User progress (as of last session):**
1. [x] Fix SSM: attach IAM instance profile with `AmazonSSMManagedInstanceCore` to **both** game instances + ASG launch template
2. [x] Confirm `aws ssm describe-instance-information` shows **Online**
3. [x] Confirm S3 bucket + website hosting + public read policy
4. [ ] Confirm GitHub OIDC role + all secrets (`AWS_DEPLOY_ROLE_ARN`, `ASSETS_BUCKET`, Cognito, `MATCHMAKER_API_BASE`)
5. [ ] Commit `backend/game-server/package-lock.json` (for CI `npm ci`)
6. [ ] Push to `master` → run Deploy workflow
7. [ ] Open **S3 website URL** (not EC2 IP) → login → Find Match → play
8. [ ] Verify SSM command success in Systems Manager → Run Command history
**SSM troubleshooting quick ref:**
- EC2 Details → IAM role must not be empty
- `sudo systemctl status amazon-ssm-agent` on instance
- Region must be `ap-southeast-1`
- Wait 2–5 min after attaching role
---
## Phases — NOT STARTED
### Phase 3 — Flow E (async post-match)
- [ ] AWS Console: follow `docs/phase3-flow-e.md` (table, Streams, IAM, Lambda, trigger)
- [x] Repo: EC2 `server.js` writes `status=finished` on disconnect (option B)
- [x] Repo: `backend/lambda-match-analytics.mjs` + IAM JSON for Console paste
- [ ] Rematch unchanged (`clearSession` deletes ActiveMatches; analytics kept in `MatchAnalytics`)
- [ ] Enable DynamoDB Streams on `ActiveMatches` + Lambda trigger (Console)
- [ ] Create `MatchAnalytics` table + Async Lambda (Console)
### Phase 2+ / production hardening (optional)
- [ ] CloudFront + WAF in front of S3/API
- [ ] `wss://` (Nginx + Certbot on game fleet)
- [ ] CodeDeploy / Lambda aliases (diagram C4)
- [ ] DynamoDB TTL on queue/match rows
- [ ] `POST /leave` endpoint
- [ ] GitHub OIDC only (no access keys)
- [ ] Ephemeral SG IP whitelisting (full architecture diagram)
---
## Important repo files
| File | Purpose |
|------|---------|
| `docs/phase0-contracts.md` | Frozen contracts |
| `docs/phase1-asg.md` | ASG / warm pool notes |
| `docs/phase2-cicd.md` | CI/CD setup runbook |
| `docs/handoff-opencode-flow-r-session2.md` | Prior teammate handoff |
| `backend/lambda-matchmaker.mjs` | MatchMaker source |
| `backend/deploy-matchmaker.ps1` | Deploy Lambda locally |
| `backend/verify-phase1.ps1` | Verify tagged fleet + health |
| `backend/game-server/server.js` | WS relay for CI/SSM |
| `.github/workflows/deploy.yml` | Flow C pipeline |
| `src/config.js` | Local only (gitignored); CI generates for S3 |
---
## Locked design decisions
1. **Warm pool:** ASG keeps healthy instances; MatchMaker picks tagged `Role=FightingGameServer`, not spin-per-match.
2. **Post-match writer (v1):** EC2 game server updates DynamoDB (not client `POST /result`).
3. **Client on S3, server on EC2:** Do not expect game UI at `http://<ec2-ip>:9000`.
4. **wsEndpoint fallback:** env `WS_ENDPOINT=ws://54.151.177.184:9000` until fleet-only is trusted.
---
## What to tell the next chat
> "Continue Fighting Game AWS project. Phase 0 and Phase 1 done. Phase 2 CI/CD in progress — SSM Fleet Manager shows 0 nodes; need to fix instance IAM profile then finish first GitHub Deploy workflow. Phase 3 Flow E not started. Read `docs/handoff-session-summary.md` and `docs/phase2-cicd.md`."
---
*Generated for context handoff — 2026-07-20.*
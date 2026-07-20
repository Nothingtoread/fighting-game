# Handoff — Flow R (EC2 + Online Play) — Session 2

**Purpose:** Paste into OpenCode to continue work. This document covers **only** progress **after** `docs/handoff-ec2-continuation.md` (API Gateway / Cognito / Lambda matchmaking phase was already done).

**Project path:** `C:\Users\tranv\Documents\Codex\2026-07-15\doc\fighting-game-master`

**AWS Region:** `ap-southeast-1`

---

## 1. What Was Completed in This Session

### 1.1 EC2 Game Server (WebSocket)

| Item | Value / Status |
|------|----------------|
| Instance name | `FightingGameServer` |
| Instance ID | `i-0d110a1e699bab029` |
| Instance type | `t3.small` |
| AMI | Ubuntu Server 24.04 LTS |
| **Public IPv4** | `54.151.177.184` |
| Private IPv4 | `172.31.41.242` |
| Security Group | `FightingGameServerSG` — SSH 22, Custom TCP **9000** |
| App path on EC2 | `~/fighting-game-server/` |
| Process manager | PM2 — `fighting-game-server` |
| Health check | `curl http://54.151.177.184:9000/health` → `{"status":"ok","rooms":0}` |

**Note:** Ubuntu is pre-installed on the AMI — no separate OS install needed after EC2 launch.

**EC2 setup steps done by teammate:**
- SSH as `ubuntu`
- `npm init -y`, `npm install ws jsonwebtoken jwks-rsa`
- `server.js` (WebSocket relay + Cognito JWT auth + `/health` endpoint)
- `pm2 start server.js --name fighting-game-server`
- `pm2 save`

---

### 1.2 Lambda Environment Variables (final)

| Key | Value |
|-----|-------|
| `QUEUE_TABLE` | `MatchmakingQueue` |
| `MATCHES_TABLE` | `ActiveMatches` |
| `WS_ENDPOINT` | `ws://54.151.177.184:9000` |

Lambda code reads: `process.env.WS_ENDPOINT` and stores it in `ActiveMatches` as `wsEndpoint` when pairing players.

**Typo fixed in Lambda import:** `ScanCommanda` → `ScanCommand`

**Rematch fix:** Full updated handler in repo at `backend/lambda-matchmaker.mjs` — adds `clearSession()` before re-queueing so **Back to lobby → Find Match again** works.

---

### 1.3 Client Config (`src/config.js` — final)

```js
export const Config = {
  MOCK_AUTH: false,
  COGNITO_REGION: "ap-southeast-1",
  COGNITO_USER_POOL_ID: "ap-southeast-1_phYoaMUPC",
  COGNITO_APP_CLIENT_ID: "73ipqvvo7h3u0j3elfqlj23jo3",
  COGNITO_IDENTITY_POOL_ID: "ap-southeast-1:a5d743b9-e4a4-45d2-9cb1-9d214cee574c",
  MATCHMAKER_API_BASE: "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod",
  MATCHMAKER_POLL_INTERVAL_MS: 2000,
  MATCHMAKER_MAX_POLLS: 60,
  WS_SERVER: "ws://54.151.177.184:9000",
};
```

**Important:** `WS_SERVER` must use **Public IPv4** from EC2 summary (`54.151.177.184`), NOT Private IP (`172.31.41.242`).

---

### 1.4 Cognito Test Users

| Username | Password | Status |
|----------|----------|--------|
| `testplayer1` | `TestPass123!` | Confirmed |
| `testplayer2` | `TestPass123!` | Created for 2-player test |

Create users via Cognito Console → Users → Create user (Don't send invitation, mark email verified, permanent password).

---

### 1.5 End-to-End Test Result

- Login with real Cognito ✅
- Find Match via API Gateway ✅
- Two players on **different machines** can match and enter game ✅
- Player 1 movement works ✅
- WebSocket connects to EC2 ✅

---

## 2. Code Fixes Applied (This Session)

### 2.1 `playerSlot` type bug (critical)

Lambda/DynamoDB returns `playerSlot` as string `"1"` / `"2"`. Strict check `slot === 1` failed → **no keyboard input** for local player.

**Fixed in:**
- `Fighter1/Fighter1.js` — `Number(this.stage.vars.myPlayerSlot)`
- `Fighter2/Fighter2.js` — same
- `index.js` — `Number(match.playerSlot)`, `Number(slot)` in callbacks
- `src/netcode.js` — `Number(playerSlot)`, `Number(msg.yourSlot)`

### 2.2 Player 2 controls (critical)

`Fighter2` used arrow keys (`left`, `right`, `up`) — **Leopard browser does not recognize these**. Only `j` (attack) worked.

**Fix:** Player 2 local controls now use **same keys as Player 1** (correct for 2 separate machines):

| Action | Key |
|--------|-----|
| Left | A |
| Right | D |
| Jump | W |
| Attack | J |

Both players on **different PCs** each use **A/D/W/J** on their own keyboard.

### 2.3 WebSocket URL not using Lambda `wsEndpoint`

`src/netcode.js` `_openSocket()` always used `Config.WS_SERVER`, ignoring `connect(wsEndpoint, ...)`.

**Fix:** Store `_wsEndpoint` in `connect()` and use it in `_openSocket()`.

### 2.4 Back to lobby reset

`index.js` — on **Back to lobby** button:
```js
disconnect();
project = null;
matchmakingAborted = false;
```

### 2.5 Rematch after Back to lobby (Lambda)

**Problem:** Old `ActiveMatches` rows remained. Lambda returned `{ status: "matched" }` immediately on next Find Match without re-queueing → players could not match each other again.

**Fix:** `backend/lambda-matchmaker.mjs` — `clearSession(playerId)` deletes:
- Player's row in `ActiveMatches`
- Opponent's row in `ActiveMatches`
- Both queue rows in `MatchmakingQueue`

Called at start of every `joinQueue()`. Removed early `if (existingMatch) return matched` shortcut.

**Action required:** Deploy this Lambda code in AWS Console if not already done.

---

## 3. Files Changed (Reference for OpenCode)

| File | Change |
|------|--------|
| `Fighter1/Fighter1.js` | `Number(slot)` in getInputs |
| `Fighter2/Fighter2.js` | `Number(slot)` + A/D/W/J for local player |
| `index.js` | Number(playerSlot), lobby reset, netcode loop fix |
| `src/netcode.js` | Use wsEndpoint param, Number slot |
| `src/config.js` | MOCK_AUTH false, WS_SERVER EC2 public IP |
| `backend/lambda-matchmaker.mjs` | **New** — full Lambda with rematch fix |

---

## 4. How to Run & Test

### Start client (each machine)

```bash
cd fighting-game-master
npx.cmd serve .
# Open http://localhost:3000  OR  http://<host-ip>:3000 for remote player
```

### Two-player test (different machines — production-like)

1. **Optional:** Clear DynamoDB `ActiveMatches` + `MatchmakingQueue` if stuck
2. Machine A: login `testplayer1`
3. Machine B: login `testplayer2`
4. Both click **Find Match** within ~5 seconds
5. Click game canvas, use **A/D/W/J**
6. After match: **Back to lobby** → both Find Match again (requires Lambda rematch fix deployed)

### Verify EC2 from local machine

```powershell
curl http://54.151.177.184:9000/health
```

### Verify matchmaking API (CloudShell)

```bash
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id 73ipqvvo7h3u0j3elfqlj23jo3 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testplayer1,PASSWORD="TestPass123!" \
  --region ap-southeast-1 \
  --query "AuthenticationResult.IdToken" --output text)

curl -X POST "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod/join" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"playerId":"testplayer1"}'
```

---

## 5. Known Issues & Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Player enters game alone | Stale `ActiveMatches` row | Clear DynamoDB tables OR deploy Lambda `clearSession` fix |
| Player 2 can't move, only J works | Arrow keys broken in Leopard | Use updated `Fighter2.js` (A/D/W/J) |
| No movement at all | `playerSlot` string vs number | Deploy Fighter/index/netcode Number() fixes |
| Can't rematch after lobby | Old match not cleared | Deploy `backend/lambda-matchmaker.mjs` |
| WebSocket fails | Wrong IP or port 9000 closed | Use Public IP, check Security Group + PM2 |
| API Gateway Test 401 with token | JWT wrapped in Console UI | Test with CloudShell curl instead |
| Only focused browser tab gets keys | Normal browser behavior | Each player uses their own machine/tab |

---

## 6. Architecture State (Flow R)

```
[Done] Cognito login
[Done] API Gateway POST /join, GET /check + Cognito authorizer
[Done] Lambda MatchMaker → DynamoDB queue/match
[Done] EC2 WebSocket server (PM2, port 9000)
[Done] Client MOCK_AUTH=false, live matchmaking + WS
[Done] 2-player online on separate machines (with code fixes)
[Pending deploy verify] Lambda rematch fix (clearSession)
[Not started] CI/CD (Flow C)
[Not started] CloudFront/WAF custom domain, wss://
[Not started] Cognito self-registration UI (Sign up button)
```

---

## 7. Suggested Next Tasks for OpenCode

1. **Verify Lambda rematch fix deployed** — test Back to lobby → Find Match × 3 rounds
2. **Add POST /leave endpoint** (optional cleaner than clear-on-join only)
3. **EC2 `pm2 startup`** — survive instance reboot
4. **Delete expired matches** via TTL on DynamoDB `expiresAt` attribute
5. **Sign up UI** on login screen for production users
6. **wss://** via Nginx + Certbot on EC2 for production browsers
7. **DynamoDB TTL / cleanup job** for orphaned queue entries

---

## 8. Key URLs & IDs (Quick Reference)

```
EC2 Public IP:     54.151.177.184
WS URL:            ws://54.151.177.184:9000
API Gateway:       https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod
User Pool ID:      ap-southeast-1_phYoaMUPC
App Client ID:     73ipqvvo7h3u0j3elfqlj23jo3
Identity Pool ID:  ap-southeast-1:a5d743b9-e4a4-45d2-9cb1-9d214cee574c
DynamoDB tables:   MatchmakingQueue, ActiveMatches
Lambda env:        QUEUE_TABLE, MATCHES_TABLE, WS_ENDPOINT
```

---

*Generated: 2026-07-17 — Session 2 handoff (Flow R EC2 + online play fixes). Prior session covered API Gateway deploy only — see `docs/handoff-ec2-continuation.md`.*

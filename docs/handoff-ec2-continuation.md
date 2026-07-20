# Handoff Document — Fighting Game AWS Backend (for EC2 Game Server teammate)

**Purpose:** Paste this entire document into a new ChatGPT (or other AI) chat so the next teammate can continue with **EC2 WebSocket Game Server** deployment without re-discovering context.

**Project path (local):** `C:\Users\tranv\Documents\Codex\2026-07-15\doc\fighting-game-master`

**AWS Region:** `ap-southeast-1` (Singapore)

**Workshop reference:** `Các bước Workshop.docx` (completed through API Gateway deploy, Hình 84)

**Architecture reference:** `tong_hop_du_an_game_backend_aws.docx` + in-repo docs `docs/auth-login.md`, `docs/game-netcode.md`

---

## 1. Project Summary

This is a **browser-based 2-player fighting game** (Leopard/Scratch-style client) with a **live-service AWS backend**:

| Flow | Component | Status |
|------|-----------|--------|
| **Flow A** | Cognito login + Identity Pool + S3 assets | ✅ Done |
| **Flow R (partial)** | API Gateway → Lambda MatchMaker → DynamoDB | ✅ Done & tested |
| **Flow R (partial)** | EC2 WebSocket game server (input relay) | ❌ **NOT done — YOUR TASK** |
| **Flow C** | CI/CD (GitHub Actions, CodeDeploy) | ❌ Another teammate |
| **Flow E** | DynamoDB Streams → Async Lambda → Analytics | ❌ Out of scope for now |

The **previous teammate finished matchmaking API**. The game client can **log in with real Cognito** and **poll matchmaking via API Gateway**, but **cannot play online yet** because no WebSocket server exists.

---

## 2. What Was Completed (verified working)

### 2.1 Amazon Cognito

| Resource | Value |
|----------|-------|
| User Pool ID | `ap-southeast-1_phYoaMUPC` |
| User Pool name | `User pool - aapp2h` (display name in console) |
| App Client ID | `73ipqvvo7h3u0j3elfqlj23jo3` |
| App Client name | `FightingGame` |
| Auth flow enabled | `ALLOW_USER_PASSWORD_AUTH` (for browser + `initiate-auth` CLI) |
| Identity Pool ID | `ap-southeast-1:a5d743b9-e4a4-45d2-9cb1-9d214cee574c` |
| Identity Pool name | `FightingGameIdentityPool` |
| IAM role (authenticated) | `FightingGameAuthenticatedRole` |

**Test user created:**
- Username: `testplayer1`
- Email: `test1@example.com`
- Password: `TestPass123!` (permanent, status **Confirmed**)
- Create a second user (e.g. `testplayer2`) to test 2-player matchmaking.

**Get IdToken (CloudShell):**
```bash
aws cognito-idp initiate-auth \
  --client-id 73ipqvvo7h3u0j3elfqlj23jo3 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testplayer1,PASSWORD="TestPass123!" \
  --region ap-southeast-1 \
  --query "AuthenticationResult.IdToken" \
  --output text
```

### 2.2 DynamoDB

| Table | Partition key | Status |
|-------|---------------|--------|
| `MatchmakingQueue` | `playerId` (String) | Active |
| `ActiveMatches` | `playerId` (String) | Active |

### 2.3 Lambda MatchMaker

- Created per Workshop (Hình 31–51)
- IAM inline policy attached for DynamoDB read/write on both tables
- Environment variables configured (table names, region, etc.)
- **Lambda test succeeded** for player 1 join + player 2 join → match pairing works at Lambda level
- Function name: check AWS Console (not recorded in this handoff — teammate should verify in Lambda console)

### 2.4 API Gateway (REST API)

| Setting | Value |
|---------|-------|
| API name | `FightingGameMatchmakerAPI` |
| Stage | `prod` |
| Invoke URL | `https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod` |
| Routes | `POST /join`, `GET /check` |
| Integration | Lambda proxy → MatchMaker function |
| Authorizer | Cognito User Pool authorizer (name ~ `FightinggameCognitoAuthorizer`) |
| Token source | `Authorization` header (Bearer JWT) |
| CORS | Enabled on `/join` and `/check` (Allow-Origin `*`, methods POST/GET/OPTIONS) |

**Verified via CloudShell (NOT via API Gateway Console Test — long JWT breaks in Console Headers UI):**

```bash
# POST /join → 200 {"status":"queued"}
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id 73ipqvvo7h3u0j3elfqlj23jo3 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testplayer1,PASSWORD="TestPass123!" \
  --region ap-southeast-1 \
  --query "AuthenticationResult.IdToken" --output text)

curl -i -X POST \
  "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod/join" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"playerId":"testplayer1"}'

# GET /check → 200 {"status":"waiting"}
curl -i \
  "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod/check?playerId=testplayer1" \
  -H "Authorization: Bearer $TOKEN"
```

**Without token:** `POST /join` returns **401 Unauthorized** (authorizer working).

### 2.5 Game Client Config (`src/config.js`)

Currently set to **live auth + live matchmaking**, but **no live WebSocket**:

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
  WS_SERVER: "ws://localhost:9000",   // ← MUST UPDATE after EC2 deploy
};
```

**Client behavior with current config:**
1. Login → real Cognito ✅
2. Lobby → "Searching for opponent... (N/60)" → real API polling ✅
3. When 2 players matched → client tries WebSocket → **fails** (no EC2 server) ❌

**Run client locally:**
```bash
cd fighting-game-master
npx serve .
# Open http://localhost:3000
# Login: testplayer1 / TestPass123!
```

---

## 3. Matchmaking API Contract (client ↔ Lambda)

Both routes require header: `Authorization: Bearer <Cognito IdToken>`

### POST `/join`
- **Body:** `{ "playerId": "<cognito sub or userId>" }`
- **Response:**
  - `{ "status": "queued" }` — waiting for opponent
  - `{ "status": "matched", "match": { "roomId", "playerSlot", "wsEndpoint" } }` — immediate match

### GET `/check?playerId=<userId>`
- **Response:**
  - `{ "status": "waiting" }`
  - `{ "status": "matched", "match": { "roomId", "playerSlot", "wsEndpoint" } }`

**Critical for EC2 teammate:** When matched, Lambda must return a valid **`wsEndpoint`** pointing to the deployed game server, e.g.:
- Dev: `ws://<EC2_PUBLIC_IP>:9000`
- Prod: `wss://game.yourdomain.com`

The client calls `connect(match.wsEndpoint, ...)` in `index.js` after match is found.

**Known client code note:** `src/netcode.js` function `_openSocket()` currently connects using `Config.WS_SERVER` in some code paths instead of the `wsEndpoint` parameter passed to `connect()`. After EC2 deploy, verify/fix so the client uses `match.wsEndpoint` from Lambda response. See `src/netcode.js` lines ~174–176.

---

## 4. EC2 Game Server — YOUR TASK (Flow R / G3)

Read **`docs/game-netcode.md`** in the repo — it contains the full wire protocol and a reference Node.js server.

### 4.1 What the server must do

1. Listen on WebSocket (default port **9000**)
2. On connect, client sends `auth` message with Cognito `idToken`, `roomId`, `slot`
3. Verify JWT via Cognito JWKS: `https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_phYoaMUPC/.well-known/jwks.json`
4. Register socket in in-memory room map: `rooms[roomId][slot] = socket`
5. When both slots connected → broadcast `match_start` to both
6. Relay `inputs` messages from each player to opponent as `opponent_inputs`
7. On disconnect → send `match_end` to opponent

### 4.2 Wire protocol (summary)

**Client → Server:**
```json
{ "type": "auth", "idToken": "<JWT>", "roomId": "...", "slot": 1 }
{ "type": "inputs", "l": 0, "r": 1, "j": 0, "a": 0 }
```

**Server → Client:**
```json
{ "type": "match_start", "yourSlot": 1 }
{ "type": "opponent_inputs", "l": 0, "r": 1, "j": 1, "a": 0 }
{ "type": "match_end", "winner": 2 }
```

### 4.3 Suggested EC2 setup (from game-netcode.md)

1. Launch EC2 (Ubuntu 24.04, t3.medium for testing; architecture doc mentions Spot/Graviton for prod)
2. Security Group: open **9000/TCP** (WebSocket) + **22/TCP** (SSH)
3. Install Node.js, `ws`, `jsonwebtoken`, `jwks-rsa`
4. Deploy reference `server.js` from `docs/game-netcode.md`
5. Environment variables:
   ```bash
   export COGNITO_REGION="ap-southeast-1"
   export COGNITO_USER_POOL_ID="ap-southeast-1_phYoaMUPC"
   export PORT=9000
   ```
6. Run with PM2 for persistence
7. Update Lambda MatchMaker env var / logic so `wsEndpoint` in match response = `ws://<EC2_PUBLIC_IP>:9000`
8. Update client `src/config.js` → `WS_SERVER: "ws://<EC2_PUBLIC_IP>:9000"` (or fix netcode to use Lambda's wsEndpoint)
9. For production: Nginx + Certbot → `wss://` domain

### 4.4 Architecture context (from project design doc)

Full production architecture also includes:
- Matchmaker Lambda in **private subnet** with VPC Gateway Endpoint → DynamoDB
- VPC Interface Endpoint → EC2 API (for dynamic Security Group rules per player IP)
- Game fleet on **public subnet** with direct client UDP/TCP connection
- **Phase 1 for internship/demo:** Simple EC2 with open port 9000 is sufficient to unblock end-to-end gameplay

---

## 5. CI/CD — Different Teammate (Flow C)

Not started. Includes:
- GitHub Actions → CodeDeploy
- Lambda alias traffic shifting
- EC2 AMI updates for game fleet
- Upload game assets/patches to S3

Do **not** block EC2 prototype on CI/CD.

---

## 6. Testing End-to-End (after EC2 is up)

1. Two browser tabs (or two machines)
2. Login as `testplayer1` and `testplayer2` (create second Cognito user if needed)
3. Both click **Play** simultaneously
4. Matchmaking should return `status: matched` with same `roomId`, different `playerSlot` (1 and 2)
5. Both clients connect WebSocket → receive `match_start` → game begins
6. Inputs from player 1 should appear as opponent inputs on player 2's screen

---

## 7. Troubleshooting Notes (from implementation session)

| Issue | Cause | Fix |
|-------|-------|-----|
| API Gateway Console Test returns 401 with token | Headers textarea wraps long JWT across lines | Use CloudShell `curl` instead |
| `admin-initiate-auth` fails | `ALLOW_ADMIN_USER_PASSWORD_AUTH` not enabled on app client | Use `initiate-auth` with `USER_PASSWORD_AUTH` |
| Cognito user "Force change password" | Admin-created user default state | `admin-set-user-password ... --permanent` in CloudShell |
| Matchmaking stuck on "Searching (N/60)" | Only 1 player in queue | Need 2 concurrent players |
| Game loads but WS fails after match | No EC2 server / wrong WS_SERVER | Deploy EC2 + update wsEndpoint |

---

## 8. Key Repo Files for Next Teammate

| File | Purpose |
|------|---------|
| `docs/game-netcode.md` | **Primary guide** — wire protocol + reference server.js + EC2 steps |
| `docs/auth-login.md` | Cognito setup reference |
| `src/config.js` | Client AWS config (gitignored) |
| `src/matchmaking.js` | API client (`/join`, `/check`) |
| `src/netcode.js` | WebSocket client |
| `src/auth.js` | Cognito login wrapper |
| `index.js` | UI flow: login → lobby → match → connect WS → game |

---

## 9. Scope Boundary (what NOT to redo)

The following are **done and tested** — do not recreate unless broken:
- Cognito User Pool + Identity Pool
- DynamoDB tables
- Lambda MatchMaker function + IAM
- API Gateway REST API + Cognito authorizer + CORS + prod deploy
- Client config for Cognito + API Gateway

**Start from:** EC2 WebSocket server + Lambda `wsEndpoint` update + client WS connection fix if needed.

---

*Generated: 2026-07-17 — handoff from matchmaking/API Gateway implementation session.*

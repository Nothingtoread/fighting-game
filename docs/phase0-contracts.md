# Phase 0 — Baseline and Contracts

**Date:** 2026-07-19  
**Region:** `ap-southeast-1`  
**Repo:** https://github.com/Nothingtoread/fighting-game  
**Purpose:** Freeze client-facing API / DynamoDB / WebSocket contracts and inventory live AWS resources before ASG (Phase 1), CI/CD (Phase 2), and Flow E async (Phase 3).

Phase 0 does **not** build ASG, CodeDeploy, or Async Lambda. Later phases may change **where** `wsEndpoint` comes from and **what** is written on match end — not the shapes below unless the whole team agrees.

---

## 1. Live AWS inventory

Values sourced from `docs/handoff-opencode-flow-r-session2.md`, `docs/handoff-ec2-continuation.md`, and `src/config.js`. Smoke tests run from this machine on 2026-07-19.

| Resource | ID / Value | Verify | Smoke result (2026-07-19) |
|----------|------------|--------|---------------------------|
| Cognito User Pool | `ap-southeast-1_phYoaMUPC` | Exists; app client; `USER_PASSWORD_AUTH` | Not re-verified here (AWS CLI not installed on this machine). Use CloudShell curl from handoff. |
| Cognito App Client | `73ipqvvo7h3u0j3elfqlj23jo3` | Name ~ `FightingGame` | Same as above |
| Cognito Identity Pool | `ap-southeast-1:a5d743b9-e4a4-45d2-9cb1-9d214cee574c` | Exists (S3 assets later; not blocking Phase 0) | Same as above |
| DynamoDB | `MatchmakingQueue`, `ActiveMatches` | PK = `playerId` (String) | Schema frozen from [`backend/lambda-matchmaker.mjs`](../backend/lambda-matchmaker.mjs) |
| Lambda MatchMaker | Name in Console (not recorded in handoff) | Env: `QUEUE_TABLE`, `MATCHES_TABLE`, `WS_ENDPOINT` | Confirm in Console before Phase 1 deploy |
| API Gateway | `FightingGameMatchmakerAPI` stage `prod` | `POST /join`, `GET /check`, Cognito authorizer | **Verified:** `POST /join` without `Authorization` → **401** |
| API Invoke URL | `https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod` | Live | Reachable |
| EC2 game server | Instance `i-0d110a1e699bab029` | Public IP, port 9000 | Instance ID from handoff (not re-queried) |
| EC2 Public IPv4 | `54.151.177.184` | Health + WS | **Verified:** `GET http://54.151.177.184:9000/health` → `200` `{"status":"ok","rooms":0}` |
| WS URL (current) | `ws://54.151.177.184:9000` | Client `Config.WS_SERVER` / Lambda `WS_ENDPOINT` | Matches live health host |
| Test users | `testplayer1` / `testplayer2` | Password `TestPass123!` (Confirmed) | From handoff; re-confirm in Cognito Console if login fails |

### Smoke commands (CloudShell — full auth path)

AWS CLI was **not** available on the local Windows machine used for this inventory. Run the following in AWS CloudShell to complete authenticated `/join` + `/check` verification:

```bash
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id 73ipqvvo7h3u0j3elfqlj23jo3 \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=testplayer1,PASSWORD="TestPass123!" \
  --region ap-southeast-1 \
  --query "AuthenticationResult.IdToken" --output text)

curl -s -X POST \
  "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod/join" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'

curl -s \
  "https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod/check" \
  -H "Authorization: Bearer $TOKEN"
```

**Expected shapes:** `{ "status": "queued" }` or `{ "status": "matched", "match": { ... } }` on join; `{ "status": "waiting" }` or matched payload on check.

**Note:** MatchMaker uses Cognito authorizer claim `sub` as `playerId`, not the username in any request body (`getPlayerId` in `backend/lambda-matchmaker.mjs`).

### IAM access checklist (escalate before Phase 1 if missing)

| Capability | Needed for |
|------------|------------|
| EC2 launch templates, ASG, Spot | Phase 1 fleet |
| EC2 security groups | Phase 1 (and optional ephemeral IP rules later) |
| VPC Interface Endpoint (EC2 API) or interim public EC2 API from Lambda | Phase 1 G1 control-plane |
| Update MatchMaker Lambda + env + IAM | Phase 1 assignment logic |
| CodeDeploy / Lambda aliases / GitHub OIDC | Phase 2 Flow C |
| DynamoDB Streams + create Async Lambda + analytics table/S3 | Phase 3 Flow E |

---

## 2. Frozen client ↔ MatchMaker API contract

**Do not change** for Phase 1–3 unless the whole team agrees.

### Auth

- Header: `Authorization: Bearer <Cognito IdToken>`
- Unauthenticated → `401 Unauthorized`

### `POST /join`

| Case | Response body |
|------|----------------|
| Queued | `{ "status": "queued" }` |
| Immediate match | `{ "status": "matched", "match": { "roomId", "playerSlot", "wsEndpoint" } }` |

### `GET /check`

| Case | Response body |
|------|----------------|
| Waiting | `{ "status": "waiting" }` |
| Matched | `{ "status": "matched", "match": { "roomId", "playerSlot", "wsEndpoint" } }` |

### `match` object (immutable for client)

| Field | Type | Notes |
|-------|------|--------|
| `roomId` | string (UUID) | Shared by both players |
| `playerSlot` | number **or** string `"1"` / `"2"` | Client coerces with `Number(...)` in `index.js` / fighters / netcode |
| `wsEndpoint` | string | e.g. `ws://54.x.x.x:9000` — **source changes in Phase 1**, shape stays |

Client consumers (must keep working unchanged):

- [`src/matchmaking.js`](../src/matchmaking.js) — `findMatch()` returns `{ roomId, playerSlot, wsEndpoint }`
- [`index.js`](../index.js) — `connect(match.wsEndpoint, match.roomId, playerSlot, ...)`

### Out of scope (document only)

- `POST /leave` — not implemented; rematch today = `clearSession()` at start of next `/join` in [`backend/lambda-matchmaker.mjs`](../backend/lambda-matchmaker.mjs).

---

## 3. Frozen DynamoDB schemas

### `MatchmakingQueue` (as implemented today)

| Attribute | Meaning |
|-----------|---------|
| `playerId` (PK) | Cognito `sub` |
| `joinedAt` | unix seconds |
| `expiresAt` | `joinedAt + 300` (TTL intent; enable DynamoDB TTL attribute later) |

### `ActiveMatches` (as implemented today)

One row **per player** (not per room). Both players in a match share `roomId` and `wsEndpoint`.

| Attribute | Meaning |
|-----------|---------|
| `playerId` (PK) | Cognito `sub` |
| `roomId` | Shared room UUID |
| `playerSlot` | `1` or `2` |
| `opponentId` | Other player's `sub` |
| `wsEndpoint` | Same URL on both rows |
| `createdAt` | unix seconds |
| `expiresAt` | `createdAt + 3600` |

### Phase 1 additions (ops only — not required by client)

| Attribute | Meaning |
|-----------|---------|
| `instanceId` | Assigned EC2 instance ID (optional) |
| `assignedAt` | unix seconds when capacity was selected (optional) |

### Post-match fields (agreed now; implement in Phase 3)

EC2 game server writes these on `match_end` / disconnect (v1 — no client `POST /result`).

| Attribute | Type | Set by |
|-----------|------|--------|
| `status` | `"active"` \| `"finished"` | EC2 game server |
| `winner` | `1` \| `2` \| `null` | EC2 on `match_end` / disconnect |
| `endedAt` | unix seconds | EC2 |
| `endReason` | `"normal"` \| `"disconnect"` \| `"forfeit"` | EC2 |

**Flow E stream filter:** process `MODIFY` (or `INSERT`) where `status == "finished"`.

**Analytics sink (Phase 3 pick):** second DynamoDB table `MatchAnalytics` (demo default) or S3 JSON. Phase 0 only freezes the **match result attributes** above.

### Rematch vs Streams constraint (critical for Phase 3)

Today, rematch **deletes** both players’ `ActiveMatches` rows inside `clearSession()` on the next `/join`.

For DynamoDB Streams to capture results reliably, Phase 3 must do one of:

1. **Update** rows to `status: "finished"` (and result fields) **before** any delete, or  
2. Write a **separate** analytics item that is never deleted by rematch, or  
3. Stop deleting finished rows immediately (TTL cleanup instead).

Do not enable Streams until this write path is decided and implemented.

---

## 4. Frozen WebSocket wire protocol

Reference: [`docs/game-netcode.md`](game-netcode.md), [`src/netcode.js`](../src/netcode.js). Current EC2 `server.js` is the Phase 1 AMI reference.

### Client → server

```json
{ "type": "auth", "idToken": "<jwt>", "roomId": "<roomId>", "slot": 1 }
{ "type": "inputs", "l": 0, "r": 1, "j": 0, "a": 0 }
```

`l` / `r` / `j` / `a` are `0` or `1`.

### Server → client

```json
{ "type": "match_start", "yourSlot": 1 }
{ "type": "opponent_inputs", "l": 0, "r": 0, "j": 1, "a": 0 }
{ "type": "match_end", "winner": 1 }
```

`winner` is `1`, `2`, or `null` (disconnect / error).

### Health

`GET http://<host>:9000/health` → `{ "status": "ok", "rooms": <number> }`

---

## 5. Locked decisions (later phases)

| Decision | Locked value | Rationale |
|----------|--------------|-----------|
| Provisioning model | **Warm pool** — ASG keeps ≥1 healthy game instance; MatchMaker **selects** one and writes `wsEndpoint` | Internship-friendly; avoids spin-per-match latency |
| Post-match writer | **EC2 game server** updates DynamoDB on `match_end` / disconnect | Matches netcode design notes; no new client API in v1 |
| `wsEndpoint` fallback | Prefer **explicit error / 503** over empty string if no capacity; keep `process.env.WS_ENDPOINT` only as interim/dev fallback until ASG is live | Empty `wsEndpoint` already causes bad client connections |
| Instance selection tags (intent) | e.g. `Role=FightingGameServer` | Used by MatchMaker Describe / registry in Phase 1 |
| Diagram G1 meaning | VPC Interface Endpoint → **EC2 API** (control plane), not a packet router into the public subnet | Per architecture review |

### Phase 1 provisioning contract (design only — not implemented in Phase 0)

1. ASG maintains warm Spot instances (health on `:9000/health`).
2. On pair, MatchMaker finds one healthy instance and sets  
   `wsEndpoint = "ws://" + publicIp + ":9000"` on both `ActiveMatches` rows.
3. Client behavior unchanged: still opens that URL from the match payload.
4. Today’s code path remains until Phase 1 ships:

```js
// backend/lambda-matchmaker.mjs (current)
const wsEndpoint = process.env.WS_ENDPOINT || "";
```

---

## 6. Ownership and repo boundary

| Party | Owns | Does not redo |
|-------|------|----------------|
| **This track (you)** | Flow C (CI/CD), ASG/Spot + MatchMaker assignment of `wsEndpoint`, Flow E (Streams → Async Lambda → analytics) | Cognito pools, API Gateway authorizer, `/join`/`/check` response shapes, client WS message types |
| **Teammates** | Cognito, API GW routes, current MatchMaker pairing logic, client UI/netcode, current single EC2 prototype | — |

**Shared touchpoint:** MatchMaker Lambda — Phase 1 edits only the **assignment of `wsEndpoint`** (and optional `instanceId`). Coordinate deploy with whoever currently owns the function in Console.

**Repo:** https://github.com/Nothingtoread/fighting-game  

- Confirm push access to `master` or a feature branch before Phase 2.  
- Current CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)) is lint/build stub only — Flow C replaces/extends it.

---

## 7. Non-goals until Phase 1+

Phase 0 explicitly does **not**:

- Create ASG, launch templates, AMIs, or VPC endpoints  
- Deploy CodeDeploy, Lambda aliases, or GitHub OIDC  
- Create Async Lambda or enable DynamoDB Streams  
- Change client UI or `match` JSON shape  
- Implement `POST /leave`, `wss://`, CloudFront/WAF, or ephemeral SG IP whitelisting  

---

## 8. Exit criteria

- [x] Live resources inventoried; EC2 `/health` and API unauth `401` smoke-tested locally  
- [ ] Authenticated `/join` + `/check` smoke-tested in CloudShell (run commands in §1)  
- [x] API / `match` / WS / DynamoDB schemas written  
- [x] Warm-pool + EC2-as-result-writer + rematch/Streams constraint recorded  
- [x] Ownership boundary and CI repo notes recorded  
- [ ] IAM gaps escalated with account admin if ASG/Streams/CodeDeploy denied  
- [x] Ready to start Phase 1 without changing client contracts  

---

## 9. Sign-off

| Role | Name | Date | Signature / ack |
|------|------|------|-----------------|
| Flow C / ASG / Flow E owner | | | |
| MatchMaker / API owner (teammate) | | | |
| Client / netcode owner (teammate) | | | |

By signing, teammates agree that `/join`, `/check`, the `match` object, WebSocket message types, and current DynamoDB PK layouts stay frozen unless the team revises this document together.

---

*Generated: 2026-07-19 — Phase 0 baseline contracts.*

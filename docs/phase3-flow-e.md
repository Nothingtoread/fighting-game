# Phase 3 — Flow E (Console-only runbook)

**Goal:** Match end on EC2 → `ActiveMatches` `status=finished` → DynamoDB Streams → `FightingGameMatchAnalytics` Lambda → `MatchAnalytics` table.

**Repo already has the code.** You only set up AWS resources below, then push/deploy the game-server.

Region: `ap-southeast-1` · Account: `508768431157`

---

## What the repo already does

| File | Purpose |
|------|---------|
| `backend/game-server/server.js` | On disconnect, updates both players’ `ActiveMatches` rows to `finished` |
| `backend/lambda-match-analytics.mjs` | Paste into Lambda (or zip as `index.mjs`) |
| `backend/iam-ec2-activematches-finish-policy.json` | Attach to EC2 instance role |
| `backend/iam-match-analytics-lambda-policy.json` | Attach to analytics Lambda role |
| `backend/iam-ec2-game-server-instance-policy.json` | Updated S3 + DynamoDB finish (optional full replace) |

Rematch / `clearSession()` is **unchanged** (option B). Analytics live in `MatchAnalytics` and are not deleted by rematch.

---

## Console steps (do these in order)

### 1) Create table `MatchAnalytics`

1. DynamoDB → **Tables** → **Create table**
2. Table name: `MatchAnalytics`
3. Partition key: `roomId` (String)
4. Capacity: **On-demand**
5. Create

### 2) Enable Streams on `ActiveMatches`

1. DynamoDB → table **ActiveMatches** → **Exports and streams**
2. Enable DynamoDB stream → view type: **New and old images**
3. Save — note the stream is now on

### 3) EC2 instance role — finish write

1. IAM → Roles → **FightingGameServerInstanceRole**
2. **Add permissions** → **Create inline policy** → JSON
3. Paste contents of `backend/iam-ec2-activematches-finish-policy.json`
4. Name: `ActiveMatchesFinishWrite` → Create

Applies to both fleet instances that use this instance profile.

### 4) Lambda execution role

1. IAM → Roles → **Create role**
2. Trusted entity: **AWS service** → **Lambda**
3. Attach managed policy: **AWSLambdaBasicExecutionRole**
4. Role name: `FightingGameMatchAnalyticsRole` → Create
5. Open the role → **Add permissions** → **Create inline policy** → JSON
6. Paste `backend/iam-match-analytics-lambda-policy.json`
7. Name: `MatchAnalyticsStreamWrite` → Create

### 5) Create Lambda `FightingGameMatchAnalytics`

1. Lambda → **Create function**
2. Name: `FightingGameMatchAnalytics`
3. Runtime: **Node.js 22.x**
4. Architecture: x86_64
5. Execution role: use existing → `FightingGameMatchAnalyticsRole`
6. Create

**Code:**

1. Delete the default `index.mjs` stub if present
2. Open `backend/lambda-match-analytics.mjs` from this repo
3. Paste the full file into the Lambda editor as **`index.mjs`**
4. Handler: `index.handler`
5. **Configuration** → **Environment variables** → Add:
   - Key: `ANALYTICS_TABLE`
   - Value: `MatchAnalytics`
6. **Deploy**

### 6) Attach DynamoDB stream trigger

1. Still on the Lambda → **Add trigger**
2. Source: **DynamoDB**
3. DynamoDB table: **ActiveMatches**
4. Batch size: `10`
5. Starting position: **Latest**
6. Leave other defaults → Add

Wait until the trigger shows **Enabled**.

### 7) Deploy the updated game-server

Push `master` (or re-run **Deploy** workflow) so CodeDeploy rolls out the new `server.js` + AWS SDK deps.

Until that deploy succeeds, EC2 will not write `finished` and nothing will appear in `MatchAnalytics` from real games.

---

## Verify (Console)

### Quick stream smoke (no game)

1. DynamoDB → `ActiveMatches` → Explore table → Create item (or edit an existing test row)
2. Set attributes including: `status` = `finished`, `roomId` = `room-smoke-1`, `winner` = `1`, `endedAt` = current unix seconds, `endReason` = `normal`, `playerId` = any string
3. Wait 10–30 seconds
4. Open table **MatchAnalytics** → look for `roomId` = `room-smoke-1`
5. CloudWatch → Log groups → `/aws/lambda/FightingGameMatchAnalytics` if empty

### Live match

1. Open S3 website → two players → Find Match → disconnect one
2. `ActiveMatches`: those players show `status` = `finished`
3. `MatchAnalytics`: same `roomId` present
4. Find Match again — rematch works; analytics row remains

---

## Checklist

- [ ] `MatchAnalytics` table created
- [ ] Streams enabled on `ActiveMatches` (new and old images)
- [ ] Inline policy on `FightingGameServerInstanceRole`
- [ ] Role `FightingGameMatchAnalyticsRole` + inline stream/write policy
- [ ] Lambda `FightingGameMatchAnalytics` with pasted code + env
- [ ] Stream trigger Enabled
- [ ] Game-server deployed via GitHub Actions / CodeDeploy
- [ ] Smoke or live match → row in `MatchAnalytics`

---

*Phase 3 Flow E — option B (separate analytics table; rematch delete unchanged).*

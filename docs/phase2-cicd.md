# Phase 2 — Flow C (CI/CD)

**Goal:** Push code on `master` → browser client on **S3**, MatchMaker **Lambda** updated, WebSocket **game-server** rolled out to all EC2/ASG instances tagged `Role=FightingGameServer`.

## Important: what goes where

| Artifact | Where it runs | How players use it |
|----------|---------------|-------------------|
| **Browser client** (`index.html`, fighters, assets) | **S3** (static site) | Open S3 website URL or CloudFront URL in browser |
| **WebSocket relay** (`backend/game-server/server.js`) | **EC2 / ASG Spot** | Client connects after matchmaking (`wsEndpoint`) |
| **MatchMaker** (`backend/lambda-matchmaker.mjs`) | **Lambda** | `/join`, `/check` via API Gateway |

EC2 does **not** host the playable browser game. If you open `http://<ec2-ip>:9000` you only get `/health` and WebSocket — not the fighting game UI. That UI must be served from **S3** (or local `npx serve` during dev).

---

## Pipeline (repo)

Workflow: [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)

On push to `master`:

1. **Lambda** — zip `index.mjs` → `FightingGameMatchmaker`
2. **Client** — copy static files + generated `src/config.js` → `s3://ASSETS_BUCKET/`
3. **Game server** — zip `backend/game-server/` → `s3://ASSETS_BUCKET/deploy/game-server.zip`
4. **EC2 fleet** — SSM Run Command on instances with `Role=FightingGameServer` → download zip, `npm ci`, `pm2 restart`

Local scripts:

- `scripts/generate-config.js` — builds `config.js` from env (used in CI)
- `backend/game-server/install-from-s3.sh` — what SSM runs on each instance

---

## AWS setup (you do once)

### 1) S3 bucket for client + deploy artifacts

```powershell
aws s3 mb s3://fighting-game-assets-508768431157 --region ap-southeast-1
aws s3 website s3://fighting-game-assets-508768431157/ --index-document index.html
```

Enable **Block Public Access** off only if you use static website hosting for demo (or use CloudFront + OAC for production).

Bucket policy (public read for static demo — tighten for prod):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::fighting-game-assets-508768431157/*"
  }]
}
```

**Client URL after deploy:**  
`http://fighting-game-assets-508768431157.s3-website-ap-southeast-1.amazonaws.com`

### 2) GitHub OIDC → IAM role

1. IAM → Identity provider → Add **GitHub** OIDC (`token.actions.githubusercontent.com`)
2. Create role `GitHubActionsFightingGameDeploy` trusted to your repo `Nothingtoread/fighting-game`
3. Attach policy (adjust bucket name):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["lambda:UpdateFunctionCode", "lambda:GetFunction"],
      "Resource": "arn:aws:lambda:ap-southeast-1:508768431157:function:FightingGameMatchmaker"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::fighting-game-assets-508768431157",
        "arn:aws:s3:::fighting-game-assets-508768431157/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:SendCommand"],
      "Resource": [
        "arn:aws:ssm:ap-southeast-1::document/AWS-RunShellScript",
        "arn:aws:ec2:ap-southeast-1:508768431157:instance/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:SendCommand"],
      "Resource": "arn:aws:ssm:ap-southeast-1:508768431157:*"
    }
  ]
}
```

Copy role ARN → GitHub repo **Settings → Secrets → Actions**:

| Secret | Example |
|--------|---------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::508768431157:role/GitHubActionsFightingGameDeploy` |
| `ASSETS_BUCKET` | `fighting-game-assets-508768431157` |
| `COGNITO_USER_POOL_ID` | `ap-southeast-1_phYoaMUPC` |
| `COGNITO_APP_CLIENT_ID` | `73ipqvvo7h3u0j3elfqlj23jo3` |
| `COGNITO_IDENTITY_POOL_ID` | `ap-southeast-1:a5d743b9-...` |
| `MATCHMAKER_API_BASE` | `https://6whg1d5qca.execute-api.ap-southeast-1.amazonaws.com/prod` |
| `WS_SERVER` | leave empty — client uses `wsEndpoint` from matchmaking |

### 3) EC2 instance profile (SSM + S3 read on fleet)

Each game server needs:

- **SSM agent** (Ubuntu AMIs include it)
- IAM instance profile with:
  - `AmazonSSMManagedInstanceCore`
  - Inline S3 read on `deploy/game-server.zip`:

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject"],
  "Resource": "arn:aws:s3:::fighting-game-assets-508768431157/deploy/*"
}
```

Attach profile to:
- Existing `i-0d110a1e699bab029`
- ASG launch template (so new Spot instances get it)

Console: EC2 → Instances → Actions → Security → Modify IAM role.

### 4) Cognito callback (if using hosted UI later)

For S3 website origin, add the S3 website URL to Cognito app client callback URLs if needed.

---

## First deploy

1. Complete AWS setup above
2. Push to `master` on GitHub (or **Actions → Deploy → Run workflow**)
3. Open S3 website URL → login → Find Match
4. Verify SSM on instances: Systems Manager → Run Command → command history
5. Health on fleet: `backend/verify-phase1.ps1`

---

## What Phase 2 does *not* include yet

- CodeDeploy blue/green or Lambda aliases (can add later for diagram C4)
- CloudFront + WAF in front of S3/API
- Automatic AMI bake + ASG instance refresh (SSM deploy is enough for demo)
- Flow E async (Phase 3)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| S3 site loads but login fails | Check generated `config.js` secrets in GitHub |
| Match works but WS fails | SSM deploy failed — check instance IAM + SSM agent |
| Spot instance no game | Expected — game UI is on S3, not EC2 |
| `npm ci` fails in CI on game-server | Run `npm install` once locally in `backend/game-server` and commit `package-lock.json` |

---

*Phase 2 — Flow C CI/CD. Depends on Phase 0 contracts and Phase 1 ASG + MatchMaker discovery.*

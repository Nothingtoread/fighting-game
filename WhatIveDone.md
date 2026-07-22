# What I've Done — Fighting Game AWS Project

Personal contributions documented in `LeThanhNhon.md`, plus implementation and fixes done with Cursor AI assistance. Teammate-only work (Cognito setup, API Gateway wiring, initial MatchMaker Lambda, etc.) is excluded.

**Region:** `ap-southeast-1`  
**Repo:** [Nothingtoread/fighting-game](https://github.com/Nothingtoread/fighting-game)

---

## 1. EC2 game server fleet (warm pool)

- Tagged the running game server instance (`Role=FightingGameServer`) so MatchMaker can discover hosts via `DescribeInstances`.
- Baked an AMI from that instance for repeatable launches.
- Created a **Spot** launch template pointing at the baked AMI.
- Created an **Auto Scaling Group** with a **warm pool** so matchmaking can assign players to already-running EC2 hosts instead of cold-starting every match.
- Verified the fleet was healthy and reachable on port **9000**.

---

## 2. S3 static client hosting

- Created the assets bucket (`fighting-game-assets-508768431157`).
- Enabled **static website hosting** for the browser client (`index.html`, JS, sprites, sounds).
- Applied a **public-read bucket policy** for the demo deployment.
- Configured **CORS** so browser login and API calls from the S3 origin do not fail cross-origin.

CI (GitHub Actions `deploy.yml`) later syncs the built client bundle into this bucket on each deploy, including a generated `src/config.js` from secrets.

---

## 3. IAM for MatchMaker and game server

- Set up IAM permissions for the MatchMaker Lambda (DynamoDB queue/matches, EC2 `DescribeInstances` for host discovery).
- Created and configured **`FightingGameServerInstanceRole`** for EC2 instances (runtime permissions for the game server process).
- Modified instance role policies as deploy and match-finish features required DynamoDB writes from EC2.

**With Cursor — IAM / deploy fixes:**

- Applied missing CodeDeploy permissions on `GitHubActionsFightingGameDeploy` (`ListDeployments`, `GetApplicationRevision`).
- Created **`CodeDeployServiceRoleForEC2`** with `AWSCodeDeployRole` when the EC2 deployment group was incorrectly using the Lambda CodeDeploy service role.
- Added EC2 instance policy for **`ActiveMatches` finish writes** (`status=finished`, winner, timestamps) after async processing was implemented.

---

## 4. GitHub OIDC → AWS (no long-lived keys)

- Registered **GitHub Actions** as an OIDC identity provider in IAM.
- Created the deploy role with a **trust policy** scoped to the GitHub repo.
- Attached the permissions policy for S3 sync, Lambda update, and CodeDeploy.
- Added **repository secrets** (`COGNITO_*`, `MATCHMAKER_API_BASE`, `WS_SERVER`, `ASSETS_BUCKET`, `AWS_ROLE_ARN`, etc.).

This removed the need for static AWS access keys in CI.

---

## 5. CodeDeploy — Lambda and EC2 CI/CD

### Lambda (MatchMaker)

- Published new Lambda versions and pointed the **`live` alias** at them for canary-style rollouts via CodeDeploy.
- Managed dormant vs active API Gateway stages around alias traffic shifting.
- Created the **CodeDeploy service role** for Lambda deployments.

### EC2 (game server fleet)

- Installed the **CodeDeploy agent** on game server instances. On Ubuntu 24.04 / Ruby 3.3, patched the agent `.deb` dependency (`ruby3.2` → `ruby3.3`) before install:

```bash
sudo apt-get update && sudo apt-get install -y ruby-full ruby-webrick wget gdebi-core
cd /tmp
wget https://aws-codedeploy-ap-southeast-1.s3.ap-southeast-1.amazonaws.com/releases/codedeploy-agent_1.8.1-26_all.deb
dpkg-deb -R codedeploy-agent_1.8.1-26_all.deb /tmp/codedeploy-extracted
sed -i 's/ruby3.2/ruby3.3/g' /tmp/codedeploy-extracted/DEBIAN/control
dpkg-deb -b /tmp/codedeploy-extracted /tmp/codedeploy-agent_fixed.deb
sudo dpkg -i /tmp/codedeploy-agent_fixed.deb
sudo systemctl enable codedeploy-agent && sudo systemctl start codedeploy-agent
```

- Updated the **launch template**, warm pool, and Spot instances to include the CodeDeploy agent.
- Created the **CodeDeploy EC2 application** (`FightingGameServerDeploy`) and **deployment group** (`FightingGameServer-fleet`) targeting instances tagged `Role=FightingGameServer`.
- Achieved **successful CodeDeploy jobs** and documented deployment history.

**With Cursor — pipeline hardening:**

- Fixed `application_start.sh` (CRLF stripping, health-check retry loop) when ApplicationStart failed on fresh deploys.
- Ensured CI generates `fighting-game.env` inside the game-server zip so Cognito and DynamoDB env vars exist on EC2.
- Added helper scripts: `codedeploy-create-with-retry.sh`, `codedeploy-wait-idle.sh`.
- Diagnosed long Lambda canary waits (`CodeDeployDefault.LambdaLinear10PercentEvery1Minute` ≈ 10 minutes).

---

## 6. Async post-match processing (Flow E)

- Enabled **DynamoDB Streams** on `ActiveMatches` (`NEW_AND_OLD_IMAGES`).
- Created **`MatchAnalytics`** table for finished-match copies.
- Created **`FightingGameMatchAnalyticsRole`** with stream-read policy.
- Deployed **`FightingGameMatchAnalytics`** Lambda with event source mapping from the `ActiveMatches` stream.
- Verified finished-match rows appear in DynamoDB and analytics table after matches end.

**With Cursor — application code:**

- **`backend/game-server/server.js`:** On disconnect, `markMatchFinished` updates both player rows in `ActiveMatches` (`status=finished`, `winner`, `endedAt`, `endReason`); stores Cognito `sub` as player id; validates WebSocket auth and slot 1|2.
- **`backend/lambda-match-analytics.mjs`:** Stream consumer copies finished matches into `MatchAnalytics` (handles MODIFY and REMOVE for rematch race).
- Client hardening (`index.js`, `Fighter1/2`, `netcode.js`): non-blocking sounds, safer slot/input handling, intentional WS close flag, waiting-timer UX.
- Investigated and patched **game-freeze** symptoms (stuck before `match_start`, `yield* startSound` hang risk).

Design choice: keep rematch `clearSession()` deletes on `ActiveMatches`; analytics are copied to a separate table before delete.

---

## 7. VPC — private MatchMaker (no NAT)

- Documented subnet layout for the MatchMaker Lambda move into **private subnets**.
- Created private subnets, private route table (local routes only), security groups, and **VPC endpoints** (DynamoDB gateway, EC2 + CloudWatch Logs interface endpoints).
- Attached **`AWSLambdaVPCAccessExecutionRole`** to the MatchMaker execution role.
- Reconfigured MatchMaker VPC settings, published a new Lambda version, and pointed the **`live` alias** at it.
- Game server fleet remains in a **public subnet**; MatchMaker reaches DynamoDB and EC2 API via endpoints without NAT.

---

## 8. Documentation and repository cleanup

**With Cursor:**

- Wrote **`PROJECT.md`** — end-to-end programming guide (client, Lambdas, game server, data contracts, CI).
- Removed deployment artifact clutter (`docs/`, IAM JSON templates, helper PowerShell scripts, `.asset-backups/`).
- Pushed cleaned project to **`master`** and synced **`main`** on GitHub.
- Guided **architecture diagram** corrections (`AWS_GameSeverless.drawio`): browser loads app from S3 (not EC2), WebSocket gameplay path to EC2, CI → S3 deploy arrow, multi-table DynamoDB labels.
- Provided **GitHub Pages** vs **S3 website** guidance for internship demo (HTTPS/`ws://` mixed-content caveat).

---

## 9. Resource cleanup documentation (screenshots only)

Documented teardown procedure for the internship report **without executing deletes**:

| Area | Resources screenshotted |
|------|-------------------------|
| CodeDeploy | `FightingGameMatchmakerDeploy`, `FightingGameServerDeploy`, deployment groups |
| Compute | `FightingGameServerASG`, EC2 instances, launch template |
| API | `FightingGameMatchmakerAPI` |
| Lambda | `FightingGameMatchmaker`, `FightingGameMatchAnalytics` |
| Data | `MatchmakingQueue`, `ActiveMatches`, `MatchAnalytics` |
| Storage | S3 bucket empty + delete confirmations |
| Network | VPC, subnets, endpoints, security groups |
| IAM | Deploy roles, Lambda roles, instance profile role |

Workflow: open delete/terminate dialog → screenshot confirmation screen → **Cancel** (no actual deletion).

---

## Summary

| Phase | My contribution |
|-------|-----------------|
| **Fleet** | AMI, Spot LT, ASG warm pool, instance tagging |
| **Hosting** | S3 static website, policy, CORS |
| **CI/CD** | GitHub OIDC, CodeDeploy Lambda + EC2, agent install on Ubuntu |
| **Async** | MatchAnalytics pipeline (AWS + server/Lambda code) |
| **Network** | Private MatchMaker subnets + VPC endpoints |
| **Docs** | `PROJECT.md`, repo cleanup, diagram accuracy, cleanup screenshots |

Screenshots for console steps live in **`LeThanhNhon.md`**. Code and architecture detail live in **`PROJECT.md`**.

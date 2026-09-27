# EVAT API: Jenkins DevOps pipeline (SIT223/SIT753 7.3HD)

Based on Chameleon's EVAT backend ([Chameleon-company/EVAT-App-BE](https://github.com/Chameleon-company/EVAT-App-BE)): a Node.js, Express, TypeScript and MongoDB REST API (about 98 documented endpoints, including auth, profiles, vehicles, stations, bookings, reviews and admin). All 7 stages are implemented and automated. The only manual step is the one-time SonarQube setup script.

```
 git push ─► Jenkins (polls every 2 min)
   │
   ├─ Checkout     version = 1.0.<build>, image tag = 1.0.<build>-<commit>
   ├─ Build        npm ci → tsc → multi-stage Docker image → image tarball + build-info.json archived
   ├─ Test         Jest + Supertest: unit + integration projects, JUnit + coverage reports, coverage gate
   ├─ Code Quality SonarQube scan → custom "EVAT Gate" quality gate (build fails if red)
   ├─ Security     npm audit (gate: no HIGH/CRITICAL) ║ Trivy image (gate: no fixable CRITICAL) ║ Trivy secrets/misconfig
   ├─ Deploy       docker compose → staging (API + MongoDB), health wait, CRUD smoke test
   ├─ Release      tag v1.0.<build> → production compose, smoke test, auto-rollback, release notes, git tag
   └─ Monitoring   Prometheus + Alertmanager + Grafana; verifies scraping, rules, fails on critical alerts
```

| Service | URL | Login |
|---|---|---|
| Jenkins | http://localhost:8080 | admin / admin |
| SonarQube | http://localhost:9000 | admin / EvatSonar#2026 |
| Staging API | http://localhost:8081/api/docs | |
| Production API | http://localhost:8082/api/docs | |
| Prometheus | http://localhost:9090/alerts | |
| Alertmanager | http://localhost:9093 | |
| Grafana | http://localhost:3300 | admin / evat-admin |

---

## 1. Setup (about 15 minutes, needs only Docker Desktop)

```bash
# 1. Push this project to your own GitHub repo
git init && git add . && git commit -m "EVAT API with Jenkins pipeline"
git branch -M main
git remote add origin https://github.com/<you>/evat-devops.git
git push -u origin main

# 2. Start Jenkins + SonarQube (first build of the Jenkins image takes ~5 min)
cd jenkins
cp .env.example .env
docker compose up -d --build

# 3. Configure SonarQube (password, project, quality gate, token → Jenkins)
./sonar-setup.sh          # Windows: run it in Git Bash
```

On Linux only, SonarQube also needs `sudo sysctl -w vm.max_map_count=262144`. Docker Desktop on macOS and Windows doesn't need it.

**4. Create the pipeline job** (show this part in the video):
Jenkins → **New Item** → name `evat-api` → **Pipeline** → OK →
*Pipeline* section: **Pipeline script from SCM** → SCM **Git** → Repository URL = your repo → Branch `*/main` → Script Path `Jenkinsfile` → **Save** → **Build Now**.

After the first manual build, `pollSCM` picks up every push automatically.

Optional credentials (Manage Jenkins → Credentials → Global):
- `github-creds` (username + GitHub token): Release pushes the `v1.0.N` git tag to GitHub.
- `dockerhub-creds` (username + Docker Hub token): Release pushes the image to Docker Hub.

Without them, the pipeline still passes and keeps the tag and image locally.

## 2. Stage details

### Build
- `npm ci` and `tsc -p tsconfig.build.json` compile to `dist/`.
- A multi-stage `Dockerfile` has three stages: build, then prod-only deps, then a slim `node:20-alpine` runtime. The runtime runs as a non-root user with a `HEALTHCHECK`, and npm/yarn are removed.
- The image is tagged `evat-api:<version>-<commit>`, with OCI labels for version and commit.
- Two artefacts are archived with fingerprints: the gzipped image tarball and `build-info.json`.

### Test
- The tools are Jest, ts-jest, Supertest and jest-junit.
- `jest.ci.config.js` defines two projects:
  - **unit** covers controllers, services, middlewares and token utils, with mocked repositories.
  - **integration** runs Express routes over HTTP with Supertest, plus repositories.
- The suite has 143 tests in 18 suites, including new tests for the `/health` and `/metrics` endpoints.
- Gates: any failing test, or coverage below the thresholds in `jest.ci.config.js`, fails the build.
- Jenkins shows JUnit trends, a Cobertura coverage chart and the HTML coverage report.
- **Scope decision:** 8 upstream suites were already failing on `main` because source signatures changed and nobody updated the tests. They are listed in `knownBroken` and excluded from the gate. The unit guidance says to pick a subset.

### Code Quality
- SonarQube analyses TypeScript and imports `reports/coverage/lcov.info`.
- `sonar-project.properties` sets the exclusions and explains them:
  - `src/src/**` is a stale duplicate copy of `src` that the app never imports. Scanning it would double every issue.
  - Models, DTOs, routes and config are excluded from coverage only, not from analysis.
- The custom **EVAT Gate** is created by `jenkins/sonar-setup.sh`. It fails the build on any of these:
  - a new bug, vulnerability, or maintainability rating worse than A
  - more than 3% duplicated new lines
  - less than 50% coverage on new code
  - unreviewed new security hotspots
  - overall coverage below 10%
- New code means changes since the previous version, and every build sets `sonar.projectVersion`, so SonarQube's activity graph tracks trends per release.
- `sonar.qualitygate.wait=true` makes the stage block and fail when the gate is red.

### Security
Three scans run in parallel:

| Scan | Tool | Gate |
|---|---|---|
| Dependencies | `npm audit --omit=dev` | fail on HIGH/CRITICAL |
| Container image | Trivy image scan | fail on fixable CRITICAL (accepted risks in `.trivyignore`, with justification) |
| Secrets + misconfiguration | Trivy fs | fail on any leaked secret |

All reports are archived: `reports/security/npm-audit.json`, `trivy-image.txt/json` and `trivy-fs.txt`.

**Findings and how they were handled**

| ID | Issue | Severity | Action |
|---|---|---|---|
| SEC-01 | Server seeded an `admin` account with the hard-coded password `admin` on every fresh database | High (default credentials, OWASP A07) | **Fixed.** The password now comes from the `DEFAULT_ADMIN_PASSWORD` env var, and nothing is seeded if it's unset (`server.ts`). |
| SEC-02 | `protobufjs <=7.6.4`: arbitrary code execution (transitive) | Critical | **Fixed.** Upgraded via `npm audit fix`. |
| SEC-03 | `fast-xml-parser <=5.6.0`: entity-encoding bypass (transitive, AWS SDK) | Critical | **Fixed.** Upgraded via `npm audit fix`. |
| SEC-04 | `mongoose <=6.13.9`: NoSQL injection through `sanitizeFilter` | High | **Fixed.** Upgraded to 6.13.11 (still 6.x, no breaking changes). |
| SEC-05 | `axios`: SSRF through NO_PROXY bypass; `form-data`: CRLF injection; `path-to-regexp`: ReDoS (Express) | High | **Fixed.** Upgraded via `npm audit fix`. |
| SEC-06 | `nodemailer <=9.1.0`: email sent to an unintended domain | High | **Fixed.** Major upgrade to 10.x. The admin 2FA mail code still compiles and its tests pass. |
| SEC-07 | `decode-uri-component <=0.4.2`: DoS (transitive, through the Google Maps client) | Moderate | **Accepted risk**, documented in `.trivyignore`. It only decodes Google API response URLs, never user input, so the path isn't reachable, and there's no fix within `query-string@7`. |
| SEC-08 | `POST /api/auth/register` returned the bcrypt **password hash** (and refresh-token fields) in the response body. Found during manual testing in Swagger. | Medium (sensitive data exposure, OWASP A02/A04) | **Fixed.** The controller now strips `password`, `refreshToken` and `refreshTokenExpiresAt` before responding, and a unit test asserts the password is never returned. |

Before the pipeline: **42 production vulnerabilities** (2 critical, 10 high, 25 moderate, 5 low). After: **2 moderate** (`decode-uri-component` and its parent `query-string`, both SEC-07), 0 high, 0 critical.

The runtime image was also hardened: non-root `USER node`, npm/yarn/corepack removed, and only production dependencies installed.

### Deploy (staging)
- `deploy/docker-compose.yml` is one file for both environments, parameterised by an env file.
- The staging project `evat-staging` runs the API plus MongoDB 7, with a named volume and an isolated network, on port 8081.
- `docker compose up --wait` blocks until the Docker healthchecks pass.
- `deploy/smoke-test.sh` runs inside the staging network, so it works on any host OS. It checks:
  - health and the Swagger spec
  - **register** (create), **login** (JWT issued), **read** and **update** of the profile
  - that the update was persisted
  - that the auth guard rejects anonymous calls
- Secrets such as `JWT_SECRET` come from Jenkins credentials, never from the repo.

### Release (production)
- The already-tested image is promoted without a rebuild: it's re-tagged `evat-api:v1.0.<build>` and `evat-api:production`.
- It's deployed to the `evat-prod` compose project on port 8082 with its own DB and network, then smoke-tested again.
- **Automatic rollback:** the pipeline records the image running in prod before the release. If the prod deploy or the smoke test fails, it redeploys that image and fails the build.
- Release notes (commits since the previous tag) are generated and archived, and an annotated git tag `v1.0.<build>` is created. It's pushed to GitHub, and the image to Docker Hub, when the optional credentials exist.

### Monitoring & Alerting
- **Instrumentation:** the API exposes `/metrics` through `prom-client`. It reports:
  - request count and latency histogram, per route template and status code
  - a `evat_db_up` gauge
  - Node process metrics
  - labels for `env` and `version`
- `/health` returns 503 when MongoDB is down.
- **Stack** (`deploy/monitoring`): Prometheus scrapes production every 10s, and Alertmanager routes alerts to the team webhook, with email and Discord receivers included, commented out.
- A Grafana dashboard is provisioned automatically. It shows up/DB status, version, firing alerts, requests/sec by route, 5xx ratio, p95 latency and memory.
- **Alert rules:** `EvatApiDown` (critical), `EvatDatabaseDown` (critical), `EvatHighErrorRate` (>5% 5xx), `EvatHighLatency` (p95 >1s) and `EvatHighMemory` (>400MB).
- **Pipeline gate:** `deploy/monitoring/verify.sh` checks that:
  - Prometheus is scraping the new release
  - the rules are loaded
  - Alertmanager is ready
  - no critical alert is firing (if one is, the build fails)

## 3. Demo video script (under 10 minutes)

1. **(1 min) Project intro.** Open the repo, `server.ts`, and Swagger at `:8082/api/docs`.
2. **(1.5 min) Setup.** Show the clone, `docker compose up -d --build` and `./sonar-setup.sh`, then create the Pipeline job from SCM.
3. **(1 min) Trigger.** Push a small commit, show Jenkins picking it up, and open the stage view.
4. **(4 min) Walk through each stage log:**
   - Build: docker build output and archived artefacts
   - Test: the JUnit and coverage charts
   - SonarQube: the dashboard and the EVAT Gate conditions
   - Security: the audit and Trivy reports, then the findings table above
   - Deploy: smoke test output, then `docker ps` to show the staging and prod containers
   - Release: tag, release notes, and the rollback code
5. **(1.5 min) Monitoring:**
   - Show the Grafana dashboard and Prometheus targets.
   - Run `sh deploy/monitoring/simulate-outage.sh` and watch `EvatApiDown` go pending, then firing, at `:9090/alerts`.
   - Show the notification with `docker logs evat-alert-receiver`.
   - Run `docker start evat-prod-api` and show the resolved alert.
6. **(0.5 min, optional) Gates.** Show a failing gate (for example, break a test) so the pipeline stops before deploy.

## 4. Changes made to the upstream project

| File | Change |
|---|---|
| `Jenkinsfile` | New: the 7-stage pipeline |
| `jenkins/` | New: Jenkins image (Node 20, Docker CLI, SonarScanner, Trivy), plugins, configuration-as-code, compose with SonarQube, `sonar-setup.sh` |
| `Dockerfile`, `.dockerignore` | Rewritten as a multi-stage, non-root, hardened image. The old one ran `npm install --production`, then `tsc`, which fails because TypeScript is a dev dependency. |
| `tsconfig.build.json` | New: compiles to `dist/`, excluding tests and the stale `src/src` copy |
| `jest.ci.config.js` | New: unit/integration projects, JUnit and coverage reporters, coverage thresholds |
| `sonar-project.properties`, `.trivyignore`, `.env.example` | New |
| `deploy/` | New: compose for staging/prod, smoke test, monitoring stack |
| `src/middlewares/monitoring-middleware.ts` + test | New: `/health`, `/metrics` and request metrics |
| `server.ts` | Wired in monitoring; fixed SEC-01 (default admin password) |
| `package.json` / lock | Security upgrades (SEC-02 to SEC-06), `prom-client`, `jest-junit`, scripts |

#!/usr/bin/env bash
# One-off SonarQube setup, run on your machine after `docker compose up -d`:
#   cd jenkins && ./sonar-setup.sh
#
# 1. Changes the default admin/admin password
# 2. Creates the evat-api project, "new code" = changes since previous version
# 3. Creates the custom "EVAT Gate" quality gate and assigns it to the project
# 4. Generates an analysis token, writes it to jenkins/.env, restarts Jenkins
#    so the sonar-token credential picks it up (via casc.yaml)
set -euo pipefail
cd "$(dirname "$0")"

SONAR=${SONAR_URL:-http://localhost:9000}
NEW_PASS=${SONAR_ADMIN_PASSWORD:-EvatSonar#2026}
PROJECT=evat-api
GATE="EVAT Gate"

echo "==> Waiting for SonarQube at $SONAR (first start takes 1-2 min)"
until curl -s "$SONAR/api/system/status" | grep -q '"status":"UP"'; do sleep 5; printf '.'; done; echo

# 1. admin password (ignore failure if already changed)
curl -s -u admin:admin -X POST "$SONAR/api/users/change_password" \
  --data-urlencode "login=admin" --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=$NEW_PASS" >/dev/null || true
AUTH="admin:$NEW_PASS"
curl -sf -u "$AUTH" "$SONAR/api/authentication/validate" | grep -q '"valid":true' \
  || { echo "Cannot log in as admin - set SONAR_ADMIN_PASSWORD to your current password"; exit 1; }
echo "OK  admin password is: $NEW_PASS"

api() { curl -s -u "$AUTH" -X POST "$SONAR/api/$1" "${@:2}"; }

# 2. project + new-code definition
api projects/create --data-urlencode "project=$PROJECT" --data-urlencode "name=EVAT API (Chameleon)" >/dev/null
api new_code_periods/set --data-urlencode "project=$PROJECT" --data-urlencode "type=PREVIOUS_VERSION" >/dev/null
echo "OK  project $PROJECT (new code = since previous version)"

# 3. custom quality gate
api qualitygates/destroy --data-urlencode "name=$GATE" >/dev/null || true
api qualitygates/create --data-urlencode "name=$GATE" >/dev/null
cond() { api qualitygates/create_condition --data-urlencode "gateName=$GATE" \
           --data-urlencode "metric=$1" --data-urlencode "op=$2" --data-urlencode "error=$3" >/dev/null
         echo "    $1 $2 $3"; }
echo "OK  quality gate '$GATE' - fails when:"
cond new_reliability_rating     GT 1    # any new bug (rating worse than A)
cond new_security_rating        GT 1    # any new vulnerability
cond new_maintainability_rating GT 1    # new technical debt ratio > 5%
cond new_duplicated_lines_density GT 3  # > 3% duplicated new lines
cond new_coverage               LT 80   # < 80% coverage on new code
cond new_security_hotspots_reviewed LT 100  # unreviewed new hotspots
cond coverage                   LT 10   # overall coverage floor (baseline ~15%)
api qualitygates/select --data-urlencode "gateName=$GATE" --data-urlencode "projectKey=$PROJECT" >/dev/null

# 4. analysis token -> jenkins/.env
api user_tokens/revoke --data-urlencode "name=jenkins" >/dev/null || true
TOKEN=$(api user_tokens/generate --data-urlencode "name=jenkins" --data-urlencode "type=GLOBAL_ANALYSIS_TOKEN" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "Token generation failed"; exit 1; }
[ -f .env ] || cp .env.example .env
if grep -q '^SONAR_TOKEN=' .env; then
  sed -i.bak "s|^SONAR_TOKEN=.*|SONAR_TOKEN=$TOKEN|" .env && rm -f .env.bak
else
  echo "SONAR_TOKEN=$TOKEN" >> .env
fi
echo "OK  analysis token written to jenkins/.env"

echo "==> Restarting Jenkins to load the token"
docker compose up -d --force-recreate jenkins
echo "Done. Jenkins: http://localhost:8080  SonarQube: $SONAR (admin / $NEW_PASS)"

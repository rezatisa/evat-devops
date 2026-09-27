#!/bin/sh
# Post-deployment smoke test. Exercises a real CRUD flow against a running
# environment: health -> docs -> register -> login -> read profile -> update
# profile -> read it back -> auth guard rejects anonymous calls.
# Usage: sh smoke-test.sh http://api:8080
set -eu
BASE="${1:?base url required}"
EMAIL="smoke_$(date +%s)_$$@evat.test"
PASS="Sm0keTest!2026"
fail() { echo "SMOKE FAIL: $*"; exit 1; }
code() { curl -s -o /tmp/body -w '%{http_code}' "$@"; }

echo "==> Smoke testing $BASE"

for i in $(seq 1 30); do
  [ "$(code "$BASE/health")" = "200" ] && break
  echo "   waiting for /health ($i/30)"; sleep 2
done
[ "$(code "$BASE/health")" = "200" ] || fail "/health not 200: $(cat /tmp/body)"
echo "OK  GET  /health -> $(cat /tmp/body)"

[ "$(code "$BASE/api-docs/json")" = "200" ] || fail "swagger spec not served"
echo "OK  GET  /api-docs/json"

c=$(code -X POST "$BASE/api/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\",\"firstName\":\"Smoke\",\"lastName\":\"Test\",\"mobile\":\"0400000000\"}")
[ "$c" = "201" ] || fail "register returned $c: $(cat /tmp/body)"
echo "OK  POST /api/auth/register -> 201 (create)"

c=$(code -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
[ "$c" = "200" ] || fail "login returned $c: $(cat /tmp/body)"
TOKEN=$(sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p' /tmp/body)
[ -n "$TOKEN" ] || fail "no accessToken in login response"
echo "OK  POST /api/auth/login -> 200 (token issued)"

c=$(code "$BASE/api/auth/profile" -H "Authorization: Bearer $TOKEN")
[ "$c" = "200" ] || fail "get profile returned $c: $(cat /tmp/body)"
grep -q "$EMAIL" /tmp/body || fail "profile does not contain registered email"
echo "OK  GET  /api/auth/profile -> 200 (read)"

c=$(code -X PUT "$BASE/api/auth/profile" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"firstName":"Updated"}')
[ "$c" = "200" ] || fail "update profile returned $c: $(cat /tmp/body)"
echo "OK  PUT  /api/auth/profile -> 200 (update)"

code "$BASE/api/auth/profile" -H "Authorization: Bearer $TOKEN" >/dev/null
grep -q "Updated" /tmp/body || fail "profile update was not persisted"
echo "OK  GET  /api/auth/profile -> update persisted"

c=$(code "$BASE/api/vehicle")
[ "$c" = "401" ] || [ "$c" = "403" ] || fail "unauthenticated /api/vehicle returned $c (expected 401/403)"
echo "OK  GET  /api/vehicle without token -> $c (auth guard works)"

echo "==> All smoke tests passed for $BASE"

#!/bin/sh
# Runs inside the monitoring network. Verifies Prometheus is scraping the
# production API, that alert rules are loaded, and fails the build if any
# critical alert is firing for production.
set -eu
PROM=http://prometheus:9090
AM=http://alertmanager:9093

echo "==> Waiting for Prometheus to scrape evat-api-prod"
ok=""
for i in $(seq 1 30); do
  r=$(curl -s "$PROM/api/v1/query" --data-urlencode 'query=up{job="evat-api-prod"}' || true)
  case "$r" in *'"value":['*'"1"]'*) ok=1; break;; esac
  echo "   target not up yet ($i/30)"; sleep 3
done
[ -n "$ok" ] || { echo "FAIL: Prometheus cannot scrape the production API"; echo "$r"; exit 1; }
echo "OK  target evat-api-prod is UP"

r=$(curl -s "$PROM/api/v1/query" --data-urlencode 'query=evat_db_up{env="prod"}')
echo "OK  evat_db_up = $(echo "$r" | sed -n 's/.*"value":\[[^,]*,"\([0-9]*\)"\].*/\1/p')"

rules=$(curl -s "$PROM/api/v1/rules" | grep -o '"name":"Evat[A-Za-z]*"' | sed "s/\"name\"://" | sort -u | tr '\n' ' ')
[ -n "$rules" ] || { echo "FAIL: alert rules not loaded"; exit 1; }
echo "OK  alert rules loaded: $rules"

curl -sf "$AM/-/ready" >/dev/null || { echo "FAIL: Alertmanager not ready"; exit 1; }
echo "OK  Alertmanager ready"

echo "==> Active alerts: $(curl -s "$PROM/api/v1/alerts" | grep -o '"alertname":"[A-Za-z]*"' | sed "s/\"name\"://" | sort -u | tr '\n' ' ')"
firing=$(curl -s "$PROM/api/v1/query" --data-urlencode 'query=ALERTS{alertstate="firing",severity="critical"}' \
  | grep -o '"alertname":"[A-Za-z]*"' | sed "s/\"name\"://" | sort -u | tr '\n' ' ' || true)
if [ -n "$firing" ]; then
  echo "FAIL: critical alert(s) firing in production: $firing"; exit 1
fi
echo "==> Monitoring healthy: no critical alerts firing"

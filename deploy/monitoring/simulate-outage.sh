#!/bin/sh
# DEMO helper: stops the production API so you can show the alert firing.
#   1. sh deploy/monitoring/simulate-outage.sh
#   2. watch http://localhost:9090/alerts  (EvatApiDown: pending -> firing ~40s)
#   3. docker logs -f evat-alert-receiver   (Alertmanager's notification arrives)
#   4. docker start evat-prod-api            (alert resolves, "resolved" notification sent)
set -e
echo "Stopping evat-prod-api to simulate an outage..."
docker stop evat-prod-api
echo "Done. Open http://localhost:9090/alerts and watch EvatApiDown fire (~40s)."
echo "Then run: docker logs -f evat-alert-receiver"
echo "Recover with: docker start evat-prod-api"

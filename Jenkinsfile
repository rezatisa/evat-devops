// =============================================================================
// EVAT API - Jenkins CI/CD pipeline (SIT223/SIT753 7.3HD)
//
// Build -> Test -> Code Quality -> Security -> Deploy (staging)
//       -> Release (production, with automatic rollback) -> Monitoring
//
// Runs on the Jenkins image in ./jenkins (Node 20, Docker CLI, sonar-scanner,
// Trivy). Credentials used (created automatically by ./jenkins/casc.yaml):
//   sonar-token        Secret text  - SonarQube analysis token
//   evat-jwt-staging   Secret text  - JWT secret for the staging API
//   evat-jwt-prod      Secret text  - JWT secret for the production API
//   github-creds       User/token   - OPTIONAL, pushes the release git tag
//   dockerhub-creds    User/token   - OPTIONAL, pushes the release image
// =============================================================================
pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
    disableConcurrentBuilds()
  }

  triggers {
    // Poll GitHub every 2 minutes so every push runs the pipeline
    // (use a GitHub webhook instead if Jenkins is reachable from the internet)
    pollSCM('H/2 * * * *')
  }

  environment {
    APP_NAME      = 'evat-api'
    CI            = 'true'
    STAGING_NET   = 'evat-staging-net'
    PROD_NET      = 'evat-prod-net'
    MONITOR_NET   = 'evat-monitoring-net'
    CURL_IMAGE    = 'curlimages/curl:8.10.1'
  }

  stages {

    // -------------------------------------------------------------------------
    stage('Checkout') {
      steps {
        checkout scm
        script {
          def pkgVersion = sh(script: "node -p \"require('./package.json').version\"", returnStdout: true).trim()
          def (major, minor) = pkgVersion.tokenize('.')
          env.GIT_SHORT   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.VERSION     = "${major}.${minor}.${env.BUILD_NUMBER}"          // e.g. 1.0.17
          env.IMAGE_TAG   = "${env.VERSION}-${env.GIT_SHORT}"                // e.g. 1.0.17-a1b2c3d
          env.RELEASE_TAG = "v${env.VERSION}"                                // e.g. v1.0.17
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.RELEASE_TAG}"
          currentBuild.description = "commit ${env.GIT_SHORT}"
        }
        sh 'mkdir -p reports/security artifacts'
      }
    }

    // -------------------------------------------------------------------------
    stage('Build') {
      steps {
        sh '''
          node --version && npm --version
          npm ci --no-fund --no-audit
          npm run build                       # tsc -> dist/

          docker build \
            --build-arg APP_VERSION=${VERSION} \
            --build-arg GIT_COMMIT=${GIT_SHORT} \
            -t ${APP_NAME}:${IMAGE_TAG} \
            -t ${APP_NAME}:latest-build .

          # Store the artefact: the image as a tarball + build metadata
          docker save ${APP_NAME}:${IMAGE_TAG} | gzip > artifacts/${APP_NAME}-${IMAGE_TAG}.tar.gz
          cat > artifacts/build-info.json <<EOF
{ "app": "${APP_NAME}", "version": "${VERSION}", "image": "${APP_NAME}:${IMAGE_TAG}",
  "commit": "${GIT_SHORT}", "build": "${BUILD_NUMBER}", "builtAt": "$(date -u +%FT%TZ)" }
EOF
          docker image ls ${APP_NAME}
        '''
        archiveArtifacts artifacts: 'artifacts/*', fingerprint: true
      }
    }

    // -------------------------------------------------------------------------
    stage('Test') {
      environment { JWT_SECRET = 'ci-test-secret' }
      steps {
        // Unit + integration projects (Jest + Supertest + in-memory MongoDB).
        // Any failing test, or coverage below the thresholds in
        // jest.ci.config.js, returns non-zero and stops the pipeline.
        sh 'npm run test:ci'
      }
      post {
        always {
          junit testResults: 'reports/junit/junit.xml', allowEmptyResults: false
          recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'reports/coverage/cobertura-coverage.xml']],
                         sourceCodeRetention: 'EVERY_BUILD')
          publishHTML(target: [reportName: 'Coverage Report', reportDir: 'reports/coverage/lcov-report',
                               reportFiles: 'index.html', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true])
        }
      }
    }

    // -------------------------------------------------------------------------
    stage('Code Quality') {
      steps {
        withSonarQubeEnv('SonarQube') {
          // sonar.qualitygate.wait makes the scanner block until SonarQube has
          // evaluated the "EVAT Gate" quality gate and fail if it is red.
          sh '''
            sonar-scanner \
              -Dsonar.projectVersion=${VERSION} \
              -Dsonar.qualitygate.wait=true \
              -Dsonar.qualitygate.timeout=300
          '''
        }
      }
    }

    // -------------------------------------------------------------------------
    stage('Security') {
      parallel {
        stage('Dependencies (npm audit)') {
          steps {
            sh '''
              npm audit --omit=dev --json > reports/security/npm-audit.json || true
              npm audit --omit=dev || true
              # Gate: no HIGH or CRITICAL vulnerabilities in production deps
              npm audit --omit=dev --audit-level=high
            '''
          }
        }
        stage('Container image (Trivy)') {
          steps {
            sh '''
              trivy image --quiet --scanners vuln --format table \
                --output reports/security/trivy-image.txt ${APP_NAME}:${IMAGE_TAG}
              trivy image --quiet --scanners vuln --format json \
                --output reports/security/trivy-image.json ${APP_NAME}:${IMAGE_TAG}
              cat reports/security/trivy-image.txt
              # Gate: fail on CRITICAL vulnerabilities that have a fix available.
              # Accepted risks are listed with justification in .trivyignore
              trivy image --quiet --scanners vuln --severity CRITICAL --ignore-unfixed \
                --ignorefile .trivyignore --exit-code 1 ${APP_NAME}:${IMAGE_TAG}
            '''
          }
        }
        stage('Secrets & config (Trivy fs)') {
          steps {
            sh '''
              trivy fs --quiet --cache-dir /tmp/trivy-fs-cache --scanners secret,misconfig \
                --skip-dirs node_modules,dist,reports,artifacts,.scannerwork \
                --format table --output reports/security/trivy-fs.txt .
              cat reports/security/trivy-fs.txt
              # Gate: no leaked secrets in the repository
              trivy fs --quiet --cache-dir /tmp/trivy-fs-cache --scanners secret --exit-code 1 \
                --skip-dirs node_modules,dist,reports,artifacts,.scannerwork .
            '''
          }
        }
      }
      post {
        always { archiveArtifacts artifacts: 'reports/security/*', allowEmptyArchive: true }
      }
    }

    // -------------------------------------------------------------------------
    stage('Deploy: Staging') {
      steps {
        withCredentials([string(credentialsId: 'evat-jwt-staging', variable: 'JWT_SECRET')]) {
          sh '''
            export IMAGE_TAG
            docker compose -p evat-staging --env-file deploy/staging.env \
              -f deploy/docker-compose.yml up -d --remove-orphans --wait --wait-timeout 120
            docker compose -p evat-staging --env-file deploy/staging.env -f deploy/docker-compose.yml ps
          '''
        }
        // Smoke tests run inside the staging network (works from any host OS)
        sh 'docker run --rm -i --network ${STAGING_NET} ${CURL_IMAGE} sh -s -- http://api:8080 < deploy/smoke-test.sh'
      }
      post {
        failure { sh 'docker logs --tail 100 evat-staging-api || true' }
      }
    }

    // -------------------------------------------------------------------------
    stage('Release: Production') {
      steps {
        script {
          // Remember what is running now so we can roll back automatically
          env.PREVIOUS_IMAGE = sh(script: "docker inspect evat-prod-api --format '{{.Config.Image}}' 2>/dev/null || echo none",
                                  returnStdout: true).trim()
          echo "Currently in production: ${env.PREVIOUS_IMAGE}"
          sh 'docker tag ${APP_NAME}:${IMAGE_TAG} ${APP_NAME}:${RELEASE_TAG}'
          sh 'docker tag ${APP_NAME}:${IMAGE_TAG} ${APP_NAME}:production'

          withCredentials([string(credentialsId: 'evat-jwt-prod', variable: 'JWT_SECRET')]) {
            try {
              sh '''
                IMAGE_TAG=${RELEASE_TAG} docker compose -p evat-prod --env-file deploy/production.env \
                  -f deploy/docker-compose.yml up -d --remove-orphans --wait --wait-timeout 120
              '''
              sh 'docker run --rm -i --network ${PROD_NET} ${CURL_IMAGE} sh -s -- http://api:8080 < deploy/smoke-test.sh'
            } catch (err) {
              if (env.PREVIOUS_IMAGE != 'none') {
                echo "Production release failed - rolling back to ${env.PREVIOUS_IMAGE}"
                def prevTag = env.PREVIOUS_IMAGE.tokenize(':').last()
                sh """
                  IMAGE_TAG=${prevTag} docker compose -p evat-prod --env-file deploy/production.env \
                    -f deploy/docker-compose.yml up -d --wait --wait-timeout 120
                """
              }
              error("Release ${env.RELEASE_TAG} failed and was rolled back: ${err}")
            }
          }

          // Release notes: commits since the previous release tag
          sh '''
            PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
            {
              echo "# EVAT API ${RELEASE_TAG}"
              echo "Image: ${APP_NAME}:${RELEASE_TAG}  (commit ${GIT_SHORT}, build ${BUILD_NUMBER})"
              echo "Released: $(date -u +%FT%TZ)"
              echo; echo "## Changes"
              if [ -n "$PREV_TAG" ]; then git log --oneline ${PREV_TAG}..HEAD; else git log --oneline -15; fi
            } > artifacts/RELEASE_NOTES.md
            cat artifacts/RELEASE_NOTES.md
            git tag -a ${RELEASE_TAG} -m "Release ${RELEASE_TAG} (build ${BUILD_NUMBER})" || true
          '''
          archiveArtifacts artifacts: 'artifacts/RELEASE_NOTES.md'

          // Optional: push the git tag to GitHub
          try {
            withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
              sh '''
                ORIGIN=$(git config --get remote.origin.url | sed -e 's#^https://##' -e 's#^.*@##')
                git push "https://${GH_USER}:${GH_TOKEN}@${ORIGIN}" ${RELEASE_TAG}
              '''
            }
          } catch (ignored) { echo 'github-creds not configured - release tag kept locally only' }

          // Optional: push the release image to Docker Hub
          try {
            withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
              sh '''
                echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
                docker tag ${APP_NAME}:${RELEASE_TAG} $DH_USER/${APP_NAME}:${RELEASE_TAG}
                docker tag ${APP_NAME}:${RELEASE_TAG} $DH_USER/${APP_NAME}:latest
                docker push $DH_USER/${APP_NAME}:${RELEASE_TAG}
                docker push $DH_USER/${APP_NAME}:latest
                docker logout
              '''
            }
          } catch (ignored) { echo 'dockerhub-creds not configured - image kept in the local registry only' }
        }
      }
    }

    // -------------------------------------------------------------------------
    stage('Monitoring & Alerting') {
      steps {
        sh '''
          docker compose -f deploy/monitoring/docker-compose.yml up -d --build --remove-orphans
          # Pick up any rule/config changes without restarting
          docker run --rm --network ${MONITOR_NET} ${CURL_IMAGE} -s -X POST http://prometheus:9090/-/reload || true
        '''
        sh 'docker run --rm -i --network ${MONITOR_NET} ${CURL_IMAGE} sh -s < deploy/monitoring/verify.sh'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/**/*.txt,reports/**/*.json', allowEmptyArchive: true
    }
    success {
      echo """
      ============================================================
       ${env.RELEASE_TAG} is live
         Staging     http://localhost:8081/api/docs
         Production  http://localhost:8082/api/docs
         Prometheus  http://localhost:9090/alerts
         Alertmgr    http://localhost:9093
         Grafana     http://localhost:3000  (dashboard: EVAT API - Production)
      ============================================================
      """
    }
    failure {
      echo "Pipeline failed in stage: check the stage log above. Production was not changed or was rolled back."
    }
    cleanup {
      // Keep the Jenkins host tidy: drop the image tarball and dangling layers
      sh 'rm -f artifacts/*.tar.gz; docker image prune -f >/dev/null 2>&1 || true'
    }
  }
}

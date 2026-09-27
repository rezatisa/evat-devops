# Jenkins controller with everything the EVAT pipeline needs:
# Docker CLI + compose, Node.js 20, SonarScanner CLI, Trivy.
FROM jenkins/jenkins:lts-jdk21

USER root
ARG SONAR_SCANNER_VERSION=7.2.0.5079
ARG TRIVY_VERSION=0.74.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg unzip git lsb-release \
 # Docker CLI + compose plugin (talks to the host daemon via the mounted socket)
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list \
 # Node.js 20
 && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin nodejs \
 && rm -rf /var/lib/apt/lists/*

# Trivy (security scanning) - official install script, pinned version
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin v${TRIVY_VERSION}

# SonarScanner CLI (uses the JDK already in this image)
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/x64/;s/arm64/aarch64/') \
 && curl -fsSL -o /tmp/ss.zip \
      https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-${ARCH}.zip \
 && unzip -q /tmp/ss.zip -d /opt && rm /tmp/ss.zip \
 && ln -s /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-${ARCH}/bin/sonar-scanner /usr/local/bin/sonar-scanner

# Identity for release tags, and trust the mounted workspace
RUN git config --system user.name "Jenkins CI" \
 && git config --system user.email "jenkins@evat.local" \
 && git config --system --add safe.directory '*'

# Plugins + configuration-as-code (no setup wizard)
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /var/jenkins_casc/casc.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_casc/casc.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
# Runs as root only so it can use the host Docker socket (local lab setup).

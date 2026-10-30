#!/usr/bin/env bash
#
# Template: probe a cloud agent platform's provisioning box. Copy to the
# project's script/clouddev/prepare, set the three compose/initialize paths
# below, and replace it with the real prepare once the answers are in. See
# claude-code-cloud.md (Probe method) for how to read its output.
#
# Run from the checkout, which is not the working directory on Claude Code
# cloud: `cd /home/user/<repo> && script/clouddev/prepare --no-build`.
#
# A setup script's output is shown only when it fails, so the whole report is
# also written to $REPORT, which a session can read. The script exits 1 only
# when the dev image build fails; a clean build exits 0, which lets the
# platform snapshot the box. A stamp file and the Docker image store record
# what survives into the next session.
#
# `--no-build` skips the dev image build and exits 0 once the backing services
# are up, so the platform snapshots a box that never touched the Dockerfile.

readonly SERVICES_COMPOSE=.devcontainer/sidecar/compose.services.yml
readonly APP_COMPOSE=.devcontainer/sidecar/docker-compose.yml
readonly INITIALIZE=.devcontainer/sidecar/initialize
readonly APP_BUILD_TIMEOUT_SECONDS=900
readonly STAMP_DIR=/var/lib/clouddev-probe
readonly STAMP=$STAMP_DIR/runs
readonly REPORT=/var/lib/clouddev-probe/report.txt
readonly BUILD_LOG=/var/lib/clouddev-probe/build.log
readonly DOCKERD_LOG=/tmp/dockerd.log
readonly DOCKERD_WAIT_SECONDS=30
readonly HOST_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
readonly CONTAINER_CA_BUNDLE=/host-ca.pem
readonly TLS_PROBE_IMAGE=curlimages/curl
readonly TLS_PROBE_URL=https://rubygems.org/

section() {
  echo
  echo "== $1"
}

http_status() {
  curl -sS -m 10 -o /dev/null -w '%{http_code}' "$1" 2>&1
}

docker_ready() {
  docker info >/dev/null 2>&1
}

start_dockerd() {
  docker_ready && return 0
  command -v dockerd >/dev/null 2>&1 || { echo "no dockerd binary"; return 1; }
  dockerd >"$DOCKERD_LOG" 2>&1 &
  local waited=0
  until docker_ready; do
    ((waited++ >= DOCKERD_WAIT_SECONDS)) && break
    sleep 1
  done
  docker_ready
}

timed() {
  local started=$SECONDS
  "$@" 2>&1 | tail -15
  echo "-- ${PIPESTATUS[0]} after $((SECONDS - started))s: $*"
}

record_previous_runs() {
  section "previous runs (disk state carried into this box)"
  mkdir -p "$STAMP_DIR"
  if [[ -f $STAMP ]]; then
    cat "$STAMP"
  else
    echo "none: this box starts from a clean disk"
  fi
  echo "run at $(date -u +%FT%TZ) on $(hostname)" >>"$STAMP"
  echo "docker storage already on disk:"
  du -sh /var/lib/docker 2>&1
}

report_checkout_and_box() {
  section "checkout"
  pwd
  git branch --show-current 2>&1
  git log --oneline -1 2>&1
  section "toolchain"
  ruby -v 2>&1
  node -v 2>&1
  echo "direnv: $(command -v direnv || echo missing)"
  section "resources"
  df -h / | tail -1
  echo "cpus: $(nproc)"
  free -h | head -2
  section "secrets"
  echo "MY_TEST_SECRET visible: $(env | grep -c '^MY_TEST_SECRET=')"
}

report_tls_interception() {
  section "tls interception"
  echo "issuer seen from this box:"
  openssl s_client -connect rubygems.org:443 -servername rubygems.org \
    </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>&1
  echo "ca bundle: $HOST_CA_BUNDLE ($(grep -c 'BEGIN CERT' "$HOST_CA_BUNDLE") certs)"
  find /usr/local/share/ca-certificates -maxdepth 1 -type f 2>&1 | head -8
  echo "cert and proxy variables:"
  env | grep -iE 'cert|ssl|proxy|ca_bundle|ca_file' | sed 's/=.*/=<set>/' | sort
}

report_network() {
  section "network"
local host
for host in ghcr.io registry-1.docker.io rubygems.org registry.yarnpkg.com \
  registry.npmjs.org github.com raw.githubusercontent.com \
  deb.debian.org security.debian.org apt.postgresql.org www.postgresql.org \
  packages.stripe.dev dl.google.com dl-ssl.google.com astral.sh sentry.io \
  s3.amazonaws.com cdn.playwright.dev playwright.download.prss.microsoft.com; do
    printf '%-24s %s\n' "$host" "$(http_status "https://$host/")"
  done
}

start_docker_and_services() {
  section "dockerd"
  if start_dockerd; then
    docker info 2>&1 | grep -E 'Server Version|Storage Driver|Images'
    docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>&1 | head -12
  else
    echo "dockerd did not come up"
    tail -25 "$DOCKERD_LOG" 2>&1
    return 1
  fi
  section "initialize and backing services"
  timed "$INITIALIZE"
  timed docker compose -f "$SERVICES_COMPOSE" up -d --wait --wait-timeout 120
  docker compose -f "$SERVICES_COMPOSE" ps --format '{{.Service}} {{.Status}}' 2>&1
}

container_tls() {
  section "tls from inside a container"
  docker pull -q "$TLS_PROBE_IMAGE" >/dev/null 2>&1
  echo "without host CA bundle:"
  docker run --rm "$TLS_PROBE_IMAGE" -sS -m 15 -o /dev/null -w '%{http_code}\n' \
    "$TLS_PROBE_URL" 2>&1 | tail -2
  echo "with host CA bundle mounted:"
  docker run --rm -v "$HOST_CA_BUNDLE:$CONTAINER_CA_BUNDLE:ro" \
    -e "CURL_CA_BUNDLE=$CONTAINER_CA_BUNDLE" \
    "$TLS_PROBE_IMAGE" -sS -m 15 -o /dev/null -w '%{http_code}\n' \
    "$TLS_PROBE_URL" 2>&1 | tail -2
}

build_dev_image() {
  section "dev image build"
  local started=$SECONDS status
  timeout "$APP_BUILD_TIMEOUT_SECONDS" \
    docker compose -f "$SERVICES_COMPOSE" -f "$APP_COMPOSE" \
    build --progress=plain app >"$BUILD_LOG" 2>&1
  status=$?
  echo "build exit $status after $((SECONDS - started))s; full log: $BUILD_LOG"
  if ((status != 0)); then
    echo "-- error lines"
    grep -n -E '^(#[0-9]+ [0-9.]+ )?(E:|Err:|W: Failed)|curl: \(|gpg:|exit code' \
      "$BUILD_LOG" | head -25
    echo "-- tail"
    tail -25 "$BUILD_LOG"
  fi
  docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>&1 | head -12
  df -h / | tail -1
  return "$status"
}

main() {
  record_previous_runs
  report_checkout_and_box
  report_tls_interception
  report_network
  start_docker_and_services || return 1
  container_tls
  if [[ ${1:-} == --no-build ]]; then
    section "dev image build skipped (--no-build)"
    return 0
  fi
  build_dev_image
}

mkdir -p "$STAMP_DIR"
main "$@" 2>&1 | tee "$REPORT"
exit "${PIPESTATUS[0]}"

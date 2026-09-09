#!/usr/bin/env bash
# Start PostgreSQL + WildFly, deploy Digi Bank, run tests, print real results.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${BASE_URL:-http://localhost:8080/digibank-app}"
API="${BASE_URL}/api"
WILDFLY_HOME="${WILDFLY_HOME:-$HOME/wildfly-33.0.2.Final}"
WILDFLY_VERSION="33.0.2.Final"
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-digibank_db}"
PG_USER="${PG_USER:-digibank_user}"
PG_PASSWORD="${PG_PASSWORD:-digibank_pwd}"
PG_JDBC="jdbc:postgresql://${PG_HOST}:${PG_PORT}/${PG_DB}"
DOCKER_DB_NAME="${DOCKER_DB_NAME:-digibank-lab2-db}"
WILDFLY_LOG="${WILDFLY_LOG:-/tmp/digibank-wildfly.log}"
WILDFLY_PID_FILE="${WILDFLY_PID_FILE:-/tmp/digibank-wildfly.pid}"
STARTED_WILDFLY=0
FAILED=0

pass() { printf '  PASS  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$((FAILED + 1)); }
info() { printf '  ..    %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

section() {
  printf '\n======== %s ========\n' "$*"
}

cli() {
  "$WILDFLY_HOME/bin/jboss-cli.sh" --connect --timeout=15000 "$@"
}

wait_http() {
  local url="$1"
  local retries="${2:-60}"
  local i code
  for i in $(seq 1 "$retries"); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$url" 2>/dev/null || true)"
    if [[ "$code" =~ ^(200|201|302|401|403)$ ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

pretty_body() {
  python3 - <<'PY' 2>/dev/null || cat /tmp/digibank-test-body
import json, pathlib, sys
raw = pathlib.Path("/tmp/digibank-test-body").read_text(errors="replace")
text = raw.strip()
if not text:
    print("(empty body)")
    sys.exit(0)
try:
    print(json.dumps(json.loads(text), indent=2, ensure_ascii=False))
except Exception:
    lines = text.splitlines()
    for line in lines[:25]:
        print(line)
    if len(lines) > 25:
        print("... (%d more lines)" % (len(lines) - 25))
PY
}

http() {
  local method="$1"
  local url="$2"
  local expected="$3"
  shift 3
  local code
  code="$(curl -sS -o /tmp/digibank-test-body -w '%{http_code}' -X "$method" "$@" "$url" 2>/dev/null || true)"
  code="${code:-000}"
  printf '\n--- %s %s\n' "$method" "$url"
  printf 'HTTP %s (expected %s)\n' "$code" "$expected"
  pretty_body
  if [[ "$code" == "$expected" ]]; then
    pass "$method $url"
  else
    fail "$method $url (got HTTP $code)"
  fi
}

ensure_postgres() {
  section "PostgreSQL"
  if PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c 'SELECT 1' >/dev/null 2>&1; then
    info "Already reachable at ${PG_JDBC}"
    PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c '\conninfo'
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    die "PostgreSQL is not reachable and docker is not installed. Start Postgres or install Docker."
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "$DOCKER_DB_NAME"; then
    info "Starting existing container ${DOCKER_DB_NAME}"
    docker start "$DOCKER_DB_NAME" >/dev/null
  else
    info "Creating Postgres container ${DOCKER_DB_NAME} on port ${PG_PORT}"
    docker run -d --name "$DOCKER_DB_NAME" \
      -e POSTGRES_DB="$PG_DB" \
      -e POSTGRES_USER="$PG_USER" \
      -e POSTGRES_PASSWORD="$PG_PASSWORD" \
      -p "${PG_PORT}:5432" \
      postgres:16 >/dev/null
  fi

  local i
  for i in $(seq 1 40); do
    if PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c 'SELECT 1' >/dev/null 2>&1; then
      info "Database ${PG_DB} is ready"
      PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c '\conninfo'
      return 0
    fi
    sleep 1
  done
  die "PostgreSQL did not become ready on ${PG_HOST}:${PG_PORT}"
}

ensure_jdbc_module() {
  local dir="$WILDFLY_HOME/modules/system/layers/base/org/postgresql/main"
  local jar="$dir/postgresql-42.7.4.jar"
  mkdir -p "$dir"
  if [[ ! -f "$jar" ]]; then
    info "Downloading PostgreSQL JDBC driver"
    wget -q -O "$jar" https://jdbc.postgresql.org/download/postgresql-42.7.4.jar \
      || die "Could not download postgresql-42.7.4.jar"
  fi
  cat > "$dir/module.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<module xmlns="urn:jboss:module:1.9" name="org.postgresql">
    <resources>
        <resource-root path="postgresql-42.7.4.jar"/>
    </resources>
    <dependencies>
        <module name="javax.api"/>
        <module name="javax.transaction.api"/>
    </dependencies>
</module>
EOF
}

ensure_wildfly_home() {
  section "WildFly"
  if [[ ! -x "$WILDFLY_HOME/bin/standalone.sh" ]]; then
    info "WildFly not found at $WILDFLY_HOME — downloading ${WILDFLY_VERSION}"
    local archive="/tmp/wildfly-${WILDFLY_VERSION}.tar.gz"
    wget -q -O "$archive" \
      "https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz" \
      || die "Could not download WildFly ${WILDFLY_VERSION}"
    tar -xzf "$archive" -C "$(dirname "$WILDFLY_HOME")"
  fi
  ensure_jdbc_module
  if ! grep -q '^admin=' "$WILDFLY_HOME/standalone/configuration/mgmt-users.properties" 2>/dev/null; then
    info "Creating management user admin/admin"
    "$WILDFLY_HOME/bin/add-user.sh" -u admin -p admin >/dev/null 2>&1 || true
  fi
  info "WILDFLY_HOME=$WILDFLY_HOME"
}

ensure_wildfly_running() {
  if wait_http "http://127.0.0.1:9990/" 2; then
    info "WildFly management already listening on :9990"
    return 0
  fi
  info "Starting WildFly (log: ${WILDFLY_LOG})"
  : > "$WILDFLY_LOG"
  nohup "$WILDFLY_HOME/bin/standalone.sh" >"$WILDFLY_LOG" 2>&1 &
  echo $! > "$WILDFLY_PID_FILE"
  STARTED_WILDFLY=1
  if ! wait_http "http://127.0.0.1:9990/" 90; then
    tail -n 40 "$WILDFLY_LOG" || true
    die "WildFly did not start (management port 9990)"
  fi
  info "WildFly started"
}

ensure_datasource() {
  if cli --command='ls /subsystem=datasources/jdbc-driver' 2>/dev/null | grep -q postgresql; then
    info "PostgreSQL JDBC driver already registered"
  else
    info "Registering PostgreSQL JDBC driver"
    cli --command='/subsystem=datasources/jdbc-driver=postgresql:add(driver-name=postgresql,driver-module-name=org.postgresql,driver-class-name=org.postgresql.Driver)' \
      || die "Failed to add JDBC driver"
  fi

  if cli --command='ls /subsystem=datasources/data-source' 2>/dev/null | grep -q DigiBankDS; then
    info "Datasource DigiBankDS already bound"
  else
    info "Creating datasource java:/jdbc/DigiBankDS"
    cli --command="/subsystem=datasources/data-source=DigiBankDS:add(jndi-name=java:/jdbc/DigiBankDS,driver-name=postgresql,connection-url=${PG_JDBC},user-name=${PG_USER},password=${PG_PASSWORD},min-pool-size=5,max-pool-size=20,enabled=true)" \
      || die "Failed to add DigiBankDS"
  fi

  if cli --command='/subsystem=undertow/server=default-server/https-listener=https:read-resource' >/dev/null 2>&1; then
    local server_log="$WILDFLY_HOME/standalone/log/server.log"
    if grep -q 'Address already in use /127.0.0.1:8443' "$server_log" 2>/dev/null; then
      info "Port 8443 is busy — removing WildFly HTTPS listener"
      cli --command='/subsystem=undertow/server=default-server/https-listener=https:remove()' >/dev/null 2>&1 || true
      cli --command=':reload' >/dev/null 2>&1 || true
      wait_http "http://127.0.0.1:9990/" 40 || die "WildFly did not come back after reload"
    fi
  fi
}

run_maven_tests() {
  section "Maven / JUnit / Cucumber results"
  local log="/tmp/digibank-mvn-test.log"
  set -o pipefail
  if ! (cd "$ROOT" && mvn test | tee "$log"); then
    set +o pipefail
    fail "mvn test"
    return 1
  fi
  set +o pipefail
  pass "mvn test"
  echo
  info "Surefire summary"
  grep -E 'Tests run:|BUILD |Running |Scenario |Compliance' "$log" | tail -n 40 || true
  echo
  local report_dir="$ROOT/digibank-compliance/target/surefire-reports"
  if [[ -d "$report_dir" ]]; then
    info "JUnit XML reports"
    grep -h 'testcase name\|tests=' "$report_dir"/*.xml 2>/dev/null | head -n 40 || true
  fi
}

deploy_app() {
  section "Build and deploy"
  (cd "$ROOT" && mvn -pl digibank-app -am package -DskipTests) || die "Maven package failed"
  if cli --command='/deployment=digibank-app.war:read-resource' >/dev/null 2>&1; then
    info "Redeploying digibank-app.war"
    (cd "$ROOT" && mvn -pl digibank-app wildfly:redeploy) || die "wildfly:redeploy failed"
  else
    info "Deploying digibank-app.war"
    (cd "$ROOT" && mvn -pl digibank-app wildfly:deploy) || die "wildfly:deploy failed"
  fi
  wait_http "${BASE_URL}/" 40 || die "App did not answer at ${BASE_URL}/"
  info "Deployed at ${BASE_URL}/"
}

run_live_tests() {
  section "Live API results"
  local email account customer_id

  http GET "${BASE_URL}/" 200
  http GET "${API}/index" 200

  echo
  info "Compliance rule: amount <= 10000 is accepted"
  http GET "${API}/compliance/validate/5000" 200
  http GET "${API}/compliance/validate/20000" 200

  email="test.$(date +%s)@digibank.test"
  echo
  info "Creating customer ${email}"
  http POST "${API}/customers" 201 -H 'Content-Type: application/json' \
    -d "{\"firstName\":\"Ada\",\"lastName\":\"Lovelace\",\"email\":\"${email}\"}"
  customer_id="$(python3 -c 'import json,pathlib; print(json.loads(pathlib.Path("/tmp/digibank-test-body").read_text()).get("id",""))' 2>/dev/null || true)"

  http GET "${API}/customers" 200
  if [[ -n "${customer_id}" ]]; then
    http GET "${API}/customers/${customer_id}" 200
  else
    fail "customer id missing from POST response"
  fi

  account="ACC-$(date +%s)"
  echo
  info "Creating account ${account}"
  http POST "${API}/accounts" 201 -H 'Content-Type: application/json' \
    -d "{\"accountNumber\":\"${account}\",\"balance\":1500.0}"
  http GET "${API}/accounts" 200

  echo
  info "Creating DEPOSIT transaction of 250.0"
  http POST "${API}/transactions" 201 -H 'Content-Type: application/json' \
    -d '{"type":"DEPOSIT","amount":250.0}'
  http GET "${API}/transactions" 200
}

print_summary() {
  section "Summary"
  echo "App:        ${BASE_URL}/"
  echo "API:        ${API}/index"
  echo "Postgres:   ${PG_JDBC}"
  echo "WildFly:    $WILDFLY_HOME"
  if [[ "$STARTED_WILDFLY" -eq 1 ]]; then
    echo "WildFly was started by this script (pid $(cat "$WILDFLY_PID_FILE" 2>/dev/null || echo unknown))."
    echo "Stop it with: $WILDFLY_HOME/bin/jboss-cli.sh --connect command=:shutdown"
  fi
  echo
  if [[ "$FAILED" -eq 0 ]]; then
    echo "All tests passed."
    exit 0
  fi
  echo "${FAILED} test(s) failed."
  exit 1
}

printf 'Digi Bank — start, deploy, and test\n'
ensure_postgres
ensure_wildfly_home
ensure_wildfly_running
ensure_datasource
run_maven_tests
deploy_app
run_live_tests
print_summary

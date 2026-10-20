#!/usr/bin/env bash
# Qeet ID Kit — implementation of every macOS/Linux command.
#
# Sourced by the thin macos/ and linux/ command scripts; core/scripts/QeetIdKit.ps1
# implements the same flow for Windows, and CI diffs the docker commands both
# issue (validate.yml, parity test). Keep the two in step.
#
# Environments: DEV, TEST, STAGING — separate Compose projects (core/compose.yaml)
# behind one shared edge (core/edge.compose.yaml) that alone owns 127.0.0.1:80. They
# can run at the same time. Ordering, health, migrations and isolation live in
# the Compose files; this file selects releases, guards the data, manages the
# edge and explains what happened.
#
# bash 3.2 compatible (the macOS default): no associative arrays, no mapfile,
# no ${var,,}, and no `set -u` (empty arrays).

set -o pipefail

# The kit root (this file is core/scripts/common.sh).
KIT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KIT_VERSION=$(tr -d '[:space:]' < "$KIT_DIR/VERSION")
REGISTRY=${QEET_KIT_REGISTRY:-ghcr.io/qeetgroup}
STATE_ROOT=${QEET_KIT_STATE_DIR:-$HOME/.qeet-id-test-kit}
WAIT_SECONDS=${QEET_KIT_WAIT_SECONDS:-300}
DEBUG=${QEET_KIT_DEBUG:-0}

# Every environment the shared edge routes. The environments in THIS kit are
# those with a file in environments/ (an environment exists when
# environments/<env>.env exists), so TEST, STAGING and DEV can arrive one at a time.
KNOWN_ENVIRONMENTS="dev test staging"
ENVIRONMENTS=""
for _e in $KNOWN_ENVIRONMENTS; do
  [ -f "$KIT_DIR/environments/$_e.env" ] && ENVIRONMENTS="${ENVIRONMENTS:+$ENVIRONMENTS }$_e"
done
unset _e
SERVICES="postgres mailpit server login console website docs"
COMPONENTS="server login console website docs"

# ----------------------------------------------------------------- output ---

if [ -t 1 ]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BOLD='' C_DIM='' C_OFF=''
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8* | *utf8* | *UTF8*) M_OK='✓' M_WARN='⚠' M_FAIL='✗' ;;
  *) M_OK='[OK]' M_WARN='[WARN]' M_FAIL='[FAIL]' ;;
esac

say() { printf '%s\n' "$*"; }
title() { printf '\n%s%s%s\n\n' "$C_BOLD" "$*" "$C_OFF"; }
ok() { printf '%s%s%s %s\n' "$C_GREEN" "$M_OK" "$C_OFF" "$*"; }
warn() { printf '%s%s%s %s\n' "$C_YELLOW" "$M_WARN" "$C_OFF" "$*" >&2; }
fail() { printf '%s%s%s %s\n' "$C_RED" "$M_FAIL" "$C_OFF" "$*" >&2; }
hint() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }
die() {
  fail "$1"
  shift
  local line
  for line in "$@"; do hint "$line"; done
  exit 1
}
debug() { [ "$DEBUG" = 1 ] && printf '%s+ %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; return 0; }

# Runs a command, keeping its output out of the way unless it fails (or the
# engineer asked for --verbose). Output is kept in $LAST_LOG for diagnosis.
LAST_LOG=""
quiet() {
  debug "$*"
  LAST_LOG=$(mktemp "${TMPDIR:-/tmp}/qeet-kit.XXXXXX")
  if [ "$DEBUG" = 1 ]; then
    "$@" 2>&1 | tee "$LAST_LOG" >&2
  else
    "$@" > "$LAST_LOG" 2>&1
  fi
}
show_last_log() {
  [ -n "$LAST_LOG" ] && [ -s "$LAST_LOG" ] || return 0
  tail -n "${1:-15}" "$LAST_LOG" | sed 's/^/    /' >&2
}

# ---------------------------------------------------------------- options ---

OPT_YES=0 OPT_NO_BROWSER=0 OPT_RESET=0 OPT_FOLLOW=0 OPT_BUILD=0 OPT_TAIL=200
OPT_CANDIDATE="" OPT_MANIFEST="" OPT_ENV="" OPT_IMAGES=""
ARGS=()
parse_options() {
  ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -y | --yes) OPT_YES=1 ;;
      --no-browser) OPT_NO_BROWSER=1 ;;
      --reset) OPT_RESET=1 ;;
      --build) OPT_BUILD=1 ;;
      -f | --follow) OPT_FOLLOW=1 ;;
      -n | --tail) OPT_TAIL=${2:?--tail needs a number}; shift ;;
      --candidate) OPT_CANDIDATE=${2:?--candidate needs a version, e.g. 0.1.19-rc.2}; shift ;;
      --manifest) OPT_MANIFEST=${2:?--manifest needs a file}; shift ;;
      --image) OPT_IMAGES="$OPT_IMAGES ${2:?--image needs component=reference}"; shift ;;
      --env) OPT_ENV=${2:?--env needs dev, test or staging}; shift ;;
      -v | --verbose) DEBUG=1 ;;
      -h | --help) usage; exit 0 ;;
      -*) die "Unknown option: $1" "Run with --help to see the options." ;;
      *) ARGS+=("$1") ;;
    esac
    shift
  done
}

usage() {
  local e
  printf 'Qeet ID Kit %s — local environments: %s\n\nRun from the qeet-id-kit folder:\n' "$KIT_VERSION" "$(env_list)"
  for e in $ENVIRONMENTS; do
    printf '  %-34s start, update, stop, reset, rollback, status, logs\n' "$(kit_cmd "$e" '<command>')"
  done
  printf '  %-34s login, doctor, cleanup, stop-all, update-kit\n' "$(kit_cmd tools '<command>')"
  cat <<EOF

Options: --yes --no-browser --verbose --candidate <version> --manifest <file>
  logs:      [server|login|console|website|docs|db|mail|edge] --follow --tail N
  DEV start: --build, --image server|login|console|website|docs=<image>
EOF
}

# ---------------------------------------------------------- small helpers ---

# Reads KEY from a KEY=VALUE file without executing it (never `source` a file
# that came from the registry). Strips one level of surrounding double quotes.
kv() {
  local v
  v=$(sed -n "s/^$2=//p" "$1" 2> /dev/null | head -n 1)
  v=${v%\"}
  printf '%s' "${v#\"}"
}

# ver_ge A B: A >= B for x.y.z versions (pre-release suffixes ignored).
ver_ge() {
  local a b i x y
  IFS=. read -r -a a <<< "${1%%-*}"
  IFS=. read -r -a b <<< "${2%%-*}"
  for i in 0 1 2; do
    x=${a[$i]:-0} y=${b[$i]:-0}
    x=${x//[!0-9]/} y=${y//[!0-9]/}
    [ "${x:-0}" -gt "${y:-0}" ] && return 0
    [ "${x:-0}" -lt "${y:-0}" ] && return 1
  done
  return 0
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
label_of() { upper "$1"; }

# The command a tester types, e.g. "bash macos/test/reset.sh". <group> is an
# environment or "tools". macOS and Linux run the same scripts from their own folder.
kit_cmd() {
  local os=linux
  [ "$(uname -s 2> /dev/null)" = Darwin ] && os=macos
  printf 'bash %s/%s/%s.sh' "$os" "$1" "$2"
}

# "test" / "dev, test, staging" — the environments in this kit.
env_list() { printf '%s' "$ENVIRONMENTS" | sed 's/ /, /g'; }

# The single source of every browser-facing name: http://<svc>.<env>.id.qeet.localhost,
# except the website, which is the environment's bare zone (as id.qeet.in is).
kit_host() {
  if [ "$2" = website ]; then
    printf 'http://%s.id.qeet.localhost' "$1"
  else
    printf 'http://%s.%s.id.qeet.localhost' "$2" "$1"
  fi
}

service_name() {
  case "$1" in
    postgres) printf 'PostgreSQL' ;;
    mailpit) printf 'Mail inbox' ;;
    server) printf 'Qeet ID Server' ;;
    login) printf 'Login' ;;
    console) printf 'Console' ;;
    website) printf 'Website' ;;
    docs) printf 'Docs' ;;
    *) printf '%s' "$1" ;;
  esac
}

check_env() {
  [ -n "$1" ] || die "Choose an environment: $(env_list)."
  case " $ENVIRONMENTS " in
    *" $1 "*) ;;
    *) die "Unknown environment '$1'. This kit has: $(env_list)." ;;
  esac
}
check_release_env() {
  check_env "$1"
  [ "$1" != dev ] || die "DEV does not follow release candidates." "Use $(kit_cmd dev start) --build (or --image ...) to choose DEV's images."
}

open_url() {
  [ "$OPT_NO_BROWSER" = 1 ] && return 0
  [ "$(kv "$KIT_DIR/environments/optional.env" QEET_KIT_OPEN_BROWSER)" = false ] && return 0
  if command -v open > /dev/null 2>&1; then
    open "$1" > /dev/null 2>&1 || true
  elif command -v xdg-open > /dev/null 2>&1; then
    xdg-open "$1" > /dev/null 2>&1 || true
  fi
}

confirm_typed() { # expected-word prompt
  [ "$OPT_YES" = 1 ] && return 0
  local reply
  printf '%s ' "$2"
  read -r reply || return 1
  [ "$reply" = "$1" ]
}

# ------------------------------------------------------------------ state ---

state_dir() { printf '%s/%s' "$STATE_ROOT" "$1"; }
volume_exists() { docker volume inspect "qeet-id-$1-postgres" > /dev/null 2>&1; }
project_running() { [ -n "$(docker ps -q --filter "label=com.docker.compose.project=qeet-id-$1")" ]; }
any_env_running() {
  local e
  for e in $ENVIRONMENTS; do project_running "$e" && return 0; done
  return 1
}
secrets_present() {
  local d
  d="$(state_dir "$1")/secrets"
  [ -s "$d/postgres.env" ] && [ -s "$d/server.env" ] && [ -s "$d/console.env" ] && [ -s "$d/relay.env" ]
}

# The kit image (keygen + update payload). A released kit pins it in kit.lock;
# a development checkout builds it locally.
KIT_IMAGE=""
kit_image() {
  if [ -z "$KIT_IMAGE" ]; then
    KIT_IMAGE=$(kv "$KIT_DIR/kit.lock" QEET_KIT_IMAGE)
    [ -n "$KIT_IMAGE" ] || KIT_IMAGE="qeet-id-test-kit:dev"
  fi
  printf '%s' "$KIT_IMAGE"
}
ensure_kit_image() {
  if [ "$(kit_image)" = "qeet-id-test-kit:dev" ]; then
    quiet docker build -q -t qeet-id-test-kit:dev -f "$KIT_DIR/core/image/Dockerfile" "$KIT_DIR" ||
      { show_last_log; die "Could not build the test-kit tools image."; }
  fi
}

# compose ENV RELEASE_FILE ARGS... — every environment Compose call goes through here.
compose() {
  local env=$1 rel=$2
  shift 2
  debug "docker compose -p qeet-id-$env $*"
  QEET_KIT_ENV=$env QEET_KIT_STATE_DIR=$STATE_ROOT QEET_KIT_IMAGE=$(kit_image) \
    QEET_KIT_UID=$(id -u) QEET_KIT_GID=$(id -g) \
    docker compose --project-name "qeet-id-$env" --project-directory "$KIT_DIR" \
    --file "$KIT_DIR/core/compose.yaml" --env-file "$KIT_DIR/environments/$env.env" --env-file "$rel" "$@"
}
edge_compose() {
  debug "docker compose -p qeet-id-edge $*"
  docker compose --project-name qeet-id-edge --project-directory "$KIT_DIR" --file "$KIT_DIR/core/edge.compose.yaml" "$@"
}

# ------------------------------------------------------------------- edge ---

edge_running() { [ -n "$(docker ps -q --filter label=com.docker.compose.project=qeet-id-edge)" ]; }
port80_busy() { (exec 3<> /dev/tcp/127.0.0.1/80) 2> /dev/null; }

ensure_edge() {
  local e
  for e in $KNOWN_ENVIRONMENTS; do
    docker network inspect "qeet-id-$e-edge" > /dev/null 2>&1 ||
      quiet docker network create --label in.qeet.test-kit=edge "qeet-id-$e-edge" ||
      { show_last_log; die "Could not create the Docker network qeet-id-$e-edge."; }
  done
  if ! edge_running && port80_busy; then
    die "Port 80 is already in use by another program." \
      "The test kit serves http://*.id.qeet.localhost on port 80. Stop the other program and try again." \
      "macOS: sudo lsof -nP -iTCP:80 -sTCP:LISTEN   shows which one. Run Doctor for more."
  fi
  # Idempotent: a running edge is left alone unless its configuration changed.
  quiet edge_compose up -d --wait --wait-timeout 60 || {
    show_last_log
    # Doctor cannot see a registry rate limit on the edge's image; say so here.
    classify_registry_error "$(cat "$LAST_LOG")"
    [ $? != 15 ] || registry_failure_message 15
    die "The local edge (port 80) did not start." "Run Doctor: $(kit_cmd tools doctor)"
  }
}

stop_edge_if_idle() {
  any_env_running && return 0
  edge_running || return 0
  quiet edge_compose down && ok "Stopped the local edge (no environment is running)"
}

# ---------------------------------------------------------------- release ---

# QEET_ID_<COMPONENT>_IMAGE for every component.
image_keys() {
  local c
  for c in $COMPONENTS; do printf 'QEET_ID_%s_IMAGE ' "$(upper "$c")"; done
}

RELEASE_LINE_RE='^QEET_ID_[A-Z0-9_]+=[A-Za-z0-9@:/._+,-]*$'
PINNED_IMAGE_RE='^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+(:[A-Za-z0-9._-]+)?@sha256:[0-9a-f]{64}$'

# valid_release FILE [allow-unpinned]
valid_release() {
  local f=$1 line k v
  [ -s "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    [[ $line =~ $RELEASE_LINE_RE ]] || { debug "bad release line: $line"; return 1; }
  done < "$f"
  [ "$(kv "$f" QEET_ID_MANIFEST_SCHEMA)" = 1 ] || return 1
  for k in QEET_ID_VERSION QEET_ID_DATA_EPOCH QEET_ID_MIN_KIT_VERSION QEET_ID_SERVER_SCHEMA_VERSION \
    $(image_keys); do
    [ -n "$(kv "$f" "$k")" ] || { debug "release is missing $k"; return 1; }
  done
  [ "${2:-}" = allow-unpinned ] && return 0
  for k in $(image_keys); do
    v=$(kv "$f" "$k")
    [[ $v =~ $PINNED_IMAGE_RE ]] || { debug "$k is not digest-pinned: $v"; return 1; }
  done
}

# Classifies a failed registry call: 10 = authentication, 11 = not found,
# 12 = other, 14 = Docker's credential helper is broken, 15 = rate limited.
classify_registry_error() {
  if grep -qiE 'error getting credentials|docker-credential-[a-z-]+' <<< "$1"; then
    return 14
  elif grep -qiE 'toomanyrequests|too many requests|rate exceeded|rate limit' <<< "$1"; then
    return 15
  elif grep -qiE 'unauthorized|denied|authentication required|no basic auth|forbidden|403' <<< "$1"; then
    return 10
  elif grep -qiE 'not found|manifest unknown|does not exist|404' <<< "$1"; then
    return 11
  fi
  return 12
}

# fetch_release REF OUT — pulls a release manifest image and writes its fields.
fetch_release() {
  local ref=$1 out=$2 log
  debug "docker pull $ref"
  if ! log=$(docker pull -q "$ref" 2>&1); then
    debug "$log"
    classify_registry_error "$log"
    return $?
  fi
  docker image inspect --format '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' "$ref" 2> /dev/null |
    sed -n 's/^qeet\.release\.//p' | sort > "$out.tmp"
  if valid_release "$out.tmp"; then
    mv "$out.tmp" "$out"
  else
    rm -f "$out.tmp"
    return 13
  fi
}

# The package name of an image reference: ghcr.io/qeetgroup/qeet-id-server:sha-1@sha256:… -> qeet-id-server
image_name() {
  local n=${1%%@*}
  n=${n%:*}
  printf '%s' "${n##*/}"
}

access_problem() { # code what
  case "$1" in
    10) fail "This GitHub sign-in cannot read $2." ;;
    11) fail "$2 was not found in the registry." ;;
    13) fail "The release record $2 is unreadable or needs a newer Qeet ID Kit." ;;
    14) fail "Docker's sign-in helper is not working (while checking $2)." ;;
    15) fail "The registry is limiting downloads right now (while checking $2) — try again in a minute." ;;
    *) fail "Could not check $2: the registry did not answer." ;;
  esac
}

# check_access — can this computer's sign-in read everything Start downloads?
# For every environment in this kit: its release channel and each image the
# candidate names; plus the kit image when kit.lock pins one. Metadata only
# (docker manifest inspect); nothing is downloaded. Prints a line per result and
# returns the number of problems.
check_access() {
  local env channel tmp rc k ref out n good problems=0
  tmp=$(mktemp "${TMPDIR:-/tmp}/qeet-kit.XXXXXX")
  for env in $ENVIRONMENTS; do
    channel=$(kv "$KIT_DIR/environments/$env.env" QEET_KIT_CHANNEL)
    [ -n "$channel" ] || continue
    fetch_release "$REGISTRY/qeet-id-release:$channel" "$tmp"
    rc=$?
    case $rc in
      0) ;;
      11) warn "No $(label_of "$env") candidate has been published yet (channel '$channel')"; continue ;;
      *) access_problem "$rc" "qeet-id-release:$channel"; problems=$((problems + 1)); continue ;;
    esac
    n=0 good=0
    for k in $(image_keys); do
      ref=$(kv "$tmp" "$k")
      n=$((n + 1))
      if out=$(docker manifest inspect "$ref" 2>&1); then
        good=$((good + 1))
      else
        debug "$out"
        classify_registry_error "$out"
        access_problem $? "$(image_name "$ref")"
        problems=$((problems + 1))
      fi
    done
    [ $good != $n ] || ok "Can download $(label_of "$env") $(kv "$tmp" QEET_ID_VERSION) (all $n images)"
  done
  if [ -f "$KIT_DIR/kit.lock" ]; then
    if out=$(docker manifest inspect "$(kit_image)" 2>&1); then
      ok "Can download the kit image"
    else
      debug "$out"
      classify_registry_error "$out"
      access_problem $? "$(image_name "$(kit_image)")"
      problems=$((problems + 1))
    fi
  fi
  rm -f "$tmp" "$tmp.tmp"
  return $problems
}

registry_failure_message() { # code channel-or-ref
  case "$1" in
    10) die "Unable to download Qeet ID: this computer's GitHub sign-in cannot read the Qeet ID packages." \
      "Run Login again: $(kit_cmd tools login)" \
      "Use a CLASSIC token (github.com/settings/tokens > Tokens (classic)) with read:packages — fine-grained tokens do not work with GitHub Packages." \
      "Sign in with your own GitHub account, and make sure it has been given access to the qeetgroup packages (ask your team lead)." ;;
    14) die "Docker's sign-in helper is not working, so Docker cannot use your GitHub sign-in." \
      "Restart Docker Desktop and try again. If it keeps happening, reinstall Docker Desktop." ;;
    15) die "The image registry is limiting downloads right now (too many requests)." \
      "Wait a minute, then run the same command again." ;;
    11)
      [ "$2" != staging ] || die "No Qeet ID candidate has been promoted to STAGING yet." \
        "A candidate reaches STAGING only after QA approves it in TEST. Ask the release manager."
      die "No Qeet ID release candidate is published as '$2' yet." \
        "Ask the release manager to publish one, or check the name passed to --candidate." ;;
    13) die "The release manifest for '$2' is invalid or needs a newer Qeet ID Kit." \
      "Run Update Kit: $(kit_cmd tools update-kit)   then try again." ;;
    *) die "Cannot reach the image registry ($REGISTRY)." \
      "Check your internet connection or proxy, then try again. Run Doctor for details: $(kit_cmd tools doctor)" ;;
  esac
}

# Schema version recorded by the server's migrations in THIS environment's
# database (the source of truth; the state cache is informational). Prints
# "<version> <dirty>" or nothing for a database the server has never migrated.
db_schema() {
  local env=$1 rel=$2 out
  quiet compose "$env" "$rel" up -d --wait --wait-timeout 120 postgres || return 1
  # No schema_migrations table (a first start that failed before migrating) = fresh.
  out=$(compose "$env" "$rel" exec -T postgres psql -U qeet_id -d "qeet_id_$env" -tA \
    -c 'SELECT version || chr(32) || dirty FROM schema_migrations' 2> /dev/null) || out=""
  printf '%s\n' "$out" | head -n 1
}

# ------------------------------------------------------------- DEV images ---

dev_source() { # component -> source directory or empty
  local c=$1 v up
  v=$(kv "$KIT_DIR/environments/optional.env" "QEET_KIT_DEV_$(upper "$c")_SRC")
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return
  fi
  up=$(cd "$KIT_DIR/.." 2> /dev/null && pwd)
  [ -n "$up" ] && [ -f "$up/qeet-id-$c/Dockerfile" ] && printf '%s' "$up/qeet-id-$c"
}

image_label() { # image label-key
  docker image inspect --format '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' "$1" 2> /dev/null |
    sed -n "s/^$2=//p" | head -n 1
}

# dev_release OUT — the DEV release record: --image picks, --build results,
# otherwise the previous DEV selection.
dev_release() {
  local out=$1 cur c ref src rev schema pick item uc
  cur="$(state_dir dev)/current.env"
  [ "$OPT_BUILD" = 1 ] || [ -n "$OPT_IMAGES" ] || [ -f "$cur" ] ||
    die "DEV has no images yet." \
      "Build them from your working trees:   $(kit_cmd dev start) --build" \
      "or choose images:   $(kit_cmd dev start) --image <component>=<ref> for each of: $COMPONENTS"
  {
    printf 'QEET_ID_MANIFEST_SCHEMA=1\nQEET_ID_VERSION=dev\nQEET_ID_RELEASE=dev\nQEET_ID_DATA_EPOCH=0\n'
    printf 'QEET_ID_MIN_KIT_VERSION=%s\nQEET_ID_CREATED_AT=%s\n' "$KIT_VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$out.tmp"
  for c in $COMPONENTS; do
    uc=$(upper "$c")
    pick=""
    for item in $OPT_IMAGES; do
      case "$item" in "$c="*) pick=${item#*=} ;; esac
    done
    rev="" schema=""
    if [ -n "$pick" ]; then
      ref=$pick
      docker image inspect "$ref" > /dev/null 2>&1 || quiet docker pull -q "$ref" ||
        { show_last_log; die "DEV: cannot use image $ref for $c."; }
      rev=$(image_label "$ref" 'org\.opencontainers\.image\.revision')
      [ "$c" = server ] && schema=$(image_label "$ref" 'in\.qeet\.id\.schema-version')
    elif [ "$OPT_BUILD" = 1 ]; then
      src=$(dev_source "$c")
      [ -n "$src" ] || die "DEV: cannot find the qeet-id-$c source." \
        "Set QEET_KIT_DEV_${uc}_SRC in environments/optional.env to its folder."
      rev=$(git -C "$src" rev-parse HEAD 2> /dev/null || printf unknown)
      [ -z "$(git -C "$src" status --porcelain 2> /dev/null)" ] || rev="$rev-dirty"
      ref="qeet-id-$c:dev"
      say "Building $c from $src ..."
      if [ "$c" = server ]; then
        quiet docker build -t "$ref" --build-arg VERSION=dev --build-arg COMMIT="$rev" \
          --build-arg DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$src" ||
          { show_last_log 25; die "DEV: building $c failed."; }
        schema=$(find "$src/internal/platform/database/migrations" -name '*.up.sql' 2> /dev/null |
          sed -E 's#.*/0*([0-9]+)_[^/]*$#\1#' | sort -n | tail -n 1)
      else
        quiet docker build -t "$ref" --build-arg VERSION=dev --build-arg REVISION="$rev" "$src" ||
          { show_last_log 25; die "DEV: building $c failed."; }
      fi
      ok "Built $ref"
    else
      ref=$(kv "$cur" "QEET_ID_${uc}_IMAGE")
      rev=$(kv "$cur" "QEET_ID_${uc}_REVISION")
      [ "$c" = server ] && schema=$(kv "$cur" QEET_ID_SERVER_SCHEMA_VERSION)
    fi
    printf 'QEET_ID_%s_IMAGE=%s\nQEET_ID_%s_REVISION=%s\n' "$uc" "$ref" "$uc" "${rev:-unknown}" >> "$out.tmp"
    if [ "$c" = server ]; then printf 'QEET_ID_SERVER_SCHEMA_VERSION=%s\n' "${schema:-0}" >> "$out.tmp"; fi
  done
  sort "$out.tmp" > "$out" && rm -f "$out.tmp"
  valid_release "$out" allow-unpinned || die "DEV: an image reference is not usable." "Run with --verbose for details."
}

# ----------------------------------------------------------------- guards ---

# Settings from an older kit (settings/.env) are no longer read.
check_local_env() {
  [ ! -f "$KIT_DIR/settings/.env" ] ||
    warn "settings/.env is no longer read. Copy its values into environments/optional.env, then delete the settings folder."
}

preflight() {
  command -v docker > /dev/null 2>&1 ||
    die "Docker is not installed." "Install Docker Desktop (https://www.docker.com/products/docker-desktop/), start it, and try again."
  docker info > /dev/null 2>&1 ||
    die "Docker Desktop is installed but is not running." "Start Docker Desktop and try again."
  [ "$(docker info --format '{{.OSType}}' 2> /dev/null)" = linux ] ||
    die "Docker is running Windows containers." "Switch Docker Desktop to Linux containers and try again."
  local v
  v=$(docker compose version --short 2> /dev/null)
  v=${v#v}
  [ -n "$v" ] || die "Docker Compose is not available." "Update Docker Desktop to a current version."
  ver_ge "$v" 2.24.0 || die "Docker Compose $v is too old (2.24 or newer is required)." "Update Docker Desktop."
}

# ----------------------------------------------------------------- start ---

# stop_project ENV — stops one environment's containers, keeping its data.
stop_project() {
  local env=$1 cur ids
  cur="$(state_dir "$env")/current.env"
  if [ -f "$cur" ]; then
    quiet compose "$env" "$cur" down --remove-orphans && return 0
  fi
  # No release recorded (or Compose could not load it): remove by project label.
  ids=$(docker ps -aq --filter "label=com.docker.compose.project=qeet-id-$env")
  # shellcheck disable=SC2086 # one container id per word
  [ -z "$ids" ] || quiet docker rm -f $ids
}

diagnose_start_failure() {
  local env=$1 rel=$2 svc id st logs reason=""
  logs=$(compose "$env" "$rel" logs --no-color --no-log-prefix --tail 200 server 2> /dev/null)
  if grep -q 'migrations failed' <<< "$logs"; then
    reason=migration
  elif grep -q 'refusing to start' <<< "$logs"; then
    reason=config
  fi
  for svc in $SERVICES; do
    id=$(compose "$env" "$rel" ps -aq "$svc" 2> /dev/null | head -n 1)
    [ -n "$id" ] || { fail "$(service_name "$svc") did not start."; continue; }
    st=$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2> /dev/null)
    case "$st" in
      running\|healthy | running\|) ok "$(service_name "$svc") healthy" ;;
      *) fail "$(service_name "$svc") failed its health check (${st%|*})." ;;
    esac
  done
  case "$reason" in
    migration)
      say ""
      fail "Database migrations for this release failed, so $(label_of "$env") is not ready."
      hint "Run Logs ($(kit_cmd "$env" logs) server) for the error and send it to the Qeet ID team."
      hint "If the database is older than this release allows, Reset ($(kit_cmd "$env" reset)) starts fresh."
      ;;
    config)
      say ""
      fail "Qeet ID Server refused its configuration:"
      # The newest "refusing to start" line and the "  - reason" lines after it.
      awk '/refusing to start/ {b = $0; r = 1; next} r && /^  - / {b = b "\n" $0; next} {r = 0} END {print b}' <<< "$logs" |
        sed 's/^/    /' >&2
      ;;
  esac
  # Do not leave a crash loop behind.
  quiet compose "$env" "$rel" stop server
  say ""
  hint "Run Logs ($(kit_cmd "$env" logs)) for diagnostics."
  exit 1
}

check_routes() {
  local env=$1 svc path host bad=0
  for svc in api login console website docs mail; do
    case "$svc" in api) path=/readyz ;; mail) path=/livez ;; *) path=/healthz ;; esac
    host=$(kit_host "$env" "$svc")
    if ! edge_compose exec -T edge wget -Y off -q -O /dev/null --header "Host: ${host#http://}" \
      "http://127.0.0.1$path" > /dev/null 2>&1; then
      fail "$(kit_host "$env" "$svc") does not answer through the local edge."
      bad=1
    fi
  done
  [ $bad = 0 ] || die "$(label_of "$env") started but is not reachable." "Run Doctor ($(kit_cmd tools doctor)) and Logs ($(kit_cmd "$env" logs) edge)."
}

print_ready() {
  local env=$1 rel=$2
  say ""
  if [ "$env" = dev ]; then
    ok "${C_BOLD}Qeet ID is ready in DEV (status shows its images).${C_OFF}"
  else
    ok "${C_BOLD}Qeet ID $(kv "$rel" QEET_ID_VERSION) is ready in $(label_of "$env").${C_OFF}"
  fi
  say ""
  say "  Console        $(kit_host "$env" console)"
  say "  Hosted login   $(kit_host "$env" login)"
  say "  API            $(kit_host "$env" api)"
  say "  Mail inbox     $(kit_host "$env" mail)   (verification codes, magic links, invites)"
  say "  Website        $(kit_host "$env" website)"
  say "  Docs           $(kit_host "$env" docs)"
  say ""
  say "  Use Google Chrome or Microsoft Edge. Data is kept until you run Reset ($(kit_cmd "$env" reset))."
}

# start_release ENV RELEASE_FILE MODE — MODE: channel | local | rollback | installed | dev
start_release() {
  local env=$1 rel=$2 mode=$3 sd cur prev fresh=0 db schema dirty epoch cand_schema min
  sd=$(state_dir "$env")
  cur="$sd/current.env" prev="$sd/previous.env"

  min=$(kv "$rel" QEET_ID_MIN_KIT_VERSION)
  ver_ge "$KIT_VERSION" "$min" ||
    die "Qeet ID $(kv "$rel" QEET_ID_VERSION) needs Qeet ID Kit $min or newer (this is $KIT_VERSION)." \
      "Run Update Kit: $(kit_cmd tools update-kit)   Your environments and data are kept."

  if volume_exists "$env"; then
    secrets_present "$env" ||
      die "Existing $(label_of "$env") data was found, but its keys are missing from $sd/secrets." \
        "The data cannot be opened without them. Run Reset ($(kit_cmd "$env" reset)) to start fresh."
    epoch=$(kv "$sd/data.env" QEET_KIT_DATA_EPOCH)
    if [ "$env" != dev ] && [ -n "$epoch" ] && [ "$epoch" != "$(kv "$rel" QEET_ID_DATA_EPOCH)" ]; then
      die "Qeet ID $(kv "$rel" QEET_ID_VERSION) cannot use your existing $(label_of "$env") data (data format $epoch -> $(kv "$rel" QEET_ID_DATA_EPOCH))." \
        "Nothing was changed. Run Reset ($(kit_cmd "$env" reset)) to start fresh with this release."
    fi
    db=$(db_schema "$env" "$rel") || { show_last_log; die "PostgreSQL did not start for the compatibility check."; }
    if [ -n "$db" ]; then
      schema=${db% *} dirty=${db#* }
      case "$dirty" in t | true) die "The last database migration in $(label_of "$env") did not finish, so the data is in an unknown state." \
        "Run Reset ($(kit_cmd "$env" reset)) to start fresh." ;;
      esac
      cand_schema=$(kv "$rel" QEET_ID_SERVER_SCHEMA_VERSION)
      if [ "${cand_schema:-0}" -gt 0 ] 2> /dev/null && [ "$cand_schema" -lt "$schema" ] 2> /dev/null; then
        die "Qeet ID $(kv "$rel" QEET_ID_VERSION) is older than your $(label_of "$env") data (schema $schema, release supports $cand_schema)." \
          "Nothing was changed. Reset ($(kit_cmd "$env" reset)) starts fresh with this release."
      fi
    fi
  else
    fresh=1
  fi

  if ! secrets_present "$env"; then
    ensure_kit_image
    mkdir -p "$sd/secrets" && chmod 700 "$sd" "$sd/secrets"
    quiet compose "$env" "$rel" --profile tools run --rm keygen ||
      { show_last_log; die "Could not generate $(label_of "$env")'s local secrets."; }
    ok "Generated local test-only secrets"
  fi

  if [ "$mode" = channel ]; then
    if ! quiet compose "$env" "$rel" pull --quiet; then
      classify_registry_error "$(cat "$LAST_LOG")"
      registry_failure_message $? "$(kv "$rel" QEET_ID_VERSION)"
    fi
    ok "Images ready"
  fi

  ensure_edge
  say "Starting $(label_of "$env")$([ $fresh = 1 ] && printf ' (first start applies every database migration — about a minute)')..."
  if ! quiet compose "$env" "$rel" up -d --remove-orphans --wait --wait-timeout "$WAIT_SECONDS"; then
    say ""
    diagnose_start_failure "$env" "$rel"
  fi
  ok "Database ready, migrations completed"
  local svc
  for svc in server login console website docs mailpit; do ok "$(service_name "$svc") healthy"; done
  check_routes "$env"

  # Capture first: grep -q stops reading early, Compose then exits 255 on the
  # closed pipe, and pipefail would turn a match into a false warning.
  local logs
  logs=$(compose "$env" "$rel" logs --no-color --no-log-prefix server 2> /dev/null)
  if ! grep -q 'notifier: email via SMTP' <<< "$logs"; then
    warn "Email is not being delivered to the Mail inbox; verification codes will not arrive. Run Logs ($(kit_cmd "$env" logs) server)."
  fi

  if [ $fresh = 1 ]; then
    local seed
    seed=$(kv "$rel" QEET_ID_SEED_ARGS)
    if [ "$(kv "$KIT_DIR/environments/$env.env" QEET_KIT_SEED)" = true ] && [ -n "$seed" ]; then
      # shellcheck disable=SC2086 # QEET_ID_SEED_ARGS is a validated, comma-separated argument list
      quiet compose "$env" "$rel" run --rm --no-deps server ${seed//,/ } ||
        { show_last_log; die "The release's seed step failed."; }
      ok "Loaded the release's synthetic seed data"
    else
      ok "Fresh environment: empty baseline — create accounts through Sign up"
    fi
  fi

  # Record what is now installed.
  if [ "$env" != dev ] && [ -f "$cur" ] && [ "$(kv "$cur" QEET_ID_VERSION)" != "$(kv "$rel" QEET_ID_VERSION)" ]; then
    cp "$cur" "$prev"
  fi
  [ "$rel" = "$cur" ] || cp "$rel" "$cur"
  db=$(compose "$env" "$cur" exec -T postgres psql -U qeet_id -d "qeet_id_$env" -tA \
    -c "SELECT version FROM schema_migrations" 2> /dev/null | head -n 1)
  printf 'QEET_KIT_DATA_EPOCH=%s\nQEET_KIT_DB_SCHEMA=%s\n' "$(kv "$cur" QEET_ID_DATA_EPOCH)" "$db" > "$sd/data.env"
  case "$mode" in
    rollback) : > "$sd/pinned" ;;
    channel | local) rm -f "$sd/pinned" ;;
  esac
  print_ready "$env" "$cur"
  open_url "$(kit_host "$env" console)"
}

prepare_state() {
  local sd
  sd=$(state_dir "$1")
  mkdir -p "$sd" && chmod 700 "$STATE_ROOT" "$sd" 2> /dev/null
  printf '%s' "$sd"
}

cmd_start() {
  local env=$1 sd cur cand ref rc channel installed
  check_env "$env"
  preflight
  check_local_env
  title "Qeet ID $(label_of "$env")"
  sd=$(prepare_state "$env")
  cur="$sd/current.env" cand="$sd/candidate.env"
  installed=$(kv "$cur" QEET_ID_VERSION)

  if [ "$env" = dev ]; then
    dev_release "$cand"
    start_release dev "$cand" dev
    return
  fi
  if [ "$OPT_BUILD" = 1 ] || [ -n "$OPT_IMAGES" ]; then
    die "--build and --image are for DEV only. TEST and STAGING run published release candidates."
  fi
  if [ -n "$OPT_MANIFEST" ]; then
    [ -f "$OPT_MANIFEST" ] || die "Manifest file not found: $OPT_MANIFEST"
    sed '/^[[:space:]]*$/d; /^#/d' "$OPT_MANIFEST" > "$cand"
    valid_release "$cand" allow-unpinned || die "$OPT_MANIFEST is not a valid release manifest."
    warn "Using a local manifest ($OPT_MANIFEST) — engineering use only."
    say "Installed: ${installed:-none}"
    say "Selected:  $(kv "$cand" QEET_ID_VERSION)"
    start_release "$env" "$cand" local
    return
  fi
  if [ -f "$sd/pinned" ] && [ -z "$OPT_CANDIDATE" ] && [ -f "$cur" ]; then
    warn "$(label_of "$env") is pinned to $installed by Rollback. Run Update ($(kit_cmd "$env" update)) to return to the newest candidate."
    start_release "$env" "$cur" installed
    return
  fi

  channel=$(kv "$KIT_DIR/environments/$env.env" QEET_KIT_CHANNEL)
  ref="$REGISTRY/qeet-id-release:${OPT_CANDIDATE:-$channel}"
  fetch_release "$ref" "$cand"
  rc=$?
  if [ $rc != 0 ]; then
    if [ -f "$cur" ] && [ -z "$OPT_CANDIDATE" ] && [ $rc != 13 ]; then
      local why
      case $rc in
        10) why="registry authentication" ;;
        11) why="nothing is on the '$channel' channel yet" ;;
        14) why="Docker's sign-in helper is not working" ;;
        15) why="the registry is limiting downloads" ;;
        *) why="registry unreachable" ;;
      esac
      warn "Could not check for a newer release ($why). Starting the installed version."
      start_release "$env" "$cur" installed
      return
    fi
    registry_failure_message $rc "${OPT_CANDIDATE:-$channel}"
  fi
  say "Installed: ${installed:-none}"
  say "Available: $(kv "$cand" QEET_ID_VERSION)"
  if [ -n "$installed" ] && cmp -s "$cand" "$cur"; then
    say "Already on the newest $(label_of "$env") candidate."
  else
    say "Updating..."
  fi
  start_release "$env" "$cand" channel
}

cmd_update() {
  local only=${1:-} env any=0
  [ "$only" != dev ] || die "DEV is updated by rebuilding: $(kit_cmd dev start) --build"
  [ -z "$only" ] || check_release_env "$only"
  preflight
  OPT_NO_BROWSER=1
  for env in $ENVIRONMENTS; do
    [ "$env" != dev ] || continue
    [ -z "$only" ] || [ "$only" = "$env" ] || continue
    if [ -n "$only" ] || project_running "$env"; then
      rm -f "$(state_dir "$env")/pinned"
      (cmd_start "$env") || exit 1
      any=1
    fi
  done
  [ $any = 1 ] || die "No TEST or STAGING environment is running." "Start one first, e.g. $(kit_cmd test start)"
}

# ------------------------------------------------------------ other cmds ---

cmd_stop() {
  local target=${1:-} env any=0
  [ -n "$target" ] || die "Stop which environment? $(env_list) or all."
  [ "$target" = all ] || check_env "$target"
  preflight
  for env in $ENVIRONMENTS; do
    [ "$target" = all ] || [ "$target" = "$env" ] || continue
    if project_running "$env"; then
      stop_project "$env"
      ok "Stopped $(label_of "$env") (data kept)"
      any=1
    elif [ "$target" = "$env" ]; then
      say "$(label_of "$env") is not running."
    fi
  done
  if [ "$target" = all ]; then
    if edge_running; then quiet edge_compose down && ok "Stopped the local edge"; fi
    [ $any = 1 ] || say "No environment was running."
  else
    stop_edge_if_idle
  fi
}

cmd_reset() {
  local env=$1 sd
  check_env "$env"
  preflight
  sd=$(state_dir "$env")
  title "Reset Qeet ID $(label_of "$env")"
  say "This permanently deletes every $(label_of "$env") account, organization and email on this computer,"
  say "then starts $(label_of "$env") fresh. The other environments are not touched."
  say ""
  confirm_typed "$env" "Type $env to confirm:" || die "Reset cancelled. Nothing was changed."
  stop_project "$env"
  quiet docker volume rm "qeet-id-$env-postgres" "qeet-id-$env-mail"
  if volume_exists "$env"; then die "Could not delete the $(label_of "$env") database volume." "Restart Docker Desktop and try again."; fi
  rm -rf "$sd/secrets" "$sd/data.env" "$sd/pinned"
  ok "Deleted $(label_of "$env") data"
  hint "Also delete any passkeys saved for $env.id.qeet.localhost in your browser or password manager."
  [ "$OPT_RESET" = rollback ] && return 0
  cmd_start "$env"
}

cmd_rollback() {
  local env=$1 sd prev db schema tmp
  check_release_env "$env"
  preflight
  sd=$(state_dir "$env")
  prev="$sd/previous.env"
  [ -f "$prev" ] || die "No earlier $(label_of "$env") candidate is available on this computer."
  valid_release "$prev" allow-unpinned || die "The recorded previous release is unreadable."
  title "Roll back Qeet ID $(label_of "$env") to $(kv "$prev" QEET_ID_VERSION)"
  if volume_exists "$env" && [ "$OPT_RESET" != 1 ]; then
    db=$(db_schema "$env" "$prev")
    schema=${db% *}
    if [ -n "$db" ] && [ "$(kv "$prev" QEET_ID_SERVER_SCHEMA_VERSION)" -lt "$schema" ] 2> /dev/null; then
      die "$(kv "$prev" QEET_ID_VERSION) is older than your $(label_of "$env") data (schema $schema), so it cannot open it." \
        "To roll back anyway with fresh data: $(kit_cmd "$env" rollback) --reset   (deletes $(label_of "$env") data)."
    fi
  fi
  tmp="$sd/rollback.env"
  cp "$prev" "$tmp"
  if [ "$OPT_RESET" = 1 ]; then
    OPT_RESET=rollback
    cmd_reset "$env"
  fi
  start_release "$env" "$tmp" rollback
  rm -f "$tmp"
}

cmd_status() {
  local only=$1 env sd cur prev svc st health state c uc
  [ -z "$only" ] || check_env "$only"
  title "Qeet ID Local Environments — Qeet ID Kit $KIT_VERSION"
  if ! docker info > /dev/null 2>&1; then
    warn "Docker is not running; showing recorded versions only."
  fi
  if edge_running 2> /dev/null; then say "${C_BOLD}EDGE${C_OFF}     running   127.0.0.1:80"; else say "${C_BOLD}EDGE${C_OFF}     stopped"; fi
  say ""
  for env in $ENVIRONMENTS; do
    [ -z "$only" ] || [ "$only" = "$env" ] || continue
    sd=$(state_dir "$env")
    cur="$sd/current.env" prev="$sd/previous.env"
    if [ ! -f "$cur" ]; then
      say "${C_BOLD}$(label_of "$env")${C_OFF}  not installed   ($(kit_cmd "$env" start))"
      say ""
      continue
    fi
    state=stopped
    project_running "$env" 2> /dev/null && state=running
    [ -f "$sd/pinned" ] && state="$state, pinned by Rollback"
    say "${C_BOLD}$(label_of "$env")${C_OFF}  $state"
    if [ "$env" = dev ]; then
      say "  Build:          locally selected images (recorded $(kv "$cur" QEET_ID_CREATED_AT))"
    else
      say "  Release:        $(kv "$cur" QEET_ID_RELEASE)   Candidate: $(kv "$cur" QEET_ID_VERSION)   Published: $(kv "$cur" QEET_ID_CREATED_AT)"
    fi
    for c in $COMPONENTS; do
      uc=$(upper "$c")
      printf '  %-15s %s\n' "$(service_name "$c"):" "$(kv "$cur" "QEET_ID_${uc}_IMAGE")"
      printf '  %-15s revision %s%s\n' "" "$(kv "$cur" "QEET_ID_${uc}_REVISION")" \
        "$([ "$c" = server ] && printf ', schema %s' "$(kv "$cur" QEET_ID_SERVER_SCHEMA_VERSION)")"
    done
    [ -f "$prev" ] && say "  Previous:       $(kv "$prev" QEET_ID_VERSION) (available for Rollback)"
    if [ "${state#running}" != "$state" ]; then
      compose "$env" "$cur" ps -a --format '{{.Service}}|{{.State}}|{{.Health}}' 2> /dev/null | sort |
        while IFS='|' read -r svc st health; do
          [ "$svc" = keygen ] && continue
          printf '  %-15s %s\n' "$(service_name "$svc")" "${health:-$st}"
        done
      say "  URLs:           $(kit_host "$env" console)  $(kit_host "$env" login)"
      say "                  $(kit_host "$env" api)  $(kit_host "$env" mail)"
      say "                  $(kit_host "$env" website)  $(kit_host "$env" docs)"
    fi
    say ""
  done
}

cmd_logs() {
  local svc=${1:-} env=$OPT_ENV cur e running="" n=0
  case "$svc" in
    edge | proxy | router)
      local eargs=(logs --timestamps --tail "$OPT_TAIL")
      [ "$OPT_FOLLOW" = 1 ] && eargs+=(--follow)
      edge_compose "${eargs[@]}"
      return
      ;;
  esac
  if [ -z "$env" ]; then
    for e in $ENVIRONMENTS; do
      if project_running "$e"; then running="$running $e" env=$e n=$((n + 1)); fi
    done
    [ $n = 1 ] || die "Which environment? Add --env with one of: $(env_list)." "Running now:${running:- none}"
  fi
  check_env "$env"
  cur="$(state_dir "$env")/current.env"
  # A first start that failed has no current.env yet, only the candidate it tried.
  [ -f "$cur" ] || cur="$(state_dir "$env")/candidate.env"
  [ -f "$cur" ] || die "$(label_of "$env") is not installed."
  case "$svc" in
    "" | all) svc="" ;;
    server | api) svc=server ;;
    login | console | website | docs) ;;
    db | database | postgres) svc=postgres ;;
    mail | mailpit) svc=mailpit ;;
    *) die "Unknown service '$svc'." "Use one of: server, login, console, website, docs, db, mail, edge (or nothing for all)." ;;
  esac
  local args=(logs --timestamps --tail "$OPT_TAIL")
  [ "$OPT_FOLLOW" = 1 ] && args+=(--follow)
  [ -n "$svc" ] && args+=("$svc")
  compose "$env" "$cur" "${args[@]}"
}

cmd_cleanup() {
  preflight
  local keep="" env f k v n=0 repo digest ours="" c
  for c in $COMPONENTS; do ours="$ours $REGISTRY/qeet-id-$c"; done
  for env in $ENVIRONMENTS; do
    for f in current previous; do
      for k in $(image_keys); do
        v=$(kv "$(state_dir "$env")/$f.env" "$k")
        case "$v" in *@sha256:*) ;; *) continue ;; esac
        repo=${v%@*}    # registry[:port]/name:tag
        repo=${repo%:*} # registry[:port]/name
        keep="$keep $repo@${v##*@}"
      done
    done
  done
  while IFS='|' read -r repo digest; do
    case "$ours " in *" $repo "*) ;; *) continue ;; esac
    case "$digest" in sha256:*) ;; *) continue ;; esac
    case " $keep " in *" $repo@$digest "*) continue ;; esac
    # By reference, so only the candidate the kit pulled is removed.
    if quiet docker image rm "$repo@$digest"; then n=$((n + 1)); fi
  done < <(docker image ls -a --digests --format '{{.Repository}}|{{.Digest}}' | sort -u)
  ok "Removed $n old Qeet ID image(s); kept the current and previous candidate of each environment."
}

cmd_login() {
  local host=${REGISTRY%%/*} user
  preflight
  title "Sign in to GitHub Packages ($host)"
  say "Use your GitHub username and a CLASSIC personal access token with ONLY the"
  say "read:packages scope: github.com/settings/tokens > Tokens (classic)."
  say "Fine-grained tokens do not work with GitHub Packages."
  say "Docker asks for the token itself (hidden) and keeps it in its credential store, not in the kit."
  say ""
  printf 'GitHub username: '
  read -r user || exit 1
  [ -n "$user" ] || die "A username is required."
  docker login "$host" -u "$user" ||
    die "Sign-in to $host failed." "Check the username, and that you pasted a classic token with read:packages."
  # "Login Succeeded" only proves the token is valid; check it can read Qeet ID.
  say ""
  say "Checking that this sign-in can download Qeet ID..."
  if check_access; then
    ok "Signed in to $host and able to download Qeet ID. Next: $(kit_cmd test start)"
  else
    die "Signed in, but this sign-in cannot download everything Qeet ID needs (see above)." \
      "Use a CLASSIC token (Tokens (classic)) with read:packages — fine-grained tokens do not work." \
      "Sign in with your own GitHub account, and make sure it has been given access to the qeetgroup packages (ask your team lead)." \
      "Then run Login again: $(kit_cmd tools login)"
  fi
}

cmd_update_kit() {
  local want=${1:-} ref digest_ref version label dest cid
  preflight
  ref="$REGISTRY/qeet-id-test-kit:${want:-stable}"
  title "Update Kit (installed: $KIT_VERSION)"
  if ! quiet docker pull -q "$ref"; then
    classify_registry_error "$(cat "$LAST_LOG")"
    registry_failure_message $? "qeet-id-test-kit:${want:-stable}"
  fi
  digest_ref=$(docker image inspect --format '{{index .RepoDigests 0}}' "$ref" 2> /dev/null)
  [[ $digest_ref == *@sha256:* ]] || die "Could not resolve $ref to an immutable digest."
  label=$(image_label "$digest_ref" 'org\.opencontainers\.image\.version')
  if [ -n "$want" ] && [ "$want" != stable ] && [ "$label" != "$want" ]; then
    die "$ref claims version '$label', not $want. Not installing it."
  fi
  # Only a newer kit is an update, unless a version was asked for explicitly.
  if [ "$label" = "$KIT_VERSION" ] || { [ "${want:-stable}" = stable ] && ver_ge "$KIT_VERSION" "$label"; }; then
    ok "This Qeet ID Kit ($KIT_VERSION) is already the newest."
    return 0
  fi
  dest="$(dirname "$KIT_DIR")/qeet-id-kit-$label"
  [ -e "$dest" ] && die "$dest already exists." "Use that folder, or remove it and run Update Kit again."
  cid=$(docker create "$digest_ref" true) || die "Could not unpack the Qeet ID Kit image."
  mkdir -p "$dest"
  if ! quiet docker cp "$cid:/kit/." "$dest"; then
    docker rm "$cid" > /dev/null 2>&1
    rm -rf "$dest"
    die "Could not unpack the Qeet ID Kit image."
  fi
  docker rm "$cid" > /dev/null 2>&1
  version=$(tr -d '[:space:]' < "$dest/VERSION" 2> /dev/null)
  if [ "$version" != "$label" ]; then
    rm -rf "$dest"
    die "The downloaded kit reports version '$version' but is labelled '$label'. Not installing it."
  fi
  printf 'QEET_KIT_IMAGE=%s:%s@%s\n' "${digest_ref%@*}" "$label" "${digest_ref##*@}" > "$dest/kit.lock"
  # Carry the tester's settings over.
  [ ! -f "$KIT_DIR/environments/optional.env" ] ||
    { cp "$KIT_DIR/environments/optional.env" "$dest/environments/optional.env" && ok "Carried your environments/optional.env over"; }
  ok "Qeet ID Kit $label installed in $dest"
  say "  Close this window and use the new folder from now on. Your environments,"
  say "  data and registry sign-in are kept."
}

cmd_doctor() {
  local problems=0 v mem arch free
  title "Qeet ID Kit $KIT_VERSION — Doctor"
  if ! command -v docker > /dev/null 2>&1; then
    fail "Docker is not installed — install Docker Desktop."
    exit 1
  fi
  ok "Docker CLI $(docker version --format '{{.Client.Version}}' 2> /dev/null)"
  if ! docker info > /dev/null 2>&1; then
    fail "Docker Desktop is installed but is not running — start it."
    exit 1
  fi
  ok "Docker engine $(docker version --format '{{.Server.Version}}' 2> /dev/null) is running"
  v=$(docker compose version --short 2> /dev/null)
  v=${v#v}
  if [ -n "$v" ] && ver_ge "$v" 2.24.0; then ok "Docker Compose $v"; else fail "Docker Compose ${v:-missing} — 2.24 or newer is required"; problems=$((problems + 1)); fi
  if [ "$(docker info --format '{{.OSType}}' 2> /dev/null)" = linux ]; then ok "Linux containers"; else fail "Switch Docker Desktop to Linux containers"; problems=$((problems + 1)); fi
  mem=$(docker info --format '{{.MemTotal}}' 2> /dev/null)
  mem=$((${mem:-0} / 1024 / 1024))
  if [ "$mem" -ge 4096 ]; then
    ok "Docker memory $((mem / 1024)) GiB (enough for DEV, TEST and STAGING together)"
  elif [ "$mem" -ge 2048 ]; then
    warn "Docker memory $((mem / 1024)) GiB — enough for one or two environments; 4 GiB runs all three (Docker Desktop > Settings > Resources)"
  else
    fail "Docker has only ${mem} MiB of memory; at least 2 GiB is needed (Docker Desktop > Settings > Resources)"
    problems=$((problems + 1))
  fi
  free=$(df -Pk "$HOME" 2> /dev/null | awk 'NR==2 {print int($4/1024/1024)}')
  if [ "${free:-0}" -ge 10 ]; then ok "Free disk ${free} GiB"; else warn "Only ${free:-?} GiB free disk; 10 GiB or more is recommended"; fi
  arch=$(docker version --format '{{.Server.Arch}}' 2> /dev/null)
  ok "Architecture: computer $(uname -m), Docker $arch"
  if edge_running; then
    ok "Port 80 is served by the Qeet ID edge"
  elif port80_busy; then
    fail "Port 80 is in use by another program (sudo lsof -nP -iTCP:80 -sTCP:LISTEN)"
    problems=$((problems + 1))
  else
    ok "Port 80 is free"
  fi
  if (exec 3<> /dev/tcp/::1/80) 2> /dev/null && ! edge_running; then
    warn "Something listens on [::1]:80; browsers may reach it instead of the kit"
  fi
  if mkdir -p "$STATE_ROOT" 2> /dev/null && [ -w "$STATE_ROOT" ]; then ok "State folder $STATE_ROOT"; else fail "Cannot write $STATE_ROOT"; problems=$((problems + 1)); fi
  if [ -f "$KIT_DIR/kit.lock" ]; then ok "Kit image $(kit_image)"; else warn "No kit.lock — development checkout; the tools image is built locally"; fi
  check_local_env
  local rc tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/qeet-kit.XXXXXX")
  fetch_release "$REGISTRY/qeet-id-release:test" "$tmp"
  rc=$?
  case $rc in
    0)
      ok "Registry access ($REGISTRY); TEST channel: $(kv "$tmp" QEET_ID_VERSION)"
      check_access || problems=$((problems + $?))
      case ",$(kv "$tmp" QEET_ID_PLATFORMS)," in
        *",linux/$arch,"*) ok "Images available for linux/$arch" ;;
        *) warn "TEST images are not published for linux/$arch; Docker will emulate them (slower)" ;;
      esac
      ver_ge "$KIT_VERSION" "$(kv "$tmp" QEET_ID_MIN_KIT_VERSION)" || {
        fail "The TEST candidate needs Qeet ID Kit $(kv "$tmp" QEET_ID_MIN_KIT_VERSION) — run Update Kit: $(kit_cmd tools update-kit)"
        problems=$((problems + 1))
      }
      ;;
    10) fail "This GitHub sign-in cannot read the Qeet ID packages — run Login: $(kit_cmd tools login)"; problems=$((problems + 1)) ;;
    14) fail "Docker's sign-in helper is not working — restart Docker Desktop"; problems=$((problems + 1)) ;;
    15) fail "The registry is limiting downloads right now — run Doctor again in a minute"; problems=$((problems + 1)) ;;
    11) warn "Registry reachable; no TEST candidate has been published yet" ;;
    13) fail "The TEST release manifest is unreadable — run Update Kit: $(kit_cmd tools update-kit)"; problems=$((problems + 1)) ;;
    *) fail "Cannot reach $REGISTRY — check your internet connection or proxy"; problems=$((problems + 1)) ;;
  esac
  rm -f "$tmp" "$tmp.tmp"
  ok "Browsers: Chrome and Edge open *.id.qeet.localhost on this computer automatically"
  say ""
  if [ $problems = 0 ]; then ok "No problems found."; else fail "$problems problem(s) found."; exit 1; fi
}

# ------------------------------------------------------------------- main ---

kit_main() {
  local cmd=$1
  shift
  parse_options "$@"
  set -- ${ARGS[@]+"${ARGS[@]}"}
  case "$cmd" in
    start) cmd_start "${1:-}" ;;
    update) cmd_update "${1:-${OPT_ENV:-}}" ;;
    stop) cmd_stop "${1:-${OPT_ENV:-}}" ;;
    reset) cmd_reset "${1:-${OPT_ENV:-}}" ;;
    rollback) cmd_rollback "${1:-${OPT_ENV:-}}" ;;
    status) cmd_status "${1:-${OPT_ENV:-}}" ;;
    logs) cmd_logs "${1:-}" ;;
    cleanup) cmd_cleanup ;;
    doctor) cmd_doctor ;;
    login) cmd_login ;;
    update-kit) cmd_update_kit "${1:-}" ;;
    *) usage; exit 2 ;;
  esac
}

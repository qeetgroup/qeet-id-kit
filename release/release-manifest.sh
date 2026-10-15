#!/usr/bin/env bash
# Qeet ID product release candidates — assembled ONLY here, in qeet-id-kit.
#
#   release-manifest.sh assemble OUT_DIR    resolve + validate components, write manifest.json + release.env
#   release-manifest.sh to-env MANIFEST     print the release.env form of a manifest.json
#   release-manifest.sh publish OUT_DIR     push qeet-id-release:<version> (immutable) and move `test`
#   release-manifest.sh promote TARGET CANDIDATE
#                                           TARGET: test | staging | production-approved | final
#
# Channels: `test` (QA tests in TEST) -> `staging` (Product/UAT validates in
# STAGING) -> `production-approved` (approval only, never deployment state) ->
# final immutable BOM <x.y.z>, recorded after the existing production deploys.
#
# Application repositories publish immutable ghcr.io/qeetgroup/<repo>:sha-<commit>
# images (their ci.yml `image` job). This script never builds application code.
#
# Inputs (environment): REGISTRY (default ghcr.io/qeetgroup), RELEASE, SERVER,
# LOGIN, CONSOLE, WEBSITE, DOCS (a 40-hex commit, an image reference, or empty =
# carry forward from the `test` channel), RESET_REQUIRED (true|false), MIN_KIT_VERSION
# (x.y.z; empty = keep the `test` candidate's),
# CREATED_BY, WORKFLOW_RUN, NOTES, SOURCE_OWNER (default qeetgroup),
# REQUIRED_PLATFORMS (default linux/amd64,linux/arm64).
# Needs docker (buildx) and jq.
set -euo pipefail

REGISTRY=${REGISTRY:-ghcr.io/qeetgroup}
SOURCE_OWNER=${SOURCE_OWNER:-qeetgroup}
REQUIRED_PLATFORMS=${REQUIRED_PLATFORMS:-linux/amd64,linux/arm64}
RELEASE=${RELEASE:-}
RELEASE_REPO="$REGISTRY/qeet-id-release"
SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

err() { echo "::error::$*" >&2; exit 1; }
note() { echo "$*" >&2; }

# exists REF -> 0 present, 1 not found; any other registry failure aborts.
exists() {
  local out
  if out=$(docker buildx imagetools inspect "$1" 2>&1); then return 0; fi
  if grep -qiE 'not found|manifest unknown|404' <<< "$out"; then return 1; fi
  err "cannot query $1: $out"
}

index_digest() { docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r '.digest'; }

# Platforms of a multi-platform image, attestation entries excluded,
# arm64 variants normalised (linux/arm64/v8 -> linux/arm64).
platforms_of() {
  docker buildx imagetools inspect --raw "$1" | jq -r '
    if .manifests then
      [.manifests[] | select(.platform.os != "unknown")
        | "\(.platform.os)/\(.platform.architecture)"
          + (if .platform.variant and .platform.architecture != "arm64" then "/\(.platform.variant)" else "" end)]
    else [] end | unique | .[]'
}

labels_of() {
  docker buildx imagetools inspect "$1" --format '{{json .Image}}' | jq -c '
    if has("config") then .config.Labels
    else [to_entries[] | select(.key | startswith("unknown") | not)][0].value.config.Labels end // {}'
}

# manifest_of REF -> manifest.json content of a published candidate/channel.
manifest_of() {
  local ref=$1 dir cid
  dir=$(mktemp -d)
  docker pull -q "$ref" > /dev/null
  cid=$(docker create "$ref" noop)
  docker cp "$cid:/qeet-id-release/manifest.json" "$dir/manifest.json" > /dev/null
  docker rm "$cid" > /dev/null
  cat "$dir/manifest.json"
  rm -rf "$dir"
}

# ---------------------------------------------------------------- assemble ---

resolve_component() { # name input previous-manifest-json -> component JSON on stdout
  local name=$1 input=$2 previous=$3 ref repo digest labels plats revision branch rel source schema
  repo="qeet-id-$name"
  if [ -z "$input" ]; then
    [ -n "$previous" ] || err "$name: no commit given and no test candidate to carry it forward from"
    jq -e ".components.$name" <<< "$previous" > /dev/null ||
      err "$name: the test candidate has no $name image to carry forward — give a commit"
    [ "$(jq -r .release <<< "$previous")" = "$RELEASE" ] ||
      err "$name: the test candidate is for release $(jq -r .release <<< "$previous"), not $RELEASE — give a commit"
    note "$name: carried forward from $(jq -r .version <<< "$previous")"
    input="$(jq -r ".components.$name.image" <<< "$previous"):$(jq -r ".components.$name.tag" <<< "$previous")"
  fi
  if [[ $input =~ ^[0-9a-f]{40}$ ]]; then
    ref="$REGISTRY/$repo:sha-$input"
  else
    ref=$input
  fi
  exists "$ref" || err "$name: image $ref is not published (has the $repo release CI run for that commit?)"

  digest=$(index_digest "$ref")
  [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || err "$name: could not resolve $ref to a digest"
  labels=$(labels_of "$ref")
  plats=$(platforms_of "$ref" | jq -R . | jq -sc .)
  revision=$(jq -r '."org.opencontainers.image.revision" // ""' <<< "$labels")
  source=$(jq -r '."org.opencontainers.image.source" // ""' <<< "$labels")
  branch=$(jq -r '."in.qeet.source-branch" // ""' <<< "$labels")
  rel=$(jq -r '."in.qeet.release" // ""' <<< "$labels")

  # Provenance: refuse anything that is not this release's build of this repository.
  [ "$source" = "https://github.com/$SOURCE_OWNER/$repo" ] || err "$name: $ref was built from '$source', not $SOURCE_OWNER/$repo"
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || err "$name: $ref has no commit revision label"
  if [[ $input =~ ^[0-9a-f]{40}$ ]] && [ "$revision" != "$input" ]; then err "$name: $ref is labelled with revision $revision, not $input"; fi
  [ "$ref" = "${ref%:sha-*}:sha-$revision" ] || [[ ! $ref =~ :sha- ]] || err "$name: tag and revision label disagree for $ref"
  [ "$branch" = "release/$RELEASE" ] || err "$name: $ref was built from '$branch', not release/$RELEASE"
  [ "$rel" = "$RELEASE" ] || err "$name: $ref is labelled release '$rel', not $RELEASE"
  local p
  for p in ${REQUIRED_PLATFORMS//,/ }; do
    jq -e --arg p "$p" 'index($p) != null' <<< "$plats" > /dev/null || err "$name: $ref is not built for $p (has $plats)"
  done
  schema=null
  if [ "$name" = server ]; then
    schema=$(jq -r '."in.qeet.id.schema-version" // ""' <<< "$labels")
    [[ $schema =~ ^[1-9][0-9]*$ ]] || err "server: $ref has no in.qeet.id.schema-version label"
  fi

  jq -n --arg image "${ref%:*}" --arg tag "sha-$revision" --arg digest "$digest" \
    --arg repository "$SOURCE_OWNER/$repo" --arg revision "$revision" --arg branch "$branch" \
    --argjson platforms "$plats" --argjson schema "$schema" '
    {image: $image, tag: $tag, digest: $digest, repository: $repository, revision: $revision,
     sourceBranch: $branch, platforms: $platforms}
    + (if $schema == null then {} else {schemaVersion: $schema} end)'
}

channel_manifest() { # channel -> manifest JSON or empty
  if exists "$RELEASE_REPO:$1"; then manifest_of "$RELEASE_REPO:$1"; fi
}

cmd_assemble() {
  local out=${1:?OUT_DIR}
  [[ ${RELEASE:-} =~ $SEMVER ]] || err "RELEASE must be x.y.z (got '${RELEASE:-}')"
  local min=${MIN_KIT_VERSION:-}

  local current epoch=0 e ch
  current=$(channel_manifest test)
  # The minimum kit is inherited from the test candidate and raised only on
  # purpose (MIN_KIT_VERSION). A new kit release alone must not raise it: testers
  # on an older kit would be refused the candidate until they update.
  if [ -z "$min" ] && [ -n "$current" ]; then min=$(jq -r '.minTestKitVersion // ""' <<< "$current"); fi
  [ -n "$min" ] || min=$(tr -d '[:space:]' < "$(dirname "$0")/../VERSION")
  [[ $min =~ $SEMVER ]] || err "MIN_KIT_VERSION must be x.y.z (got '$min')"
  # dataEpoch is inherited from the newest candidate in any channel and only ever grows.
  for ch in test staging production-approved; do
    if [ "$ch" = test ]; then e=$current; else e=$(channel_manifest "$ch"); fi
    [ -n "$e" ] || continue
    e=$(jq -r .dataEpoch <<< "$e")
    [ "$e" -gt "$epoch" ] && epoch=$e
  done
  [ "$epoch" -ge 1 ] || epoch=1
  if [ "${RESET_REQUIRED:-false}" = true ]; then epoch=$((epoch + 1)); fi

  local n=1
  while exists "$RELEASE_REPO:$RELEASE-rc.$n"; do n=$((n + 1)); done
  local version="$RELEASE-rc.$n"

  local server login console website docs
  server=$(resolve_component server "${SERVER:-}" "$current")
  login=$(resolve_component login "${LOGIN:-}" "$current")
  console=$(resolve_component console "${CONSOLE:-}" "$current")
  website=$(resolve_component website "${WEBSITE:-}" "$current")
  docs=$(resolve_component docs "${DOCS:-}" "$current")

  mkdir -p "$out"
  jq -n --arg version "$version" --arg release "$RELEASE" --argjson candidate "$n" \
    --arg createdAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg createdBy "${CREATED_BY:-unknown}" \
    --arg workflowRun "${WORKFLOW_RUN:-local}" --argjson dataEpoch "$epoch" --arg min "$min" \
    --argjson server "$server" --argjson login "$login" --argjson console "$console" \
    --argjson website "$website" --argjson docs "$docs" \
    --arg notes "${NOTES:-}" '
    {schemaVersion: 1, product: "qeet-id", version: $version, release: $release, candidate: $candidate,
     createdAt: $createdAt, createdBy: $createdBy, workflowRun: $workflowRun,
     dataEpoch: $dataEpoch, minTestKitVersion: $min,
     components: {server: $server, login: $login, console: $console, website: $website, docs: $docs}}
    + (if $notes == "" then {} else {notes: $notes} end)' > "$out/manifest.json"
  cmd_to_env "$out/manifest.json" > "$out/release.env"
  note "assembled $version (dataEpoch $epoch, minimum kit $min)"
  echo "$version"
}

# ------------------------------------------------------------------ to-env ---

cmd_to_env() {
  jq -r '
    def img(c): "\(c.image):\(c.tag)@\(c.digest)";
    [ "QEET_ID_MANIFEST_SCHEMA=\(.schemaVersion)",
      "QEET_ID_VERSION=\(.version)",
      "QEET_ID_RELEASE=\(.release)",
      "QEET_ID_CANDIDATE=\(.candidate)",
      "QEET_ID_CREATED_AT=\(.createdAt)",
      "QEET_ID_DATA_EPOCH=\(.dataEpoch)",
      "QEET_ID_MIN_KIT_VERSION=\(.minTestKitVersion)",
      "QEET_ID_SERVER_IMAGE=\(img(.components.server))",
      "QEET_ID_SERVER_REVISION=\(.components.server.revision)",
      "QEET_ID_SERVER_SCHEMA_VERSION=\(.components.server.schemaVersion)",
      "QEET_ID_LOGIN_IMAGE=\(img(.components.login))",
      "QEET_ID_LOGIN_REVISION=\(.components.login.revision)",
      "QEET_ID_CONSOLE_IMAGE=\(img(.components.console))",
      "QEET_ID_CONSOLE_REVISION=\(.components.console.revision)",
      "QEET_ID_WEBSITE_IMAGE=\(img(.components.website))",
      "QEET_ID_WEBSITE_REVISION=\(.components.website.revision)",
      "QEET_ID_DOCS_IMAGE=\(img(.components.docs))",
      "QEET_ID_DOCS_REVISION=\(.components.docs.revision)",
      "QEET_ID_PLATFORMS=\([.components[].platforms] | reduce .[1:][] as $p (.[0]; map(select(. as $x | $p | index($x)))) | join(","))"
    ] + (if .seed then ["QEET_ID_SEED_ARGS=\(.seed.args | join(","))"] else [] end)
    | sort | .[]' "$1"
}

# ----------------------------------------------------------------- publish ---

cmd_publish() {
  local out=${1:?OUT_DIR} version args=() line
  version=$(jq -r .version "$out/manifest.json")
  exists "$RELEASE_REPO:$version" && err "$RELEASE_REPO:$version already exists; candidates are immutable"
  while IFS= read -r line; do args+=(--label "qeet.release.$line"); done < "$out/release.env"
  printf 'FROM scratch\nCOPY manifest.json /qeet-id-release/manifest.json\n' > "$out/Dockerfile"
  docker buildx build "$out" --platform linux/amd64,linux/arm64 \
    --label "org.opencontainers.image.source=https://github.com/$SOURCE_OWNER/qeet-id-kit" \
    --label "org.opencontainers.image.title=Qeet ID release candidate" \
    --label "org.opencontainers.image.version=$version" \
    --annotation "index:org.opencontainers.image.source=https://github.com/$SOURCE_OWNER/qeet-id-kit" \
    "${args[@]}" --tag "$RELEASE_REPO:$version" --push
  docker buildx imagetools create --tag "$RELEASE_REPO:test" "$RELEASE_REPO:$version"
  note "published $RELEASE_REPO:$version and moved test -> $version"
}

# ----------------------------------------------------------------- promote ---

cmd_promote() {
  local target=${1:?TARGET} candidate=${2:?CANDIDATE} digest required release tag
  [[ $candidate =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-rc\.[1-9][0-9]*$ ]] ||
    err "candidate must look like 0.1.19-rc.3"
  exists "$RELEASE_REPO:$candidate" || err "$candidate has not been published"
  digest=$(index_digest "$RELEASE_REPO:$candidate")
  case "$target" in
    test) required="" tag=test ;;
    staging) required=test tag=staging ;;
    production-approved) required=staging tag=production-approved ;;
    final) required=production-approved tag=${candidate%-rc.*} ;;
    *) err "target must be test, staging, production-approved or final" ;;
  esac
  if [ -n "$required" ]; then
    exists "$RELEASE_REPO:$required" || err "nothing is on $required yet"
    [ "$(index_digest "$RELEASE_REPO:$required")" = "$digest" ] ||
      err "$candidate is not what $required currently points to — only the candidate that passed $required can be promoted to $target"
  fi
  if [ "$target" = final ]; then
    release=${candidate%-rc.*}
    exists "$RELEASE_REPO:$release" && err "final BOM $release already exists"
  fi
  docker buildx imagetools create --tag "$RELEASE_REPO:$tag" "$RELEASE_REPO@$digest"
  note "$RELEASE_REPO:$tag -> $candidate ($digest)"
}

case "${1:-}" in
  assemble) shift; cmd_assemble "$@" ;;
  to-env) shift; cmd_to_env "$@" ;;
  publish) shift; cmd_publish "$@" ;;
  promote) shift; cmd_promote "$@" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac

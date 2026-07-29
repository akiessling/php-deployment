#!/usr/bin/env bash

set -Eeuo pipefail

readonly IMAGE="${IMAGE:-akiessling/php-deployment}"
readonly PLATFORM="${PLATFORM:-linux/amd64}"
readonly DOCKERFILE="${DOCKERFILE:-Dockerfile}"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local answer

  if [[ "$default" == "y" ]]; then
    read -r -p "$prompt [Y/n] " answer
    answer="${answer:-y}"
  else
    read -r -p "$prompt [y/N] " answer
    answer="${answer:-n}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

detect_latest_composer_version() {
  local output

  printf 'Detecting the current Composer version from composer:latest ...\n' >&2
  output="$(docker run --rm composer:latest --version 2>/dev/null)" ||
    die "Could not detect the Composer version."

  sed -nE 's/^Composer version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' <<<"$output" |
    head -n 1
}

update_composer_version() {
  local version="$1"
  local temporary_file

  grep -Eq '^FROM composer:[^[:space:]]+ AS composer$' "$DOCKERFILE" ||
    die "Could not find a matching Composer FROM line in $DOCKERFILE."

  temporary_file="$(mktemp "${DOCKERFILE}.XXXXXX")"
  awk -v version="$version" '
    /^FROM composer:[^[:space:]]+ AS composer$/ {
      print "FROM composer:" version " AS composer"
      next
    }
    { print }
  ' "$DOCKERFILE" >"$temporary_file"
  command cp "$temporary_file" "$DOCKERFILE"
  command rm "$temporary_file"
}

command -v docker >/dev/null 2>&1 || die "Docker was not found."
command -v git >/dev/null 2>&1 || die "Git was not found."
docker info >/dev/null 2>&1 || die "Docker is not running or cannot be reached."
docker buildx version >/dev/null 2>&1 || die "Docker Buildx is not available."
[[ -f "$DOCKERFILE" ]] || die "$DOCKERFILE was not found."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  die "The script must be run inside a Git working tree."

composer_version="${1:-}"
if [[ -z "$composer_version" ]]; then
  detected_version="$(detect_latest_composer_version)"
  [[ -n "$detected_version" ]] || die "Could not read the Composer version."

  read -r -p "Composer version [$detected_version]: " composer_version
  composer_version="${composer_version:-$detected_version}"
fi

[[ "$composer_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die "Invalid Composer version: $composer_version (expected: x.y.z)"

update_composer_version "$composer_version"
printf 'Dockerfile now uses Composer %s.\n' "$composer_version"

temporary_tag="${IMAGE}:build-${composer_version}-$$"
cleanup() {
  docker image rm "$temporary_tag" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Building %s for %s ...\n' "$temporary_tag" "$PLATFORM"
docker buildx build \
  --platform "$PLATFORM" \
  --load \
  --tag "$temporary_tag" \
  --file "$DOCKERFILE" \
  .

php_version="$(
  docker run --rm --platform "$PLATFORM" "$temporary_tag" \
    php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;'
)"
[[ "$php_version" =~ ^[0-9]+\.[0-9]+$ ]] ||
  die "Could not read the PHP version from the image."

version_tag="${php_version}-${composer_version}"
full_version_tag="${IMAGE}:${version_tag}"
latest_tag="${IMAGE}:latest"

docker tag "$temporary_tag" "$full_version_tag"
docker tag "$temporary_tag" "$latest_tag"

printf '\nCreated tags:\n  %s\n  %s\n\n' "$full_version_tag" "$latest_tag"

if git rev-parse --verify --quiet "refs/tags/$version_tag" >/dev/null; then
  die "Git tag $version_tag already exists."
fi

if git diff --quiet HEAD -- "$DOCKERFILE"; then
  printf 'Dockerfile is unchanged; no Git commit is required.\n'
else
  git commit --only \
    --message "rebuild image with composer $composer_version" \
    -- "$DOCKERFILE"
fi

git tag "$version_tag"
printf 'Created Git tag %s at commit %s.\n\n' \
  "$version_tag" \
  "$(git rev-parse --short HEAD)"

if confirm "Push both tags to Docker Hub?"; then
  docker push "$full_version_tag"
  docker push "$latest_tag"
  printf '\nDone: pushed %s and %s.\n' "$full_version_tag" "$latest_tag"
else
  printf 'Push skipped. Both tags remain available locally.\n'
fi

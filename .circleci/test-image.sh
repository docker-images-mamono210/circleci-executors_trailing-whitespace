#!/usr/bin/env bash
# Usage: bash .circleci/test-image.sh IMAGE[:TAG|@DIGEST]
# The image must already be available in the selected Docker daemon.
set -euo pipefail

trap 'status=$?; if [ "$status" -ne 0 ]; then printf "RESULT: FAIL\n" >&2; fi' EXIT

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'Usage: bash %s IMAGE[:TAG|@DIGEST]\n' "$0" >&2
  exit 2
fi

image="$1"
command -v docker >/dev/null
docker info >/dev/null

configured_user=$(docker image inspect --format '{{.Config.User}}' "$image")
image_platform=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")
image_id=$(docker image inspect --format '{{.Id}}' "$image")
repo_digests=$(docker image inspect --format '{{json .RepoDigests}}' "$image")

printf 'IMAGE: %s\nImage ID: %s\nRepoDigests: %s\n' "$image" "$image_id" "$repo_digests"
printf 'Configured user: %s\nImage platform: %s\n' "$configured_user" "$image_platform"
printf 'Started at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$configured_user" != 'circleci' ]; then
  printf 'ERROR: Expected the configured user to be circleci.\n' >&2
  exit 1
fi
if [ "$image_platform" != 'linux/amd64' ]; then
  printf 'ERROR: Expected the image platform to be linux/amd64.\n' >&2
  exit 1
fi

docker run --rm --pull=never --platform linux/amd64 --network none -i \
  --entrypoint /bin/bash "$image" -s <<'CONTAINER_SCRIPT'
set -euo pipefail

actual_user=$(id -un)
actual_uid=$(id -u)
actual_gid=$(id -g)
printf 'Actual user: %s; uid=%s; gid=%s\n' "$actual_user" "$actual_uid" "$actual_gid"
if [ "$actual_user" != 'circleci' ] || [ "$actual_uid" != '3434' ] || [ "$actual_gid" != '3434' ]; then
  printf 'ERROR: Expected circleci with UID/GID 3434.\n' >&2
  exit 1
fi

. /etc/os-release
printf 'OS: %s\n' "$PRETTY_NAME"
python --version
python -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 14) else "Expected Python 3.14.x")'
git --version
command -v trailing-whitespace

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"
git -c init.defaultBranch=main init --quiet

# A tracked file without trailing spaces must succeed.
printf 'first line\nsecond line\n' > sample.txt
git add -- sample.txt
clean_status=0
trailing-whitespace > clean-output.log 2>&1 || clean_status=$?
cat clean-output.log
if [ "$clean_status" -ne 0 ]; then
  printf 'ERROR: Clean fixture returned %s; expected 0.\n' "$clean_status" >&2
  exit 1
fi
printf 'PASS: clean tracked file (exit 0)\n'

# Generate a trailing space without adding one to this script's source.
printf 'first line\nsecond line \n' > sample.txt
git add -- sample.txt
dirty_status=0
trailing-whitespace > dirty-output.log 2>&1 || dirty_status=$?
cat dirty-output.log
if [ "$dirty_status" -ne 1 ]; then
  printf 'ERROR: Trailing-space fixture returned %s; expected 1.\n' "$dirty_status" >&2
  exit 1
fi
if ! grep -Fxq './sample.txt:2' dirty-output.log; then
  printf 'ERROR: The expected file and line number were not reported.\n' >&2
  exit 1
fi
printf 'PASS: trailing-space fixture (exit 1, ./sample.txt:2)\n'
CONTAINER_SCRIPT

printf 'RESULT: PASS\n'
printf 'Finished at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

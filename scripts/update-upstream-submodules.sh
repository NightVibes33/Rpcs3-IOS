#!/bin/bash
set -euo pipefail

REPO="${1:?usage: update-upstream-submodules.sh <repo> [attempts]}"
ATTEMPTS="${2:-4}"
JOBS="${SUBMODULE_JOBS:-2}"
RETRY_DELAY_BASE="${SUBMODULE_RETRY_DELAY_BASE:-15}"

if [[ ! -d "$REPO/.git" ]]; then
  echo "Not a git repository: $REPO" >&2
  exit 2
fi

# GitHub's hosted macOS runners occasionally time out while fetching RPCS3's
# deeply nested submodules. Keep the checkout deterministic, but retry the
# exact pinned commits instead of allowing a transient network failure to
# invalidate an otherwise healthy iOS build.
git -C "$REPO" config http.version HTTP/1.1
git -C "$REPO" config http.lowSpeedLimit 1000
git -C "$REPO" config http.lowSpeedTime 120

git -C "$REPO" submodule sync --recursive

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
  echo "Submodule checkout attempt $attempt/$ATTEMPTS (jobs=$JOBS)"
  if git -C "$REPO" submodule update --init --recursive --depth 1 --jobs "$JOBS"; then
    git -C "$REPO" submodule status --recursive
    echo "PASS: upstream submodules initialized"
    exit 0
  fi

  if (( attempt < ATTEMPTS )); then
    delay=$((attempt * RETRY_DELAY_BASE))
    echo "Submodule checkout failed; retrying in ${delay}s" >&2
    sleep "$delay"
  fi
done

echo "Submodule checkout failed after $ATTEMPTS attempts" >&2
exit 1

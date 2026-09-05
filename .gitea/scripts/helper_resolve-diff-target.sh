#!/usr/bin/env bash
# Sourceable helper — resolves DIFF_TARGET based on event type.
#
# Expected variables (set before calling):
#   EVENT_NAME   — e.g. "pull_request", "push"
#   BASE_BRANCH  — e.g. "origin/main"
#   EVENT_BEFORE — (optional) commit SHA before the push event
#
# Sets:
#   DIFF_TARGET  — git diff range or ref to diff against

resolve_diff_target() {
  if [ "${EVENT_NAME}" = "pull_request" ]; then
    echo ""
    echo ">> Checking for changes in a pull request ..."
    # If the PR was automerged before this step runs, origin/main might already
    # include our changes, causing the standard diff to be empty.
    if git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null | grep -q . ; then
      DIFF_TARGET="${BASE_BRANCH}...HEAD"
    else
      echo ">> Diff against ${BASE_BRANCH}...HEAD is empty (likely already merged). Falling back to HEAD^1..HEAD"
      DIFF_TARGET="HEAD^1..HEAD"
    fi
  else
    local BEFORE="${EVENT_BEFORE:-}"
    if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
      DIFF_TARGET="HEAD^1..HEAD"
    else
      DIFF_TARGET="${BEFORE}..HEAD"
    fi

    echo ""
    echo ">> Checking for changes from a push (Diff target: ${DIFF_TARGET}) ..."
  fi
}

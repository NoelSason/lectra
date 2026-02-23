#!/bin/bash
set -e

# Claim next eligible ticket
ISSUE_URL=$(./scripts/claim-next-ticket.sh)

if [ -z "$ISSUE_URL" ]; then
  echo "❌ No eligible tickets found."
  exit 1
fi

echo "✅ Claimed: $ISSUE_URL"

# Launch Antigravity / Codex with issue context
codex start \
  --context "Working on GitHub issue: $ISSUE_URL"

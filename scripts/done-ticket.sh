#!/bin/bash
set -e

FILE=".active-ticket.md"

if [ ! -f "$FILE" ]; then
  echo "❌ No active ticket file found."
  exit 1
fi

# Extract issue number
ISSUE_NUMBER=$(grep -E "^Issue: #" "$FILE" | grep -oE "[0-9]+")

if [ -z "$ISSUE_NUMBER" ]; then
  echo "❌ Could not find issue number."
  exit 1
fi

echo "✅ Closing issue #$ISSUE_NUMBER..."

# Close issue
gh issue close "$ISSUE_NUMBER" --comment "Resolved via local workflow"

# Remove in-progress just in case
gh issue edit "$ISSUE_NUMBER" --remove-label in-progress >/dev/null || true

# Archive file
mkdir -p .tickets-archive
mv "$FILE" ".tickets-archive/issue-$ISSUE_NUMBER.md"

echo "📦 Archived to .tickets-archive/issue-$ISSUE_NUMBER.md"

# Refresh queue
./scripts/start-antigravity.sh

echo "�� Done. Queue refreshed."

#!/bin/bash
set -e

# Find first open, ready issue that is NOT in-progress
ISSUE_NUMBER=$(gh issue list \
  --state open \
  --label ready \
  --json number,labels \
  --jq '.[] | select(.labels | all(.name != "in-progress")) | .number' \
  | head -n 1)

# If none found
if [ -z "$ISSUE_NUMBER" ]; then
  echo "No tickets"
  exit 0
fi

# Mark as in-progress
gh issue edit "$ISSUE_NUMBER" --add-label in-progress >/dev/null

# Print URL (ONLY ONCE)
echo "https://github.com/NoelSason/lectra/issues/$ISSUE_NUMBER"

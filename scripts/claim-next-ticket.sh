#!/bin/bash

ISSUE=$(gh issue list \
  --label ready \
  --label "P1,P2,P3" \
  --state open \
  --json number,labels \
  --limit 20 \
  --jq '.[] | select([.labels[].name] | index("in-progress") | not) | .number' \
  | head -n 1)

if [ -z "$ISSUE" ]; then
  echo "No tickets"
  exit 1
fi

gh issue edit $ISSUE \
  --add-label in-progress \
  --add-assignee @me

gh issue comment $ISSUE \
  --body "Claimed by Antigravity 🚀"

echo $ISSUE

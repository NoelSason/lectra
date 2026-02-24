#!/bin/bash
set -e

echo "📋 Syncing ticket queue..."

OUTPUT=".tickets.md"

echo "# 🎯 Lectra Engineering Queue" > $OUTPUT
echo "" >> $OUTPUT
echo "Last Updated: $(date)" >> $OUTPUT
echo "" >> $OUTPUT
echo "---" >> $OUTPUT
echo "" >> $OUTPUT


build_section () {
  PRIORITY=$1
  TITLE=$2

  echo "## $TITLE" >> $OUTPUT
  echo "" >> $OUTPUT

  gh issue list \
    --state open \
    --label "$PRIORITY" \
    --json number,title,body,labels,url \
    --jq '.[]' | while read -r issue; do

      NUMBER=$(echo "$issue" | jq -r '.number')
      NAME=$(echo "$issue" | jq -r '.title')
      URL=$(echo "$issue" | jq -r '.url')

      STATUS="ready"

      if echo "$issue" | jq -r '.labels[].name' | grep -q in-progress; then
        STATUS="in-progress"
      fi

            BODY=$(echo "$issue" | jq -r '.body')

      echo "### #$NUMBER $NAME" >> $OUTPUT
      echo "Status: $STATUS" >> $OUTPUT
      echo "URL: $URL" >> $OUTPUT
      echo "" >> $OUTPUT

      if [ "$BODY" != "null" ] && [ -n "$BODY" ]; then
        echo "**Description:**" >> $OUTPUT
        echo "" >> $OUTPUT
        echo "$BODY" >> $OUTPUT
        echo "" >> $OUTPUT
      fi

  done

  echo "---" >> $OUTPUT
  echo "" >> $OUTPUT
}


build_section "P1" "🔴 P1 — Critical"
build_section "P2" "🟠 P2 — Important"
build_section "P3" "🟢 P3 — Minor"


echo "✅ Ticket queue updated: $OUTPUT"
echo "👉 Open with: code $OUTPUT"

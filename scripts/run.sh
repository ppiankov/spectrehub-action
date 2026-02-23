#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${1:-0}"
FORMAT="${2:-text}"

# Free tier: cap at 3 targets unless license key is set
MAX_TARGETS=3
if [ -n "${SPECTREHUB_LICENSE_KEY:-}" ]; then
  MAX_TARGETS=0  # 0 = unlimited
  echo "License key detected — paid tier (unlimited targets)"
else
  echo "Free tier — up to ${MAX_TARGETS} targets"
fi

# Discover available tools
echo ""
echo "=== Discovery ==="
spectrehub discover --format json > /tmp/spectrehub-discovery.json
spectrehub discover

RUNNABLE=$(jq '.total_runnable' /tmp/spectrehub-discovery.json)

if [ "$RUNNABLE" -eq 0 ]; then
  echo "::warning::No runnable tools found. Configure infrastructure credentials."
  echo "total_issues=0" >> "$GITHUB_OUTPUT"
  echo "health_score=0" >> "$GITHUB_OUTPUT"
  echo "health_level=unknown" >> "$GITHUB_OUTPUT"
  echo "tools_run=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Free tier enforcement
if [ "$MAX_TARGETS" -gt 0 ] && [ "$RUNNABLE" -gt "$MAX_TARGETS" ]; then
  echo "::warning::Free tier: ${RUNNABLE} targets found but limited to ${MAX_TARGETS}. Set SPECTREHUB_LICENSE_KEY for unlimited."
fi

# Run spectrehub
echo ""
echo "=== Execution ==="
REPORT_FILE="/tmp/spectrehub-report.json"
EXIT_CODE=0

spectrehub run \
  --format json \
  --fail-threshold "$THRESHOLD" \
  > "$REPORT_FILE" 2>/tmp/spectrehub-stderr.txt || EXIT_CODE=$?

# Also generate text report for PR comment
spectrehub run \
  --format text \
  --dry-run 2>/dev/null || true
# Re-run with text for display (dry-run shows plan only, we need actual text)
# The JSON report is the source of truth

# Extract outputs from JSON report
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
  TOTAL_ISSUES=$(jq -r '.summary.total_issues // 0' "$REPORT_FILE")
  HEALTH_SCORE=$(jq -r '.summary.score_percent // 0' "$REPORT_FILE")
  HEALTH_LEVEL=$(jq -r '.summary.health_score // "unknown"' "$REPORT_FILE")
  TOOLS_RUN=$(jq -r '.summary.total_tools // 0' "$REPORT_FILE")
else
  TOTAL_ISSUES=0
  HEALTH_SCORE=0
  HEALTH_LEVEL="unknown"
  TOOLS_RUN=0
fi

# Set outputs
echo "total_issues=${TOTAL_ISSUES}" >> "$GITHUB_OUTPUT"
echo "health_score=${HEALTH_SCORE}" >> "$GITHUB_OUTPUT"
echo "health_level=${HEALTH_LEVEL}" >> "$GITHUB_OUTPUT"
echo "tools_run=${TOOLS_RUN}" >> "$GITHUB_OUTPUT"
echo "report_json=${REPORT_FILE}" >> "$GITHUB_OUTPUT"

echo ""
echo "=== Results ==="
echo "Tools run:    ${TOOLS_RUN}"
echo "Total issues: ${TOTAL_ISSUES}"
echo "Health score: ${HEALTH_LEVEL} (${HEALTH_SCORE}%)"

# Paid tier: send report to API and fetch trends
TREND_INFO=""
if [ -n "${SPECTREHUB_LICENSE_KEY:-}" ] && [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
  API_URL="${SPECTREHUB_API_URL:-https://api.spectrehub.dev}"
  REPO_NAME="${GITHUB_REPOSITORY:-unknown}"

  echo ""
  echo "=== Paid Tier: Sending report to API ==="

  # Build API payload
  API_PAYLOAD=$(jq -n \
    --arg repo "$REPO_NAME" \
    --argjson tools "${TOOLS_RUN}" \
    --argjson issues "${TOTAL_ISSUES}" \
    --argjson score "${HEALTH_SCORE}" \
    --arg health "${HEALTH_LEVEL}" \
    --arg raw "$(cat "$REPORT_FILE")" \
    '{repo: $repo, total_tools: $tools, issues: $issues, score: $score, health: $health, raw_json: $raw}')

  # POST report
  API_RESPONSE=$(curl -fsSL -X POST "${API_URL}/v1/reports" \
    -H "Authorization: Bearer ${SPECTREHUB_LICENSE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD" 2>/dev/null || echo '{"error":"api unreachable"}')
  echo "API response: ${API_RESPONSE}"

  # Fetch trends for PR comment enrichment
  TREND_RESPONSE=$(curl -fsSL "${API_URL}/v1/trends?repo=${REPO_NAME}&days=30" \
    -H "Authorization: Bearer ${SPECTREHUB_LICENSE_KEY}" 2>/dev/null || echo '{"trends":[]}')

  TREND_COUNT=$(echo "$TREND_RESPONSE" | jq '.trends | length' 2>/dev/null || echo "0")
  if [ "$TREND_COUNT" -gt 1 ]; then
    PREV_ISSUES=$(echo "$TREND_RESPONSE" | jq '.trends[-2].issues // 0' 2>/dev/null || echo "0")
    TREND_INFO="Previous run: ${PREV_ISSUES} issues"
    if [ "$TOTAL_ISSUES" -lt "$PREV_ISSUES" ]; then
      TREND_INFO="${TREND_INFO} (improving)"
    elif [ "$TOTAL_ISSUES" -gt "$PREV_ISSUES" ]; then
      TREND_INFO="${TREND_INFO} (degrading)"
    else
      TREND_INFO="${TREND_INFO} (stable)"
    fi
    echo "Trend: ${TREND_INFO}"
  fi
fi

# Store report in step summary
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
  {
    echo "### SpectreHub Audit Results"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Tools run | ${TOOLS_RUN} |"
    echo "| Total issues | ${TOTAL_ISSUES} |"
    echo "| Health score | ${HEALTH_LEVEL} (${HEALTH_SCORE}%) |"
    echo ""

    # Issue breakdown by tool
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
      echo "#### Issues by Tool"
      echo ""
      echo "| Tool | Issues |"
      echo "|------|--------|"
      jq -r '.summary.issues_by_tool // {} | to_entries[] | "| \(.key) | \(.value) |"' "$REPORT_FILE"
      echo ""
    fi

    # Trend info (paid tier)
    if [ -n "$TREND_INFO" ]; then
      echo "#### Trend"
      echo ""
      echo "${TREND_INFO}"
      echo ""
    fi

    # Threshold check
    if [ "$EXIT_CODE" -eq 1 ]; then
      echo "> **⚠ Threshold exceeded:** ${TOTAL_ISSUES} issues > ${THRESHOLD} threshold"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$EXIT_CODE"

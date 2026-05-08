#!/bin/bash
# Create a new Jira ticket for each workflow run; attach markdown summary only (JSON/SBOM via GA Artifacts).
#
# DEMO: replace JIRA_BASE with your Atlassian site (https://yourcompany.atlassian.net/rest/api/3).
set -euo pipefail

REPO_NAME="$1"
EPIC_KEY="$2"
RUN_ID="$3"
JIRA_EMAIL="$4"
JIRA_TOKEN="$5"
ASSIGNEE_ACCOUNT_ID="${6:-}"
RUN_URL="$7"
S3_BASE="$8"
MARKDOWN_PATH="${9:-}"

JIRA_BASE="${JIRA_BASE:-https://demo-placeholder.atlassian.net/rest/api/3}"
SUMMARY="SBOM / Inspector: HIGH or CRITICAL vulnerabilities detected — ${REPO_NAME} (GitHub run ${RUN_ID})"

# Atlassian Document Format: link to workflow run + Artifacts; only MD attached in Jira.
DESC_ADF=$(jq -n \
  --arg repo "$REPO_NAME" \
  --arg rid "$RUN_ID" \
  --arg url "$RUN_URL" \
  --arg s3 "$S3_BASE" \
  '{
    type: "doc",
    version: 1,
    content: (
      [
        {
          type: "paragraph",
          content: [
            { type: "text", text: "HIGH or CRITICAL vulnerabilities were detected in the Amazon Inspector scan for " },
            { type: "text", text: $repo, marks: [{ type: "strong" }] },
            { type: "text", text: " (GitHub Actions run " },
            { type: "text", text: $rid, marks: [{ type: "code" }] },
            { type: "text", text: "). See the attached markdown summary and workflow artifacts for details." }
          ]
        },
        {
          type: "paragraph",
          content: [
            { type: "text", text: "Workflow run: " },
            { type: "text", text: "GitHub Actions", marks: [{ type: "link", attrs: { href: $url } }] },
            { type: "text", text: ". Open " },
            { type: "text", text: "Artifacts", marks: [{ type: "strong" }] },
            { type: "text", text: " on that page to download SBOM JSON, Inspector scan JSON/CSV, and other outputs. This ticket attaches only the markdown summary." }
          ]
        }
      ] + (
        if ($s3 != "none") and (($s3 | length) > 0) then
          [{
            type: "paragraph",
            content: [
              { type: "text", text: "S3 evidence prefix: " },
              { type: "text", text: $s3, marks: [{ type: "code" }] }
            ]
          }]
        else
          []
        end
      )
    )
  }')

if [ -n "$ASSIGNEE_ACCOUNT_ID" ]; then
  CREATE_PAYLOAD=$(jq -n \
    --arg project "DEMO" \
    --arg parent "$EPIC_KEY" \
    --arg summary "$SUMMARY" \
    --arg assignee "$ASSIGNEE_ACCOUNT_ID" \
    --argjson description "$DESC_ADF" \
    '{
      fields: {
        project: { key: $project },
        parent: { key: $parent },
        issuetype: { name: "Config" },
        summary: $summary,
        description: $description,
        assignee: { accountId: $assignee }
      }
    }')
else
  CREATE_PAYLOAD=$(jq -n \
    --arg project "DEMO" \
    --arg parent "$EPIC_KEY" \
    --arg summary "$SUMMARY" \
    --argjson description "$DESC_ADF" \
    '{
      fields: {
        project: { key: $project },
        parent: { key: $parent },
        issuetype: { name: "Config" },
        summary: $summary,
        description: $description
      }
    }')
fi

CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_BASE}/issue" \
  -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "$CREATE_PAYLOAD")
CREATE_BODY=$(echo "$CREATE_RESP" | head -n -1)
CREATE_CODE=$(echo "$CREATE_RESP" | tail -n 1)

if [ "$CREATE_CODE" -lt 200 ] || [ "$CREATE_CODE" -ge 300 ]; then
  echo "::warning::Jira create failed ($CREATE_CODE): $CREATE_BODY"
  exit 0
fi

ISSUE_KEY=$(echo "$CREATE_BODY" | jq -r '.key')
echo "Created ticket $ISSUE_KEY"

DATE_FULL=$(date -u +%Y-%m-%dT%H:%MZ)
if [ -n "$MARKDOWN_PATH" ] && [ -f "$MARKDOWN_PATH" ]; then
  ATT_NAME="inspector-scan-run-${RUN_ID}-${DATE_FULL}.md"
  TMP_ATTACH=$(mktemp)
  cp "$MARKDOWN_PATH" "$TMP_ATTACH"
  ATT_RESP=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_BASE}/issue/${ISSUE_KEY}/attachments" \
    -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@${TMP_ATTACH};filename=${ATT_NAME}")
  rm -f "$TMP_ATTACH"
  ATT_CODE=$(echo "$ATT_RESP" | tail -n 1)
  if [ "$ATT_CODE" -ge 200 ] && [ "$ATT_CODE" -lt 300 ]; then
    echo "Attached markdown report to $ISSUE_KEY"
  else
    echo "::warning::Jira attachment failed ($ATT_CODE): $(echo "$ATT_RESP" | head -n -1)"
  fi
else
  echo "No markdown report to attach (path missing or empty)."
fi

echo "jira_key=$ISSUE_KEY"

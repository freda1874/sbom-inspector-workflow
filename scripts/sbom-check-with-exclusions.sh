#!/bin/bash
# SBOM scan check with CVE exclusions.
# Reads accepted CVEs from sbom-accepted-cves.json (repo root by default) and excludes them
# from the Critical/High count before deciding pass/fail.
#
# Modes:
#   Default: exit 0 if all remaining issues are fixed or in accepted list, else exit 1 (strict / local).
#   SBOM_INFORMATIONAL=1: never exit 1; if GITHUB_OUTPUT is set, write should_create, remaining, excluded, gate_source.
set -euo pipefail

SCAN_CSV="${1:?Usage: $0 <scan_csv_path> [accepted_json]}"
ACCEPTED_JSON="${2:-sbom-accepted-cves.json}"
INFORMATIONAL="${SBOM_INFORMATIONAL:-0}"

log_err() { echo "::error::$*"; }
log_warn() { echo "::warning::$*"; }
log_notice() { echo "::notice::$*"; }

write_outputs() {
  local should rem exc src
  should="$1"
  rem="$2"
  exc="$3"
  src="$4"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "should_create=${should}" >> "$GITHUB_OUTPUT"
    echo "remaining_after_exclusions=${rem}" >> "$GITHUB_OUTPUT"
    echo "excluded_from_gate=${exc}" >> "$GITHUB_OUTPUT"
    echo "gate_source=${src}" >> "$GITHUB_OUTPUT"
  fi
}

if [ ! -f "$SCAN_CSV" ]; then
  if [ "$INFORMATIONAL" = "1" ] || [ "$INFORMATIONAL" = "true" ]; then
    log_warn "Scan CSV not found: $SCAN_CSV (caller should fall back to JSON aggregate for Jira if needed)"
    write_outputs "false" "0" "0" "no_csv"
    exit 0
  fi
  log_err "Scan CSV not found: $SCAN_CSV"
  exit 1
fi

# Extract accepted CVE IDs from JSON (handles missing file)
ACCEPTED_IDS=()
if [ -f "$ACCEPTED_JSON" ]; then
  ACCEPTED_IDS=($(jq -r '.accepted_cves[]? | .id // empty' "$ACCEPTED_JSON" 2>/dev/null || true))
fi

# Get Critical and High findings (skip header rows 1-3)
CRITICAL_HIGH=$(tail -n +4 "$SCAN_CSV" | grep -E ',"critical",|,"high",' || true)
TOTAL=$(echo "$CRITICAL_HIGH" | grep -c . 2>/dev/null || echo 0)
TOTAL=${TOTAL:-0}

# Count how many of those are in the accepted list
EXCLUDED=0
for cve_id in "${ACCEPTED_IDS[@]}"; do
  [ -z "$cve_id" ] && continue
  COUNT=$(echo "$CRITICAL_HIGH" | grep -c "\"$cve_id\"" 2>/dev/null || echo 0)
  COUNT=${COUNT:-0}
  EXCLUDED=$((EXCLUDED + COUNT))
  if [ "${COUNT:-0}" -gt 0 ]; then
    REASON=$(jq -r --arg id "$cve_id" '.accepted_cves[]? | select(.id == $id) | .reason // "accepted"' "$ACCEPTED_JSON" 2>/dev/null || echo "accepted")
    log_notice "Excluded from gate: $cve_id (count in CSV: $COUNT) — $REASON"
  fi
done

REMAINING=$((TOTAL - EXCLUDED))
if [ "${REMAINING:-0}" -lt 0 ]; then
  REMAINING=0
fi

echo "Critical+High rows in CSV: $TOTAL; excluded: $EXCLUDED; remaining for gate: $REMAINING"

if [ "$INFORMATIONAL" = "1" ] || [ "$INFORMATIONAL" = "true" ]; then
  if [ "${REMAINING:-0}" -le 0 ]; then
    log_notice "After exclusions: no remaining Critical/High in CSV (or none present). Jira: should_create=false"
    write_outputs "false" "$REMAINING" "$EXCLUDED" "csv_exclusions"
  else
    log_warn "After exclusions: $REMAINING Critical/High row(s) still count toward risk. Jira: may open if other steps succeed"
    write_outputs "true" "$REMAINING" "$EXCLUDED" "csv_exclusions"
  fi
  exit 0
fi

# Strict mode (e.g. optional blocking workflow)
if [ "${REMAINING:-0}" -le 0 ]; then
  log_notice "Pass: All Critical/High vulnerabilities are either fixed or in sbom-accepted-cves.json"
  exit 0
fi

log_err "Fail: $REMAINING Critical/High vulnerabilities remain. Resolve or add to sbom-accepted-cves.json with justification."
exit 1

# SBOM Scan Toolkit

Demo repository showing how to generate a Software Bill of Materials (SBOM), scan a repository with Amazon Inspector, archive the results, and optionally open a Jira ticket when serious vulnerabilities remain.

This repo is intentionally set up as a **reference example**, not a production-ready deployment. The AWS account ID, IAM role ARN, S3 bucket, Jira site, and SSM parameter names are placeholders.

## What this workflow does

The main workflow lives at `.github/workflows/sbom-scan.yml`.

On a schedule or manual run, it:

1. Checks out the repository.
2. Configures AWS credentials through GitHub Actions OIDC.
3. Runs the Amazon Inspector GitHub Action to:
   - generate an SBOM
   - scan the repository for vulnerabilities
   - write JSON, CSV, and Markdown outputs
4. Runs a gating step that:
   - reads the Inspector CSV when available
   - excludes CVEs listed in `sbom-accepted-cves.json`
   - decides whether a Jira ticket should be created
5. Uploads generated files as GitHub Actions artifacts.
6. Optionally uploads those files to S3.
7. Optionally creates a Jira ticket with a Markdown summary attached.

The workflow is **informational by default**. It uses `continue-on-error: true` and very high severity thresholds, so the job demonstrates the flow without blocking merges.

## What is AWS Inspector?

Amazon Inspector is an AWS security service that can analyze software and infrastructure for known vulnerabilities and unintended exposure. In this repo, it is used in its repository scanning mode through the GitHub Action `aws-actions/vulnerability-scan-github-action-for-amazon-inspector`.

For this demo, Inspector is used to:

- build an SBOM for the checked-out repository
- identify vulnerable packages and components
- produce machine-readable and human-readable outputs
- expose counts such as High and Critical findings that downstream steps can act on

In simple terms: the workflow asks Inspector to tell you **what software is in the repo** and **whether any known vulnerable components were found**.

## What is an SBOM?

An SBOM, or Software Bill of Materials, is an inventory of the software components that make up an application or codebase. It is similar to an ingredients list for software.

Teams use SBOMs to:

- understand what packages and dependencies they ship
- investigate exposure when a new CVE is announced
- support audits, compliance, and vendor review processes
- keep security evidence for later review

## Repository layout

```text
.
├── .github/workflows/sbom-scan.yml
├── scripts/sbom-check-with-exclusions.sh
├── scripts/sbom-jira-sync.sh
└── sbom-accepted-cves.json
```

- `.github/workflows/sbom-scan.yml`: the GitHub Actions workflow
- `scripts/sbom-check-with-exclusions.sh`: removes accepted CVEs from the CSV-based gate
- `scripts/sbom-jira-sync.sh`: creates a Jira ticket and attaches the Markdown summary
- `sbom-accepted-cves.json`: accepted-risk list used by the gate

## How the workflow decides whether to create Jira

The workflow does **not** create a Jira ticket for every run.

It first checks whether Inspector produced a CSV file:

- If the CSV exists, `scripts/sbom-check-with-exclusions.sh` counts High and Critical rows, subtracts anything listed in `sbom-accepted-cves.json`, and writes outputs such as `should_create=true` or `false`.
- If the CSV does not exist, the workflow falls back to aggregate counts in the JSON output. In that fallback mode, accepted CVEs are **not** subtracted because the JSON path does not provide the same row-level filtering behavior.

This means the CSV path is the more precise path for demoing accepted-risk handling.

## How to use this repo

### Option 1: Read it as a demo

If your goal is explanation only, start with:

1. `README.md`
2. `.github/workflows/sbom-scan.yml`
3. `scripts/sbom-check-with-exclusions.sh`
4. `scripts/sbom-jira-sync.sh`

That gives you the main workflow, the gate logic, and the Jira integration flow in order.

### Option 2: Run it in your own AWS account

Before running this for real, replace the demo placeholders in `.github/workflows/sbom-scan.yml`:

- `aws-region`
- `role-to-assume`
- S3 bucket and prefix
- SSM parameter names for Jira
- any naming you want for artifacts and outputs

You should also review:

- `scripts/sbom-jira-sync.sh` for your Jira base URL, project key, issue type, and parent relationship
- `sbom-accepted-cves.json` for your own accepted-risk entries

## Required setup for a real run

To make this workflow actually work in a real repository, you need:

1. A GitHub repository with Actions enabled.
2. An AWS account configured for GitHub OIDC federation.
3. An IAM role that GitHub Actions is allowed to assume.
4. Permissions on that role for the Amazon Inspector workflow and any optional S3 or SSM operations.
5. If you keep the Jira steps, a Jira site plus credentials available through SSM or another secret mechanism.

## Manual usage

The workflow supports:

- a scheduled run on the first day of each month
- a manual run through `workflow_dispatch`

To trigger it manually:

1. Push this repo to GitHub.
2. Open the repository's **Actions** tab.
3. Open **Generate SBOM and Scan with Amazon Inspector**.
4. Click **Run workflow**.

## Outputs you get

The workflow writes four main outputs:

- `sbom_lex_api_spdx.json`: the generated SBOM
- `inspector_scan_results.json`: Inspector scan output
- `inspector_scan_results.csv`: tabular findings used by the exclusion gate
- `inspector_scan_results.md`: Markdown summary useful for Jira attachment or quick review

It also uploads these as a GitHub artifact named like `demo-sbom-and-scan-<run_id>`.

## Accepted CVEs

`sbom-accepted-cves.json` lets you document risks that are known and intentionally accepted for now.

Each entry includes:

- CVE ID
- package name
- reason
- added date

This is useful when:

- a vulnerable dependency is not actually exercised in your runtime path
- no upstream fix exists yet
- the issue is mitigated another way
- the team has consciously accepted the risk temporarily

Even in a demo repo, this file is important because it explains how the workflow separates **known accepted risk** from **new actionable findings**.

## Important demo note

This repo contains placeholder values on purpose. It is meant to explain the workflow shape and logic, not to be run unchanged.

Examples of placeholder values include:

- AWS account ID `111122223333`
- demo IAM role name
- demo S3 bucket
- demo Jira URL
- demo SSM parameter paths
- demo fallback email

## Suggested customization

If you want to turn this into a reusable template, good next improvements are:

- rename output files to be more generic than `sbom_lex_api_spdx.json`
- make AWS region, role ARN, bucket, and Jira values repository variables or secrets
- add a top-level architecture diagram
- add a sample GitHub Actions run screenshot
- add an example of a generated CSV and Markdown report
 
---
name: kiro-coco
description: >
  AWS + Snowflake integrated solutions combining Kinesis, Lambda, DynamoDB, and
  EventBridge with Snowflake Openflow and Snowpipe Streaming. Use this skill
  whenever the user wants to set up streaming data pipelines from AWS to
  Snowflake, deploy a Kinesis connector, configure Openflow on SPCS, ingest
  real-time data into Snowflake from AWS, set up an Openflow canvas user, or
  build any AWS ↔ Snowflake integration — even if they don't say "kiro-coco"
  explicitly.
---

# Kiro-CoCo: AWS + Snowflake Integrated Solutions

Integrated solutions combining AWS services with Snowflake, built collaboratively between Kiro (AWS) and CoCo (Snowflake).

<!-- AI INSTRUCTIONS
On skill load, follow this workflow:

SKILL_DIR is the directory containing this SKILL.md file.

STEP 1: Show available integrations FIRST
- Read the Sub-folders table below and present the available integrations to the user
- Use AskUserQuestion with options built from the table
  Example: "Kinesis + Openflow streaming ingestion"
- Let the user select which integration they want to work with

STEP 2: After user selects an integration, load and display the workflow FIRST
- Read the selected sub-folder's README.md IN ITS ENTIRETY — do not skip or summarize any section
- You MUST read every section of the document thoroughly before proceeding with any deployment steps
- Display the architecture, workflow, and what will be set up
- Give the user visibility into what we're going to do
- Ask if they want to proceed
- IMPORTANT: Do NOT begin deployment until you have read and understood the complete document.
  Skipping sections leads to missed prerequisites, wrong parameter values, and failed deployments.

STEP 3: After user confirms, THEN run prerequisite checks:
1. Check required CLIs:
   - nipyapi: `~/.snowflake/venv/nipyapi-env/bin/nipyapi --help` — if missing, tell user to run:
     `pip install nipyapi[cli]` in their nipyapi env (~/.snowflake/venv/nipyapi-env)
   - snow: `snow --version` — if missing, help install via `pip install snowflake-cli`
2. Check AWS CLI: `aws --version` — if missing, help install via `brew install awscli` or guide user
3. Check AWS profile: `aws sts get-caller-identity` — try default profile first
   - If fails, ask user for their AWS profile name
   - If succeeds, show account ID and ask user to confirm
4. Check Snowflake connection: run `snow sql -c <SNOWFLAKE_CONNECTION> -q "SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE()" --format json`
   - If fails, ask user which Snowflake connection to use (list available with `snow connection list`)
   - If succeeds, show account/user/role and ask user to confirm
5. Show summary of both connections and ask "Does this look correct?" before proceeding

STEP 4: Execute the integration setup following the README.md instructions

IMPORTANT: Before creating any Snowflake resource (database, table, warehouse, role, network rule,
external access integration, etc.), first check if it already exists:
  - SHOW DATABASES LIKE '<name>';
  - SHOW TABLES LIKE '<name>' IN <db>.<schema>;
  - SHOW WAREHOUSES LIKE '<name>';
  - SHOW ROLES LIKE '<name>';
  - SHOW NETWORK RULES LIKE '<name>';
  - SHOW INTEGRATIONS LIKE '<name>';
If the resource exists, ask the user: "Found existing <RESOURCE_TYPE> '<name>'. Use it, or create a new one with a different name?"
Only create new resources after user confirms.

Similarly, before creating any AWS resource (Kinesis stream, DynamoDB table, Lambda function,
EventBridge rule, IAM role, etc.), first check if it already exists:
  - aws kinesis describe-stream --stream-name <name> --region <region> --profile <profile>
  - aws dynamodb describe-table --table-name <name> --region <region> --profile <profile>
  - aws lambda get-function --function-name <name> --region <region> --profile <profile>
  - aws events describe-rule --name <name> --region <region> --profile <profile>
  - aws iam get-role --role-name <name>
If the resource exists, ask the user: "Found existing <RESOURCE_TYPE> '<name>'. Use it, or create a new one with a different name?"
Only create new resources after user confirms.

IMPORTANT: For the Openflow role identification step (Step 1 in kinesis-openflow):
1. Discover the existing role by running:
     SHOW OPENFLOW DATA PLANE INTEGRATIONS;
   Then for each integration:
     SHOW GRANTS ON INTEGRATION <integration_name>;
   Find the role with OWNERSHIP — this is the candidate <OPENFLOW_ROLE>.
2. Verify the role is granted to runtime service users:
     SHOW GRANTS OF ROLE <candidate_role>;
   Filter for USER grants where grantee_name matches: dpa, integration-secret, runtime-*
3. Present the discovered role to the user: "Found role '<role>' with grants to runtime service users. Use this as <OPENFLOW_ROLE>?"
4. If confirmed, use that role. If the user wants a dedicated role, follow the 1c production path.
5. The Openflow runtime integration names come from:
     SHOW OPENFLOW RUNTIME INTEGRATIONS;
   Use these actual integration names (not placeholders) when granting.
6. After confirming the role, verify the user has it:
     SHOW GRANTS TO USER <current_user>;
   If the role is missing, grant it.

IMPORTANT: For all snow/nipyapi commands in sub-skills, use:
  snow  (system CLI)
  ~/.snowflake/venv/nipyapi-env/bin/nipyapi
-->

## Prerequisites

Before using any integration, verify both CLI tools and connections are working.

**nipyapi** (pre-installed at `~/.snowflake/venv/nipyapi-env`):
```bash
~/.snowflake/venv/nipyapi-env/bin/nipyapi --help
```

**AWS CLI:**
```bash
aws --version
aws sts get-caller-identity --profile <AWS_PROFILE>
```

**Snowflake CLI:**
```bash
snow --version
snow connection test -c <SNOWFLAKE_CONNECTION>
```

If AWS CLI is missing: `brew install awscli` then `aws configure --profile <name>`
If nipyapi is missing: `pip install nipyapi[cli]` in `~/.snowflake/venv/nipyapi-env`

## Sub-folders

Each integration lives in its own sub-folder with a README and relevant artifacts.

| Folder | Integration | AWS Services | Snowflake Features |
|--------|-------------|--------------|-------------------|
| `kinesis-openflow/` | Kinesis → Openflow → Snowflake streaming ingestion | Kinesis, DynamoDB, CloudWatch | Openflow SPCS, Snowpipe Streaming |

See also: `openflow-setup.md` — shared prerequisite covering Openflow runtime discovery, nipyapi profile creation, and canvas UI user setup. Read this before starting any integration if Openflow isn't already configured.

## Conventions

- Each sub-folder contains its own `README.md` with architecture, setup, and teardown steps
- Each sub-folder has a `params.yaml` capturing all configurable values
- Shared prerequisites live at the project root as `.md` files (e.g., `openflow-setup.md`)
- All `snow` commands use the system CLI (`snow`)
- All `nipyapi` commands use `~/.snowflake/venv/nipyapi-env/bin/nipyapi`
- Include cost estimates where applicable
- Include cleanup instructions in every integration

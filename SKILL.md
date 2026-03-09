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
   - nipyapi: `~/kiro-coco-venv/bin/nipyapi --help` — if missing, tell user to run:
     `pip install nipyapi[cli]` in their nipyapi env (~/kiro-coco-venv)
   - snow: `snow --version` — if missing, help install via `pip install snowflake-cli`
2. Check AWS CLI: `aws --version` — if missing, help install via `brew install awscli` or guide user
3. Check AWS profile: `aws sts get-caller-identity` — try default profile first
   - If fails, ask user for their AWS profile name
   - If succeeds, show account ID and ask user to confirm
4. Check Snowflake connection: run `snow sql -c <SNOWFLAKE_CONNECTION> -q "SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE()" --format json`
   - If fails, ask user which Snowflake connection to use (list available with `snow connection list`)
   - If succeeds, show account/user/role and ask user to confirm
5. Check Openflow environment (Snowflake-managed runtime required):
   a. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW DATA PLANE INTEGRATIONS" --format json`
      - Must return at least one integration with enabled=true
      - If empty: STOP — Openflow is not deployed at all.
        Tell the user: "This integration requires a Snowflake-managed Openflow deployment.
        Please deploy Openflow via the Snowflake Control Plane UI first, then return here.
        To get started, search 'Openflow' at https://docs.snowflake.com — look for
        'Set up Snowflake Openflow' or 'Openflow SPCS runtime'."
        Do NOT continue until the user confirms Openflow is deployed.
   b. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW RUNTIME INTEGRATIONS" --format json`
      - Must return at least one integration with enabled=true
      - Check oauth_redirect_uri — must contain snowflakecomputing.app (Snowflake-managed)
      - If only BYOC runtimes exist: STOP — this integration requires Snowflake-managed Openflow.
        Tell the user: "Only BYOC runtimes were found. Please add a Snowflake-managed runtime
        via the Snowflake Control Plane UI, then return here.
        See https://docs.snowflake.com and search 'Openflow SPCS runtime' for instructions."
   c. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT" --format json`
      - At least one service must have status=RUNNING
      - If all suspended: tell user to resume the Openflow runtime first via the Control Plane UI
   d. Run: `~/kiro-coco-venv/bin/nipyapi profiles list_profiles`
      - Must return at least one profile
      - Ask user which profile targets the Snowflake-managed runtime
      - Confirm with: `~/kiro-coco-venv/bin/nipyapi --profile <profile> config nifi_config`
        The host must match the snowflakecomputing.app URL from the runtime integration
      - If no matching profile exists: use openflow-setup.md to create one (this is a config
        step only — Openflow is already deployed, just needs nipyapi wired up)
6. Show summary of all connections and ask "Does this look correct?" before proceeding

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

**Two-role pattern:**
- BASE ROLE = the pre-existing customer role that owns the Openflow data plane integration.
  The Openflow runtime authenticates via OAuth as this role. Discovered automatically —
  the user never needs to know its name. Use it as the "Snowflake Role" in Step 5.
- CANVAS ROLE = a new dedicated role created for human canvas UI access only.

**How to discover and use the base role (do this silently — no user involvement needed):**
1. Run: SHOW OPENFLOW DATA PLANE INTEGRATIONS;
   Then: SHOW GRANTS ON INTEGRATION <integration_name>;
   Find OWNERSHIP → this is <BASE_ROLE>.
2. Grant data privileges directly to <BASE_ROLE>:
     GRANT USAGE ON DATABASE <DB_NAME> TO ROLE <BASE_ROLE>;
     GRANT USAGE ON SCHEMA <DB_NAME>.PUBLIC TO ROLE <BASE_ROLE>;
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE ... TO ROLE <BASE_ROLE>;
     GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE <BASE_ROLE>;
3. Use <BASE_ROLE> as the "Snowflake Role" parameter in Step 5.
4. Verify the current user has <BASE_ROLE>:
     SHOW GRANTS TO USER <current_user>;
   If missing, grant it: GRANT ROLE <BASE_ROLE> TO USER <current_user>;
5. The Openflow runtime integration names come from:
     SHOW OPENFLOW RUNTIME INTEGRATIONS;
   Use these actual names (not placeholders) when granting.

See steering/connector-auth.md for the full architecture explanation.

IMPORTANT: Always create a canvas user (Step 1e) — this is REQUIRED, not optional:
- Create a new dedicated <CANVAS_ROLE> (e.g., <prefix>_CANVAS_RL)
- Grant it endpoint access on both SPCS services (runtime + data plane)
- Grant it USAGE/OPERATE on both integrations
- Create <CANVAS_USER> with default role = <CANVAS_ROLE>
- Ask the user for the canvas username and password
- Do NOT skip this step even for demos

IMPORTANT: For all snow/nipyapi commands in sub-skills, use:
  snow  (system CLI)
  ~/kiro-coco-venv/bin/nipyapi
-->

## Prerequisites

Before using any integration, verify both CLI tools and connections are working.

**nipyapi** (pre-installed at `~/kiro-coco-venv`):
```bash
~/kiro-coco-venv/bin/nipyapi --help
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
If nipyapi is missing: `pip install nipyapi[cli]` in `~/kiro-coco-venv`

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
- All `nipyapi` commands use `~/kiro-coco-venv/bin/nipyapi`
- Include cost estimates where applicable
- Include cleanup instructions in every integration

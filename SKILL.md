---
name: kiro-coco
description: >
  AWS + Snowflake integrated solutions. Use for: Kinesis to Snowflake,
  Openflow connector setup, Snowpipe Streaming from AWS, deploy Kinesis
  connector, configure Openflow on SPCS, canvas user setup, streaming
  ingestion, real-time AWS to Snowflake pipeline. Triggers: kinesis,
  openflow, streaming ingestion, snowpipe streaming, aws to snowflake,
  even if the user doesn't say "kiro-coco" explicitly.
---

# Kiro-CoCo: AWS + Snowflake Integrated Solutions

Integrated solutions combining AWS services with Snowflake, built collaboratively between Kiro (AWS) and CoCo (Snowflake).

SKILL_DIR is the directory containing this SKILL.md file.

## Batch / Regression Mode

For repeated non-interactive runs (regression testing), skip the interactive workflow and use:

1. **`kinesis-openflow/params-regression.yaml`** — pre-filled parameters for HOL environment
2. **`kinesis-openflow/references/regression.md`** — step-by-step batch execution guide

Batch mode runs cleanup → AWS setup → Snowflake setup → deploy → verify with no prompts.
The only manual step is attaching the EAI to the runtime via the Control Plane UI.

> **Usage:** When the user asks to "run regression" or "run batch", load `params-regression.yaml`
> and follow `references/regression.md` phases sequentially. Fill `AWS_SECRET_KEY` before starting.

### Execution Strategy: Maximize Tool Calls

**Intent:** Each regression run is a benchmark for measuring human prompts in a session.
Every tool call (bash, snow sql, nipyapi, etc.) generates an auto-approved permission prompt
that counts as a "human prompt" in session metrics. This is intentional.

**Rules for regression execution:**
- Execute commands **individually** (one per tool call), NOT batched into scripts
- Do NOT combine multiple commands into a single bash call with `&&`
- Do NOT create wrapper scripts that consolidate steps
- Do NOT use `AskUserQuestion` — all decisions are pre-made via params-regression.yaml
- Each `snow sql`, `aws`, `nipyapi`, and `bash` command = 1 tool call = 1 counted prompt
- The user's permissions are configured to auto-approve, so no physical keyboard input is needed
- The session should flow autonomously with maximum individual tool calls

## Workflow

### Step 1: Show available integrations

- Read the Sub-folders table below and present the available integrations to the user
- Use AskUserQuestion with options built from the table
  Example: "Kinesis + Openflow streaming ingestion"
- Let the user select which integration they want to work with

### Step 2: Load and present the integration overview

- Read the selected sub-folder's `guide.md` to understand the architecture, parameters, and components
- Display the architecture, workflow, and what will be set up
- Give the user visibility into what we're going to do
- Ask if they want to proceed
- IMPORTANT: Do NOT begin deployment until you have read and understood the guide.
  Skipping it leads to missed prerequisites, wrong parameter values, and failed deployments.

### Step 3: Run prerequisite checks

1. Check required CLIs:
   - nipyapi: `<SKILL_DIR>/venv/bin/nipyapi --help` — if missing, tell user to run:
     `pip install nipyapi[cli]` in their nipyapi env (`<SKILL_DIR>/venv`)
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
        Tell the user:

        "This integration requires a Snowflake-managed Openflow deployment.
        Before deploying, complete these steps in order:

        Step 1 — Create a dedicated base role (REQUIRED if none exists):
          A non-privileged role is required as the Openflow deployment role.
          ACCOUNTADMIN and other privileged roles are blocked by Snowflake OAuth.
          If you are on a new account or have no suitable role, create one now:

            USE ROLE ACCOUNTADMIN;
            CREATE ROLE OPENFLOW_BASE_RL;
            GRANT ROLE OPENFLOW_BASE_RL TO ROLE ACCOUNTADMIN;

          Note the role name — you will need it in this setup.

        Step 2 — Deploy Openflow via the Snowflake Control Plane UI:
          Search 'Openflow' at https://docs.snowflake.com for the deployment guide.
          When prompted to choose a Snowflake role, select the role from Step 1.

        Step 3 — Return here once the deployment is running.
        Tell me the name of the role you chose and we will continue."

        Do NOT continue until the user confirms Openflow is deployed and provides the role name.
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
   d. Run: `<SKILL_DIR>/venv/bin/nipyapi profiles list_profiles`
      - Must return at least one profile
      - Ask user which profile targets the Snowflake-managed runtime
      - Confirm with: `<SKILL_DIR>/venv/bin/nipyapi --profile <profile> config nifi_config`
        The host must match the snowflakecomputing.app URL from the runtime integration
      - If no matching profile exists: use openflow-setup.md to create one (this is a config
        step only — Openflow is already deployed, just needs nipyapi wired up)
6. Show summary of all connections and ask "Does this look correct?" before proceeding

### Step 4: Execute the integration setup

Follow the integration's `references/setup-steps.md` instructions. Load each reference file on-demand as its phase is reached.

**Before creating any Snowflake resource** (database, table, warehouse, role, network rule,
external access integration, etc.), first check if it already exists:
  - SHOW DATABASES LIKE '<name>';
  - SHOW TABLES LIKE '<name>' IN <db>.<schema>;
  - SHOW WAREHOUSES LIKE '<name>';
  - SHOW ROLES LIKE '<name>';
  - SHOW NETWORK RULES LIKE '<name>';
  - SHOW INTEGRATIONS LIKE '<name>';
If the resource exists, ask the user: "Found existing <RESOURCE_TYPE> '<name>'. Use it, or create a new one with a different name?"
Only create new resources after user confirms.

**Before creating any AWS resource** (Kinesis stream, DynamoDB table, Lambda function,
EventBridge rule, IAM role, etc.), first check if it already exists:
  - aws kinesis describe-stream --stream-name <name> --region <region> --profile <profile>
  - aws dynamodb describe-table --table-name <name> --region <region> --profile <profile>
  - aws lambda get-function --function-name <name> --region <region> --profile <profile>
  - aws events describe-rule --name <name> --region <region> --profile <profile>
  - aws iam get-role --role-name <name>
If the resource exists, ask the user: "Found existing <RESOURCE_TYPE> '<name>'. Use it, or create a new one with a different name?"
Only create new resources after user confirms.

### Step 5: Verify and report

- Load `references/verification.md` and run all checks
- Show row counts, connector status, KCL checkpoint health
- Present summary: "Pipeline running. X rows ingested. Canvas user ready at <URL>."

## Openflow Role Pattern

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
3. Use <BASE_ROLE> as the "Snowflake Role" parameter in Step 5 of setup.
4. Verify the current user has <BASE_ROLE>:
     SHOW GRANTS TO USER <current_user>;
   If missing, grant it: GRANT ROLE <BASE_ROLE> TO USER <current_user>;
5. The Openflow runtime integration names come from:
     SHOW OPENFLOW RUNTIME INTEGRATIONS;
   Use these actual names (not placeholders) when granting.

See `connector-auth.md` for the full architecture explanation.

**IMPORTANT: Always create a canvas user — this is REQUIRED, not optional:**
- Create a new dedicated <CANVAS_ROLE> (e.g., <prefix>_CANVAS_RL)
- Grant it endpoint access on both SPCS services (runtime + data plane)
- Grant it USAGE/OPERATE on both integrations
- Create <CANVAS_USER> with default role = <CANVAS_ROLE>
- Ask the user for the canvas username and password
- Do NOT skip this step (canvas role + canvas user) even for demos

## Prerequisites

Before using any integration, verify both CLI tools and connections are working.

**nipyapi** (pre-installed at `<SKILL_DIR>/venv`):
```bash
<SKILL_DIR>/venv/bin/nipyapi --help
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
If nipyapi is missing: `pip install nipyapi[cli]` in `<SKILL_DIR>/venv`

**Hooks:** See `powers/steering/hooks.md` for an `aws-profile-guard` hook that blocks any `aws` command
missing `--profile`, preventing accidental operations against the wrong AWS account.
Includes installation instructions for both Kiro and Claude Code.

## Sub-folders

Each integration lives in its own sub-folder with a guide and relevant artifacts.

| Folder | Integration | AWS Services | Snowflake Features |
|--------|-------------|--------------|-------------------|
| `kinesis-openflow/` | Kinesis → Openflow → Snowflake streaming ingestion | Kinesis, DynamoDB, CloudWatch | Openflow SPCS, Snowpipe Streaming |

See also: `openflow-setup.md` — shared prerequisite covering Openflow runtime discovery, nipyapi profile creation, and canvas UI user setup. Read this before starting any integration if Openflow isn't already configured.

## Conventions

- Each sub-folder contains its own `guide.md` with architecture and parameter reference
- Detailed setup steps, verification, costs, and troubleshooting live in `references/` within each sub-folder
- Each sub-folder has a `params.yaml` capturing all configurable values
- Shared prerequisites live at the project root as `.md` files (e.g., `openflow-setup.md`)
- All `snow` commands use the system CLI (`snow`)
- All `nipyapi` commands use `<SKILL_DIR>/venv/bin/nipyapi`
- Include cost estimates where applicable
- Include cleanup instructions in every integration

## Stopping Points

- Step 1: After presenting integrations — wait for user selection
- Step 2: After showing architecture — wait for user to confirm proceed
- Step 3: After prereq summary — wait for "Does this look correct?"
- Step 4: Before each resource creation — confirm if existing resource found
- Step 5: After verification — present final summary

## Output

- Running Kinesis → Openflow → Snowflake streaming pipeline
- Configured nipyapi profile for Openflow runtime
- Canvas user with UI access to Openflow
- params.yaml populated with all resolved values
- Verification summary with row counts and pipeline health

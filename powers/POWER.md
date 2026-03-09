---
name: "kiro-coco"
displayName: "Kiro-CoCo: AWS + Snowflake Integrations"
description: "AWS + Snowflake integrated solutions combining Kinesis, Lambda, DynamoDB, and EventBridge with Snowflake Openflow and Snowpipe Streaming. Use when setting up streaming pipelines from AWS to Snowflake, deploying Kinesis connectors, configuring Openflow on SPCS, or setting up an Openflow canvas user."
keywords: ["aws", "snowflake", "kinesis", "openflow", "streaming", "pipeline", "ingestion"]
author: "James Sun"
---

# Kiro-CoCo: AWS + Snowflake Integrated Solutions

Integrated solutions combining AWS services with Snowflake, built collaboratively between Kiro (AWS) and CoCo (Snowflake).

<!-- AI INSTRUCTIONS
On power activation, follow this workflow:

POWER_DIR is the directory containing this POWER.md file.

STEP 1: Show available integrations FIRST
- Read the Integrations table below and present the available integrations to the user
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
   - If fails, ask user which Snowflake connection to use (list with `snow connection list`)
   - If succeeds, show account/user/role and ask user to confirm
5. Check Openflow environment (Snowflake-managed runtime required):
   a. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW DATA PLANE INTEGRATIONS" --format json`
      - Must return at least one integration with enabled=true
      - If empty: STOP — tell user:
        "This power requires a Snowflake-managed Openflow deployment.
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
   b. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW RUNTIME INTEGRATIONS" --format json`
      - Must return at least one with enabled=true and snowflakecomputing.app in oauth_redirect_uri
      - If only BYOC runtimes: STOP — tell user to add a Snowflake-managed runtime via Control Plane UI
        See https://docs.snowflake.com and search 'Openflow SPCS runtime'
   c. Run: `snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT" --format json`
      - At least one service must have status=RUNNING
      - If all suspended: tell user to resume the Openflow runtime first via the Control Plane UI
   d. Run: `~/kiro-coco-venv/bin/nipyapi profiles list_profiles`
      - Must return at least one profile
      - Ask user which profile targets the Snowflake-managed runtime
      - Confirm: `~/kiro-coco-venv/bin/nipyapi --profile <profile> config nifi_config`
        host must match snowflakecomputing.app URL from the runtime integration
      - If no profile: use steering/openflow-setup.md Section 3 to create one
6. Show summary of all connections and ask "Does this look correct?" before proceeding

STEP 4: Execute the integration setup following the steering file instructions

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
- Discover SPCS services: SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
- Grant endpoint access on both SPCS services (runtime + data plane)
- Grant USAGE/OPERATE on both integrations
- Create <CANVAS_USER> with default role = <CANVAS_ROLE> and MUST_CHANGE_PASSWORD = FALSE
- Ask the user for the canvas username and password
- Canvas URL: https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/<RUNTIME_KEY>/nifi/
  If OAuth blocks login, append ?role=<CANVAS_ROLE> to the URL
- Privileged roles (ACCOUNTADMIN, SECURITYADMIN, ORGADMIN) are blocked by Snowflake OAuth —
  the canvas user's default role must always be a non-privileged role

IMPORTANT: For all snow/nipyapi commands in sub-powers, use:
  snow  (system CLI)
  ~/kiro-coco-venv/bin/nipyapi

NOTE: Integration content lives in POWER_DIR/steering/. Read files from there when following integration instructions.
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

**Recommended Hooks:**
See `steering/hooks.md` for an `aws-profile-guard` hook that blocks any `aws` command
missing `--profile`, preventing accidental operations against the wrong AWS account.
Includes installation instructions for both Kiro and Claude Code.

## Integrations

| Integration | Guide | AWS Services | Snowflake Features |
|-------------|-------|--------------|-------------------|
| Kinesis → Openflow → Snowflake streaming ingestion | `steering/kinesis-openflow.md` | Kinesis, DynamoDB, CloudWatch | Openflow SPCS, Snowpipe Streaming |

See also: `steering/openflow-setup.md` — shared prerequisite covering Openflow runtime discovery, nipyapi profile creation, and canvas UI user setup. Read this before starting any integration if Openflow isn't already configured.

## Available Steering Files

- **kinesis-openflow** - Full setup guide for Kinesis → Openflow → Snowflake streaming ingestion: architecture, step-by-step deployment, parameter reference, and teardown
- **kinesis-openflow-params** - Configurable parameters for the Kinesis-Openflow integration
- **openflow-setup** - Shared prerequisite: Openflow runtime discovery, nipyapi profile creation, and canvas UI user setup
- **connector-auth** - Openflow connector authentication architecture: how the base role works, OAuth identity flow, why the base role must be used for Snowpipe Streaming writes
- **hooks** - Recommended safety hooks: aws-profile-guard blocks AWS commands missing --profile, with install instructions for Kiro and Claude Code

## Conventions

- Integration content (guides, params) lives in `steering/` relative to this file
- Shared prerequisites live at `steering/openflow-setup.md`
- All `snow` and `nipyapi` commands use system `snow` and `~/kiro-coco-venv/bin/nipyapi`
- Include cost estimates where applicable
- Include cleanup instructions in every integration

## License & Attribution

**License:** MIT

**Power Author:** James Sun

**Original Work:** This power is derived from the [kiro-coco](https://github.com/sfc-gh-jsun/claude-skills) Claude Code skill.

**Source Version:** Based on v1.0.4.

**Update Frequency:** This power is updated as new AWS-Snowflake integrations are added or existing ones are revised.

---
name: "kiro-coco"
displayName: "Kiro-CoCo: AWS + Snowflake Integrations"
description: "AWS + Snowflake integrated solutions. Use for: Kinesis to Snowflake, Openflow connector setup, Snowpipe Streaming from AWS, deploy Kinesis connector, configure Openflow on SPCS, canvas user setup, streaming ingestion, real-time AWS to Snowflake pipeline."
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

STEP 2: After user selects an integration, load the overview
- Read `steering/kinesis-openflow.md` to understand the architecture, parameters, and components
- Display the architecture, workflow, and what will be set up
- Give the user visibility into what we're going to do
- Ask if they want to proceed
- IMPORTANT: Do NOT begin deployment until you have read and understood the overview.

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
Load `steering/kinesis-openflow-setup-steps.md` and follow the steps.
Load additional steering files on-demand as each phase is reached:
- `steering/kinesis-openflow-verification.md` for verification
- `steering/kinesis-openflow-cost-estimation.md` for cost analysis
- `steering/kinesis-openflow-troubleshooting.md` for troubleshooting and cleanup

STEP 4b: Create canvas UI user (MANDATORY — DO NOT SKIP)

After deploying and configuring the connector, always create a canvas user for UI access.
This step is NOT optional — it must be executed for every deployment.

1. Check if a canvas role already exists:
   `SHOW ROLES LIKE '%CANVAS%';`
   If a suitable role exists with the correct grants, ask the user whether to reuse it or create a new one.

2. Discover SPCS service names:
   `SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;`
   Note the runtime service and data plane service names.

3. Create the canvas role and grants:
   ```sql
   USE ROLE ACCOUNTADMIN;
   CREATE ROLE IF NOT EXISTS <CANVAS_ROLE>;
   GRANT ROLE <CANVAS_ROLE> TO ROLE ACCOUNTADMIN;

   -- Canvas UI endpoint access (both SPCS services)
   GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_RUNTIME_SERVICE>!ALL_ENDPOINTS_USAGE
     TO ROLE <CANVAS_ROLE>;
   GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_DATAPLANE_SERVICE>!ALL_ENDPOINTS_USAGE
     TO ROLE <CANVAS_ROLE>;

   -- Integration access
   GRANT USAGE   ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
   GRANT OPERATE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
   GRANT USAGE   ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <CANVAS_ROLE>;
   ```

4. Create the canvas user:
   ```sql
   CREATE USER IF NOT EXISTS <CANVAS_USER>
     PASSWORD          = '<PASSWORD>'
     DEFAULT_ROLE      = <CANVAS_ROLE>
     MUST_CHANGE_PASSWORD = FALSE;
   GRANT ROLE <CANVAS_ROLE> TO USER <CANVAS_USER>;
   ```

5. Show the canvas URL:
   `https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/<RUNTIME_KEY>/nifi/`
   If OAuth blocks the login, append `?role=<CANVAS_ROLE>` to the URL.

Do NOT proceed to Step 5 until the canvas role and user are confirmed to exist.
See steering/openflow-setup.md Section 5 for the full reference.

STEP 5: Verify and report
- **Pre-check:** Confirm canvas role and user exist before reporting success.
  Run: `SHOW ROLES LIKE '%CANVAS%';` and `SHOW USERS LIKE '<CANVAS_USER>';`
  If either is missing, go back to Step 4b.
- Run verification checks from `steering/kinesis-openflow-verification.md`
- Show row counts, connector status, KCL checkpoint health
- Present summary: "Pipeline running. X rows ingested. Canvas user ready at <URL>."

IMPORTANT: Before creating any Snowflake resource, first check if it already exists.
Similarly, before creating any AWS resource, first check if it already exists.
If a resource exists, ask the user whether to use it or create a new one.

IMPORTANT: For the Openflow role identification step:

**Two-role pattern:**
- BASE ROLE = the pre-existing customer role that owns the Openflow data plane integration.
  Discovered automatically — the user never needs to know its name.
- CANVAS ROLE = a new dedicated role created for human canvas UI access only.

**How to discover the base role (do this silently):**
1. SHOW OPENFLOW DATA PLANE INTEGRATIONS; then SHOW GRANTS ON INTEGRATION <name>;
   Find OWNERSHIP → this is <BASE_ROLE>.
2. Grant data privileges directly to <BASE_ROLE>.
3. Use <BASE_ROLE> as "Snowflake Role" in connector parameters.

See steering/connector-auth.md for the full architecture explanation.

IMPORTANT: Always create a canvas user — this is REQUIRED, not optional.
See steering/openflow-setup.md Section 5 for the full canvas user creation workflow.

IMPORTANT: For all snow/nipyapi commands in sub-powers, use:
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

**Recommended Hooks:**
See `steering/hooks.md` for an `aws-profile-guard` hook that blocks any `aws` command
missing `--profile`, preventing accidental operations against the wrong AWS account.
Includes installation instructions for both Kiro and Claude Code.

## Integrations

| Integration | Guide | AWS Services | Snowflake Features |
|-------------|-------|--------------|-------------------|
| Kinesis → Openflow → Snowflake streaming ingestion | `steering/kinesis-openflow.md` | Kinesis, DynamoDB, CloudWatch | Openflow SPCS, Snowpipe Streaming |

See also: `steering/openflow-setup.md` — shared prerequisite covering Openflow runtime discovery, nipyapi profile creation, and canvas UI user setup.

## Available Steering Files

- **kinesis-openflow.md** - Overview: architecture, parameters, components, getting started
- **kinesis-openflow-setup-steps.md** - Steps 0a-6: stream, producer, role, table, EAI, connector
- **kinesis-openflow-verification.md** - Confirm data flowing end-to-end
- **kinesis-openflow-cost-estimation.md** - Measure actual costs, pricing reference, alerts
- **kinesis-openflow-troubleshooting.md** - Common issues + complete cleanup
- **kinesis-openflow-workflow-diagram.md** - ASCII art end-to-end flow
- **kinesis-openflow-params.yaml** - Configurable parameters
- **openflow-setup.md** - Shared prerequisite: runtime discovery, nipyapi profile, canvas user
- **connector-auth.md** - Authentication architecture: base role, OAuth, Snowpipe Streaming
- **hooks.md** - AWS profile guard hook for safety

## Conventions

- Integration overview lives in `steering/kinesis-openflow.md`
- Detailed content (setup, verification, costs, troubleshooting) lives in `steering/kinesis-openflow-*.md`
- Shared prerequisites live at `steering/openflow-setup.md`
- All `snow` and `nipyapi` commands use system `snow` and `~/kiro-coco-venv/bin/nipyapi`
- Include cost estimates where applicable
- Include cleanup instructions in every integration

## Stopping Points

- Step 1: After presenting integrations — wait for user selection
- Step 2: After showing architecture — wait for user to confirm proceed
- Step 3: After prereq summary — wait for "Does this look correct?"
- Step 4: Before each resource creation — confirm if existing resource found
- Step 4b: After canvas user creation — confirm user can log into canvas UI
- Step 5: After verification — present final summary

## Output

- Running Kinesis → Openflow → Snowflake streaming pipeline
- Configured nipyapi profile for Openflow runtime
- Canvas user with UI access to Openflow
- Verification summary with row counts and pipeline health

## License & Attribution

**License:** MIT

**Power Author:** James Sun

**Original Work:** This power is derived from the [kiro-coco](https://github.com/sfc-gh-jsun/claude-skills) Claude Code skill.

**Source Version:** Based on v1.0.5.

**Update Frequency:** This power is updated as new AWS-Snowflake integrations are added or existing ones are revised.

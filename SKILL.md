# Kiro-CoCo: AWS + Snowflake Integrated Solutions

Integrated solutions combining AWS services with Snowflake, built collaboratively between Kiro (AWS) and CoCo (Snowflake).

<!-- AI INSTRUCTIONS
On skill load, run the prerequisite checks below BEFORE doing anything else.

SKILL_DIR is the directory containing this SKILL.md file.

1. Check Python venv: if SKILL_DIR/venv/ does not exist, create it and install dependencies:
   python3 -m venv SKILL_DIR/venv
   SKILL_DIR/venv/bin/pip install snowflake-cli nipyapi[cli]
   If venv exists, verify: SKILL_DIR/venv/bin/snow --version && SKILL_DIR/venv/bin/nipyapi --help
2. Check AWS CLI: `aws --version` — if missing, help install via `brew install awscli` or guide user
3. Check AWS profile: `aws sts get-caller-identity` — try default profile first
   - If fails, ask user for their AWS profile name
   - If succeeds, show account ID and ask user to confirm
4. Check Snowflake connection: use snowflake_sql_execute to run SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE()
   - If fails, ask user which Snowflake connection to use
   - If succeeds, show account/user/role and ask user to confirm
5. Show summary of both connections and ask "Does this look correct?" before proceeding
6. After user confirms, list available integrations from the Sub-folders table below and ask
   the user which one they'd like to work with. Use AskUserQuestion with options built from
   the table (e.g., "Kinesis + Openflow streaming ingestion"). Then load the selected
   sub-folder's README.md and follow its instructions.

IMPORTANT: For all snow/nipyapi commands in sub-skills, use the venv binaries:
  SKILL_DIR/venv/bin/snow
  SKILL_DIR/venv/bin/nipyapi
-->

## Prerequisites

Before using any integration, verify both CLI tools and connections are working.

**Python venv** (created in this skill's directory):
```bash
# From the skill directory (where SKILL.md lives)
python3 -m venv venv
venv/bin/pip install snowflake-cli nipyapi[cli]
```

**AWS CLI:**
```bash
aws --version
aws sts get-caller-identity --profile <AWS_PROFILE>
```

**Snowflake CLI:**
```bash
venv/bin/snow --version
venv/bin/snow connection test -c <SNOWFLAKE_CONNECTION>
```

If AWS CLI is missing: `brew install awscli` then `aws configure --profile <name>`

## Sub-folders

Each integration lives in its own sub-folder with a README and relevant artifacts.

| Folder | Integration | AWS Services | Snowflake Features |
|--------|-------------|--------------|-------------------|
| `kinesis-openflow/` | Kinesis → Openflow → Snowflake streaming ingestion | Kinesis, DynamoDB, CloudWatch | Openflow SPCS, Snowpipe Streaming |

## Conventions

- Each sub-folder contains its own `README.md` with architecture, setup, and teardown steps
- Each sub-folder has a `params.yaml` capturing all configurable values
- Shared prerequisites (e.g., Openflow setup) live at the project root as `.md` files
- CloudFormation/CDK templates go in the sub-folder
- SQL scripts for Snowflake setup go in the sub-folder
- All `snow` and `nipyapi` commands use the venv binaries (`venv/bin/snow`, `venv/bin/nipyapi`)
- The `venv/` directory is local-only and should be gitignored
- Include cost estimates where applicable
- Include cleanup instructions in every integration

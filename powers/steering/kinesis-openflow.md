<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Kinesis + Openflow: Streaming Ingestion to Snowflake

Copyright 2026 James Sun, Snowflake, Inc. All rights reserved.

Consume data from an existing Amazon Kinesis Data Stream via Snowflake Openflow Kinesis Connector and ingest into Snowflake using Snowpipe Streaming. Includes DynamoDB for KCL checkpoint management.

This integration assumes data is **already flowing into Kinesis** from any upstream source (Lambda, SDK, Kinesis Agent, etc.). It covers only the consumption and ingestion side.

## Section Index

| Section | File | Description |
|---------|------|-------------|
| Setup Steps | `references/setup-steps.md` | Steps 0a-6: stream creation, producer, role setup, table, EAI, connector deploy/config/start |
| Verification | `references/verification.md` | Confirm data flowing end-to-end |
| Cost Estimation | `references/cost-estimation.md` | Measure actual costs, pricing reference, alerts |
| Troubleshooting | `references/troubleshooting.md` | Common issues + complete cleanup |
| Workflow Diagram | `references/workflow-diagram.md` | ASCII art end-to-end flow |

**Load references on-demand** as each phase is reached — do not read all at once.

---

## Parameters

Fill in these values before running any setup steps. All `<PLACEHOLDER>` tokens in the docs reference this table.

| Parameter | Description | Example |
|-----------|-------------|---------|
| `<AWS_REGION>` | AWS region for Kinesis, DynamoDB, CloudWatch | `us-west-2` |
| `<AWS_PROFILE>` | AWS CLI profile name | `my-profile` |
| `<AWS_ACCESS_KEY>` | AWS access key ID for Openflow | *(from IAM)* |
| `<AWS_SECRET_KEY>` | AWS secret access key for Openflow | *(from IAM)* |
| `<STREAM_NAME>` | Kinesis Data Stream name | `my-events-stream` |
| `<APP_NAME>` | KCL application name (becomes DynamoDB table) | `my-kinesis-consumer` |
| `<CONNECTOR_FLOW>` | Flow name in registry (`kinesis-json-modularized` default, `kinesis` legacy) | `kinesis-json-modularized` |
| `<DB_NAME>` | Snowflake destination database | `KINESIS_DB` |
| `<TABLE_NAME>` | Snowflake destination table (legacy only) | `RAW_EVENTS` |
| `<AUTO_TABLE_NAME>` | Auto-created table name (modularized — named after stream) | `"MY-EVENTS-STREAM"` |
| `<WAREHOUSE>` | Snowflake warehouse for Openflow | `OPENFLOW_WH` |
| `<SNOWFLAKE_CONNECTION>` | Snowflake CLI connection name (`snow connection list`) | `my_connection` |
| `<OPENFLOW_ROLE>` | Snowflake role identified in Step 1 (owns Openflow deployment) | `KINESIS_OPENFLOW_RL` |
| `<OPENFLOW_DATAPLANE_INTEGRATION>` | Data plane integration name | `OPENFLOW_DATAPLANE_...` |
| `<OPENFLOW_RUNTIME_INTEGRATION>` | Runtime integration name | `OPENFLOW_RUNTIME_...` |
| `<OPENFLOW_RUNTIME_SERVICE>` | SPCS service name for the runtime | `DB.SCHEMA.OPENFLOW_RDS` |
| `<OPENFLOW_DATAPLANE_SERVICE>` | SPCS service name for the data plane | `DB.SCHEMA.OPENFLOW_MSK` |
| `<CANVAS_ROLE>` | Dedicated role for humans to log into the Openflow canvas UI | `KINESIS_CANVAS_RL` |
| `<CANVAS_USER>` | Snowflake user who will log into the canvas UI | `kinesis_openflow_user` |
| `<OPENFLOW_PROFILE>` | nipyapi profile for Openflow runtime | `my_openflow` |
| `<PG_ID>` | Openflow process group ID (after deploy) | *(from deploy output)* |
| `<SOURCE_PG_ID>` | Kinesis JSON Source sub-PG ID (modularized) | *(from Step 5a)* |
| `<SOURCE_PARAM_CONTEXT_ID>` | Source parameter context ID (modularized) | *(from Step 5a)* |
| `<DEST_PG_ID>` | Streaming Destination sub-PG ID (modularized) | *(from Step 5a)* |

## Components

| Component | Service | Purpose |
|-----------|---------|---------|
| Kinesis Data Stream | AWS Kinesis | Source stream (ON_DEMAND mode) |
| DynamoDB Table | AWS DynamoDB | KCL lease coordination and checkpoint storage |
| CloudWatch | AWS CloudWatch | KCL consumer metrics |
| External Access Integration | Snowflake | Network egress rules for SPCS to reach AWS |
| Openflow Kinesis Connector | Snowflake SPCS | NiFi-based connector runtime (Snowflake-managed only, not BYOC) |
| ConsumeKinesisStream | Openflow Processor | KCL-based Kinesis consumer |
| PutSnowpipeStreaming | Openflow Processor | Batch insert via Snowpipe Streaming API |
| Target Table | Snowflake | Destination (standard or Iceberg) |

## Connector Versions

The **modularized connector** (`kinesis-json-modularized`) is the current default. The legacy `kinesis` flow is deprecated and absent from newer runtimes. Always use `kinesis-json-modularized` unless the runtime registry only has `kinesis`.

### Comparison Table

| Aspect | `kinesis-json-modularized` (Default) | `kinesis` (Legacy) |
|--------|---------------------------------------|-------------------|
| **Availability** | All runtimes (current and new) | Older runtimes only (deprecated from newer registries) |
| **Architecture** | 3 nested sub-PGs, each with own parameter context | Single PG with one inherited parameter context |
| **Sub-PGs** | Kinesis JSON Source, Streaming Destination, Custom Transformations | None |
| **Deploy command** | `--flow kinesis-json-modularized` | `--flow kinesis` |
| **Configure params** | Must configure each sub-PG separately | Single `configure_inherited_params` call |
| **Sensitive params** (AWS keys) | **Must use NiFi REST API directly** — nipyapi causes 409 Conflict | Work via `configure_inherited_params` |
| **Consumer type** | Explicit: `SHARED_THROUGHPUT` or `ENHANCED_FAN_OUT` | Not exposed (defaults internally) |
| **Table naming** | Schema evolution auto-creates table named after stream | `Kinesis Stream To Table Map` param (explicit mapping) |
| **Table name format** | Stream name uppercased (e.g., `"OPENSKY-REGRESSION-STREAM"`) | User-defined (e.g., `FLIGHT_DATA`) |
| **DB grants needed** | CREATE TABLE + ALL on future tables (schema evolution) | Standard INSERT on pre-created table |
| **Auth strategy** | `SNOWFLAKE_MANAGED` (SPCS) | `SNOWFLAKE_MANAGED` (SPCS) — same |
| **Initial position** | Explicit: `TRIM_HORIZON` or `LATEST` | Not exposed |

### Key Pitfalls When Switching Versions

1. **Do NOT use `configure_inherited_params` for sensitive params on modularized connector.** nipyapi will attempt to change the parameter from sensitive to non-sensitive, causing a 409 Conflict. Use the NiFi REST API directly with `"sensitive": true`.

2. **Do NOT set consumer type to `POLLING`.** The valid values are `SHARED_THROUGHPUT` and `ENHANCED_FAN_OUT`. `POLLING` causes an INVALID processor state.

3. **Do NOT expect data in a pre-created table.** The modularized connector uses schema evolution and auto-creates a table named after the Kinesis stream. Check `SHOW TABLES` to find it.

4. **Do NOT forget CREATE TABLE grants.** The Openflow role needs `CREATE TABLE ON SCHEMA` plus `ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA` for schema evolution to work.

5. **ENHANCED_FAN_OUT has a 10-minute initialization delay** on first run. The consumer processor will show "Kinesis Scheduler initialization may take up to 10 minutes" and appear stuck. Use `SHARED_THROUGHPUT` for regression/testing.

6. **Do NOT hardcode revision version 0 in the REST API call.** After `configure_inherited_params` modifies the parameter context (Step 5b), the revision increments. Always fetch the current version with `GET /parameter-contexts/{id}` before submitting the sensitive param update, or you'll get HTTP 400 "is not the most up-to-date revision."

7. **Use file-based JSON for sensitive params with special characters.** If your AWS secret key contains `/`, `+`, or other shell-special characters, inline JSON in curl will break. Write JSON to a temp file with heredoc (`<< 'JSONEOF'`) and use `curl -d @/tmp/file.json`.

### Modularized Connector Parameters

Parameters are split across sub-PGs:

**Kinesis JSON Source** (non-sensitive via `configure_inherited_params`, sensitive via REST API):
| Parameter | Example | Notes |
|-----------|---------|-------|
| `AWS Region Code` | `us-west-2` | Non-sensitive |
| `Kinesis Stream Name` | `opensky-regression-stream` | Non-sensitive |
| `Kinesis Application Name` | `opensky-regression-consumer` | Non-sensitive |
| `Kinesis Consumer Type` | `SHARED_THROUGHPUT` | Non-sensitive. Valid: `SHARED_THROUGHPUT`, `ENHANCED_FAN_OUT` |
| `Kinesis Initial Stream Position` | `TRIM_HORIZON` | Non-sensitive |
| `AWS Access Key ID` | *(from IAM)* | **SENSITIVE** — must use NiFi REST API |
| `AWS Secret Access Key` | *(from IAM)* | **SENSITIVE** — must use NiFi REST API |

**Streaming Destination** (all non-sensitive, via `configure_inherited_params`):
| Parameter | Example | Notes |
|-----------|---------|-------|
| `Destination Database` | `KINESIS_REGRESSION_DB` | |
| `Destination Schema` | `PUBLIC` | |
| `Snowflake Role` | `ADF_PL_RL` | |
| `Snowflake Authentication Strategy` | `SNOWFLAKE_MANAGED` | Default — do not change for SPCS |

**Custom Transformations**: Usually no configuration needed.

## Getting Started

### Option A: Test with Sample Data (Recommended for First-Time Setup)

If you don't have a data source yet or want to validate the pipeline architecture first, use this sample flight data endpoint:

**Sample Source:** `http://ecs-alb-1504531980.us-west-2.elb.amazonaws.com:8502/opensky`

This OpenSky ECS endpoint provides real-time flight data in JSON format - perfect for testing the Kinesis → Openflow → Snowflake pipeline.

**Workflow:**
1. Create Kinesis stream (Step 0a)
2. Run local producer with OpenSky endpoint (Step 0b)
3. **Examine the data records** — inspect JSON structure from Kinesis
4. **Identify Openflow role** — discover the role that owns the deployment (Step 1)
5. **Design table schema** based on observed data fields (Step 2)
6. Configure Openflow (Steps 3-6)
7. Verify data flows end-to-end

**After successful test**, apply the same workflow to your production data source.

### Option B: Production Setup (Your Data Source)

**Workflow:**

1. **Start with local producer** (easier debugging):
   - Create production Kinesis stream (Step 0a)
   - Run local Python producer for your data source (adapt Step 0b template)
   - **Examine the data records** — inspect JSON structure from Kinesis
   - **Identify Openflow role** — discover the role that owns the deployment (Step 1)
   - **Design table schema** based on observed data fields (Step 2)
   - Configure Openflow connector (Steps 3-6)
   - Verify data flows end-to-end

2. **Migrate to Lambda + EventBridge** (optional, after verification):
   - Package producer logic as Lambda function
   - Set up EventBridge rule to trigger Lambda on schedule or event
   - Monitor CloudWatch logs for Lambda execution
   - Decommission local producer

**Benefits of local-first approach:**
- Faster iteration cycle during development
- Easier to debug with direct console output
- See actual data before designing schema
- No Lambda packaging/deployment until proven

**If you already have data flowing into Kinesis**, skip to Step 1 (role identification) and Step 2 (table creation) — examine existing records to design your schema.

---

## Prerequisites

### 1. Snowflake-managed Openflow (SPCS) deployment

A Snowflake-managed Openflow deployment with at least one **RUNNING** runtime is required.
Run these checks before proceeding — if any fail, set up Openflow first (see `../openflow-setup.md`).

**Check 1: Data plane integration exists**
```sql
SHOW OPENFLOW DATA PLANE INTEGRATIONS;
-- Must return at least one row with enabled = true
```

**Check 2: Runtime integration exists**
```sql
SHOW OPENFLOW RUNTIME INTEGRATIONS;
-- Must return at least one row with enabled = true
-- Note the oauth_redirect_uri — it must contain snowflakecomputing.app (Snowflake-managed)
-- NOT a BYOC deployment (byoc in the URL)
```

**Check 3: Runtime SPCS service is RUNNING**
```sql
SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
-- At least one service must have status = RUNNING
```

**Check 4: nipyapi profile exists for the Snowflake-managed runtime**
```bash
~/kiro-coco-venv/bin/nipyapi profiles list_profiles
# Must return at least one profile
# Confirm it points to the correct runtime:
~/kiro-coco-venv/bin/nipyapi --profile <profile> config nifi_config
# host should match the snowflakecomputing.app/... URL from the runtime integration above
```

If all four checks pass, you have a working environment. Proceed to `references/setup-steps.md`.

If no Openflow deployment exists, deploy one via the **Snowflake Control Plane UI** first, then return here.
This skill does not cover Openflow installation — it assumes a running deployment as a prerequisite.

> **Docs:** Search "Openflow" at [docs.snowflake.com](https://docs.snowflake.com) for the
> latest setup guide. Look for **"Set up Snowflake Openflow"** or
> **"Openflow SPCS runtime"** to find the deployment instructions.

### 2. AWS credentials and Kinesis stream

- Kinesis Data Stream exists and has data flowing (or will create one for testing)
- AWS credentials (Access Key + Secret Key) with permissions for Kinesis, DynamoDB, CloudWatch

### 3. Snowflake permissions

- Snowflake role with USAGE on warehouse and database/schema
- CREATE TABLE ON SCHEMA + ALL PRIVILEGES ON FUTURE TABLES (modularized connector uses schema evolution)
- For legacy connector only: INSERT on pre-created target table

## Estimated Costs (Before Setup)

**Typical monthly costs for low-volume workloads:**

| Service | Configuration | Monthly Cost |
|---------|---------------|-------------|
| Kinesis (ON_DEMAND) | Pay per throughput | ~$0.80 (low volume) |
| DynamoDB (On-Demand) | KCL checkpoint table | ~$0.00 (free tier) |
| CloudWatch | KCL metrics | ~$0.00 (minimal) |
| Openflow SPCS | Snowflake compute | Varies by runtime size |
| **Total (AWS side)** | | **~$1/month** (low volume) |

**For detailed cost estimation based on your actual throughput**, see `references/cost-estimation.md` after your pipeline is running.

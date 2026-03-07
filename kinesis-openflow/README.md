# Kinesis + Openflow: Streaming Ingestion to Snowflake

---

**Copyright © 2026 James Sun, Snowflake, Inc.**
**Created:** March 5, 2026
**Author:** James Sun (james.sun@snowflake.com)

All rights reserved. This document is provided for informational and educational purposes.

---


Consume data from an existing Amazon Kinesis Data Stream via Snowflake Openflow Kinesis Connector and ingest into Snowflake using Snowpipe Streaming. Includes DynamoDB for KCL checkpoint management.

This integration assumes data is **already flowing into Kinesis** from any upstream source (Lambda, SDK, Kinesis Agent, etc.). It covers only the consumption and ingestion side.


## Quick Preview

**New to this workflow?** See the [Complete Flow Diagram](#complete-workflow-diagram) at the end of this document for a visual overview of all steps from setup to cleanup.

**Key sections:**
- [Getting Started](#getting-started) - Choose Option A (test) or Option B (production)
- [Setup](#setup) - Step-by-step configuration (Steps 0a, 0b, 1-6)
- [Verification](#verification) - Confirm data is flowing
- [Cost Estimation](#cost-estimation-optional) - Measure actual costs after pipeline runs
- [Cleanup](#cleanup) - Delete all resources when done

---

## Parameters

Fill in these values before running any setup steps. All `<PLACEHOLDER>` tokens in the doc reference this table.

| Parameter | Description | Example |
|-----------|-------------|---------|
| `<AWS_REGION>` | AWS region for Kinesis, DynamoDB, CloudWatch | `us-west-2` |
| `<AWS_PROFILE>` | AWS CLI profile name | `my-profile` |
| `<AWS_ACCESS_KEY>` | AWS access key ID for Openflow | *(from IAM)* |
| `<AWS_SECRET_KEY>` | AWS secret access key for Openflow | *(from IAM)* |
| `<STREAM_NAME>` | Kinesis Data Stream name | `my-events-stream` |
| `<APP_NAME>` | KCL application name (becomes DynamoDB table) | `my-kinesis-consumer` |
| `<DB_NAME>` | Snowflake destination database | `KINESIS_DB` |
| `<TABLE_NAME>` | Snowflake destination table | `RAW_EVENTS` |
| `<WAREHOUSE>` | Snowflake warehouse for Openflow | `OPENFLOW_WH` |
| `<OPENFLOW_ROLE>` | Snowflake role identified in Step 1 (owns Openflow deployment, granted to runtime service users) | `KINESIS_OPENFLOW_RL` |
| `<CANVAS_ROLE>` | Dedicated role for humans to log into the Openflow canvas UI | `KINESIS_CANVAS_RL` |
| `<CANVAS_USER>` | Snowflake user who will log into the canvas UI | `kinesis_openflow_user` |
| `<OPENFLOW_PROFILE>` | nipyapi profile for Openflow runtime | `my_openflow` |
| `<PG_ID>` | Openflow process group ID (after deploy) | *(from deploy output)* |

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

## Getting Started

### Option A: Test with Sample Data (Recommended for First-Time Setup)

If you don't have a data source yet or want to validate the pipeline architecture first, use this sample flight data endpoint:

**Sample Source:** `http://ecs-alb-1504531980.us-west-2.elb.amazonaws.com:8502/opensky`

This OpenSky ECS endpoint provides real-time flight data in JSON format - perfect for testing the Kinesis → Openflow → Snowflake pipeline.

**Workflow (same as Option B):**
1. Create Kinesis stream (Step 0a)
2. Run local producer with OpenSky endpoint (Step 0b)
3. **Examine the data records** - inspect JSON structure from Kinesis
 4. **Identify Openflow role** — discover the role that owns the deployment (Step 1)
5. **Design table schema** based on observed data fields (Step 2)
6. Configure Openflow (Steps 3-6)
7. Verify data flows end-to-end

**After successful test**, apply the same workflow to your production data source.

### Option B: Production Setup (Your Data Source)

**Workflow (same as Option A):**

1. **Start with local producer** (easier debugging):
   - Create production Kinesis stream (Step 0a)
   - Run local Python producer for your data source (adapt Step 0b template)
   - **Examine the data records** - inspect JSON structure from Kinesis
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

An Openflow deployment running on SPCS with at least one active runtime is required before proceeding.

- **Running runtime(s)**: Verify via the Openflow UI that at least one runtime is in a running state
- **Service role grant**: Your Snowflake role must be granted the Openflow service's service role to access the UI (Snowflake managed token handles authentication automatically, but the service role grant is the authorization gate). This same role is needed later when deploying the flow.

**Verify your role has access:**

```sql
-- List service roles defined by the Openflow service
SHOW ROLES IN SERVICE <db>.<schema>.<openflow_service>;

-- Check which roles have been granted the service role
SHOW GRANTS OF SERVICE ROLE <db>.<schema>.<openflow_service>!ALL_ENDPOINTS_USAGE;

-- Grant if missing (requires service owner or MANAGE GRANTS)
GRANT SERVICE ROLE <db>.<schema>.<openflow_service>!ALL_ENDPOINTS_USAGE TO ROLE <your_role>;
```

If no Openflow deployment exists, set one up first. This skill does not cover Openflow installation.

### 2. AWS credentials and Kinesis stream

- Kinesis Data Stream exists and has data flowing (or will create one for testing)
- AWS credentials (Access Key + Secret Key) with permissions for Kinesis, DynamoDB, CloudWatch

### 3. Snowflake permissions

- Snowflake role with INSERT on target table and USAGE on warehouse

## Setup

### Step 0a: Create Kinesis Stream

**For testing:** Create a new test stream to validate the pipeline architecture.

**For production:** Create your production stream with appropriate name and capacity.

```bash
# Create ON_DEMAND stream (no shard provisioning needed)
aws kinesis create-stream \
  --stream-name opensky-test-stream \
  --stream-mode-config StreamMode=ON_DEMAND \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE>

# Wait for stream to become ACTIVE
aws kinesis describe-stream \
  --stream-name opensky-test-stream \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> \
  --query 'StreamDescription.StreamStatus'
```

**Expected output:** `"ACTIVE"` (takes ~30 seconds)

### Step 0b: Run Local Producer

**Start with a local producer to validate the pipeline before cloud deployment.**

This example uses OpenSky flight data for testing, but you can adapt the script for any data source (API, database, files, etc.).

**Create producer script:**
```bash
cat > /tmp/opensky_producer.py << 'PRODUCER_EOF'
#!/usr/bin/env python3
"""
OpenSky to Kinesis Producer
Fetches flight data from OpenSky API and streams to Kinesis.
"""
import json
import time
import boto3
import requests
from datetime import datetime

# Configuration
OPENSKY_URL = "http://ecs-alb-1504531980.us-west-2.elb.amazonaws.com:8502/opensky"
STREAM_NAME = "opensky-test-stream"
AWS_REGION = "us-west-2"
AWS_PROFILE = "<AWS_PROFILE>"
POLL_INTERVAL = 10  # seconds

def fetch_opensky_data():
    """Fetch flight data from OpenSky API."""
    try:
        response = requests.get(OPENSKY_URL, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"Error fetching OpenSky data: {e}")
        return None

def send_to_kinesis(kinesis_client, records):
    """Send flight records to Kinesis stream."""
    if not records:
        return 0

    try:
        # Batch records (max 500 per request)
        batch = []
        for record in records[:500]:
            batch.append({
                'Data': json.dumps(record),
                'PartitionKey': record.get('icao', 'unknown')
            })

        response = kinesis_client.put_records(
            StreamName=STREAM_NAME,
            Records=batch
        )

        failed = response.get('FailedRecordCount', 0)
        success = len(batch) - failed
        return success
    except Exception as e:
        print(f"Error sending to Kinesis: {e}")
        return 0

def main():
    """Main producer loop."""
    # Initialize Kinesis client
    session = boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)
    kinesis = session.client('kinesis')

    print(f"Starting OpenSky producer...")
    print(f"Stream: {STREAM_NAME}")
    print(f"Region: {AWS_REGION}")
    print(f"Poll interval: {POLL_INTERVAL}s")
    print("-" * 50)

    record_count = 0

    try:
        while True:
            # Fetch data
            data = fetch_opensky_data()

            if data:
                # Send to Kinesis
                sent = send_to_kinesis(kinesis, data)
                record_count += sent
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Sent {sent} records (total: {record_count})")
            else:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] No data available")

            # Wait before next poll
            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print(f"\nProducer stopped. Total records sent: {record_count}")

if __name__ == "__main__":
    main()
PRODUCER_EOF
```

**Run the producer:**
```bash
# Install dependencies (if needed)
pip install boto3 requests

# Run producer (Ctrl+C to stop)
python3 /tmp/opensky_producer.py
```

**Expected output:**
```
Starting OpenSky producer...
Stream: opensky-test-stream
Region: us-west-2
Poll interval: 10s
--------------------------------------------------
[14:23:45] Sent 247 records (total: 247)
[14:23:55] Sent 251 records (total: 498)
[14:24:05] Sent 245 records (total: 743)
...
```

**Verify data in Kinesis:**
```bash
# Get shard iterator
SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name opensky-test-stream \
  --shard-id shardId-000000000000 \
  --shard-iterator-type LATEST \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> \
  --query 'ShardIterator' \
  --output text)

# Read a few records
aws kinesis get-records \
  --shard-iterator "$SHARD_ITERATOR" \
  --limit 5 \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE>
```

**Once data is flowing, proceed to Step 1 to identify your Openflow role and then Step 2 for the Snowflake table. Use the sample records from Step 0b to design your schema.**

### Step 1: Identify the Openflow Role

The Openflow connector runs under a Snowflake role that must be granted to the runtime's service users. For demos, **reuse the role that already owns the Openflow deployment** — it already has all required grants.

**1a. Find the role that owns the data plane integration:**

```sql
-- List Openflow data plane integrations
SHOW OPENFLOW DATA PLANE INTEGRATIONS;

-- Check who owns it (look for OWNERSHIP grant)
SHOW GRANTS ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION>;
-- The role with OWNERSHIP privilege is your <OPENFLOW_ROLE>
```

**1b. Verify the role is granted to runtime service users:**

```sql
-- Confirm the role is granted to the runtime service users
SHOW GRANTS OF ROLE <OPENFLOW_ROLE>;
-- Look for USER grants to: dpa, integration-secret, runtime-<key>
```

If you see grants to these service users, **this role is ready to use** — skip to 1d.

**1c. (Production only) Create a dedicated role instead:**

For production environments where you want least-privilege isolation, create a new role:

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS <OPENFLOW_ROLE>;
GRANT ROLE <OPENFLOW_ROLE> TO ROLE ACCOUNTADMIN;

-- Grant to runtime service users (REQUIRED for connector to operate)
GRANT ROLE <OPENFLOW_ROLE> TO USER "dpa";
GRANT ROLE <OPENFLOW_ROLE> TO USER "integration-secret";
GRANT ROLE <OPENFLOW_ROLE> TO USER "runtime-<runtime_key>";

-- Grant Openflow integration access
GRANT USAGE ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <OPENFLOW_ROLE>;
GRANT OPERATE ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <OPENFLOW_ROLE>;
GRANT MONITOR ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <OPENFLOW_ROLE>;
GRANT USAGE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION> TO ROLE <OPENFLOW_ROLE>;
```

**1d. Ensure warehouse exists and is granted to the connector role:**

```sql
-- Ensure warehouse exists and is granted
CREATE WAREHOUSE IF NOT EXISTS <WAREHOUSE>
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE <OPENFLOW_ROLE>;
```

**1e. Create a dedicated canvas UI user (for humans who need to log into the NiFi canvas):**

> `<OPENFLOW_ROLE>` is a service role granted to internal runtime users (`dpa`, `integration-secret`, `runtime-*`). Do **not** use it for human canvas logins — create a separate `<CANVAS_ROLE>` instead.
>
> Privileged roles (`ACCOUNTADMIN`, `SECURITYADMIN`, `ORGADMIN`) are blocked by Snowflake's OAuth. The canvas user's default role must be a non-privileged role.

First, discover the SPCS service names:

```sql
SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
```

Note the runtime service and data plane service names, then create the canvas role with all required grants:

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS <CANVAS_ROLE>;

-- Canvas UI endpoint access (runtime service)
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_RUNTIME_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;

-- Data plane endpoint access
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_DATAPLANE_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;

-- Runtime integration access
GRANT USAGE   ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION> TO ROLE <CANVAS_ROLE>;
GRANT OPERATE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION> TO ROLE <CANVAS_ROLE>;

-- Data plane integration access
GRANT USAGE ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <CANVAS_ROLE>;

-- Allow ACCOUNTADMIN to manage this role
GRANT ROLE <CANVAS_ROLE> TO ROLE ACCOUNTADMIN;
```

Create the user:

```sql
CREATE USER IF NOT EXISTS <CANVAS_USER>
  PASSWORD          = '<PASSWORD>'
  DEFAULT_ROLE      = <CANVAS_ROLE>
  MUST_CHANGE_PASSWORD = FALSE;

GRANT ROLE <CANVAS_ROLE> TO USER <CANVAS_USER>;
```

Log in at: `https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/<RUNTIME_KEY>/nifi/`

If OAuth blocks the login, append `?role=<CANVAS_ROLE>` to the URL.

> See `../openflow-setup.md` Section 5 for full reference and discovery steps.

### Step 2: Create Snowflake Target Table

**Before creating the table**, analyze your data structure:
- Use records from Step 0b verification to understand JSON structure
- Or inspect existing Kinesis stream with `aws kinesis get-records`
- Design columns based on your data fields
- Add `INGESTED_AT TIMESTAMP_NTZ` for tracking (no DEFAULT values!)

**Schema requirements** (Snowpipe Streaming limitation):

No DEFAULT values, no AUTOINCREMENT, no GEO columns (Snowpipe Streaming limitation).

**For OpenSky test data:**
```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS <DB_NAME>;
CREATE SCHEMA IF NOT EXISTS <DB_NAME>.PUBLIC;

-- Flight data schema from OpenSky
CREATE TABLE <DB_NAME>.PUBLIC.<TABLE_NAME> (
    ICAO VARCHAR(10),
    ID VARCHAR(20),
    UTC TIMESTAMP_NTZ,
    LAT FLOAT,
    LON FLOAT,
    ALT INTEGER,
    INGESTED_AT TIMESTAMP_NTZ  -- NO DEFAULT!
);

-- Grant to Openflow role
GRANT USAGE ON DATABASE <DB_NAME> TO ROLE <OPENFLOW_ROLE>;
GRANT USAGE ON SCHEMA <DB_NAME>.PUBLIC TO ROLE <OPENFLOW_ROLE>;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE <DB_NAME>.PUBLIC.<TABLE_NAME> TO ROLE <OPENFLOW_ROLE>;
```

**For production data:**
Replace columns with your actual schema from Step 0 analysis.

### Step 3: Create External Access Integration

KCL requires access to Kinesis, DynamoDB, **and** CloudWatch. Missing DynamoDB causes a silent failure (consumer runs but reads zero records).

```sql
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE kinesis_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    -- Kinesis data plane
    'kinesis.<AWS_REGION>.amazonaws.com:443',
    'kinesis.<AWS_REGION>.api.aws:443',
    '*.control-kinesis.<AWS_REGION>.amazonaws.com:443',
    '*.data-kinesis.<AWS_REGION>.amazonaws.com:443',
    '*.control-kinesis.<AWS_REGION>.api.aws:443',
    '*.data-kinesis.<AWS_REGION>.api.aws:443',
    -- DynamoDB (KCL checkpoints — REQUIRED)
    'dynamodb.<AWS_REGION>.amazonaws.com:443',
    -- CloudWatch (KCL metrics)
    'monitoring.<AWS_REGION>.amazonaws.com:443',
    'monitoring.<AWS_REGION>.api.aws:443'
  );

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION kinesis_eai
  ALLOWED_NETWORK_RULES = ('kinesis_network_rule')
  ENABLED = true;

GRANT USAGE ON INTEGRATION kinesis_eai TO ROLE <OPENFLOW_ROLE>;
```

**Manual step**: Attach `kinesis_eai` to the Openflow runtime in the Control Plane UI.

### Step 4: Deploy Kinesis Connector

```bash
# Prerequisite: invoke Openflow skill first
# Deploy connector from registry
~/.snowflake/venv/nipyapi-env/bin/nipyapi --profile <OPENFLOW_PROFILE> ci deploy_flow \
  --registry_client ConnectorFlowRegistryClient \
  --bucket connectors \
  --flow kinesis
```

### Step 5: Configure Connector Parameters

```bash
~/.snowflake/venv/nipyapi-env/bin/nipyapi --profile <OPENFLOW_PROFILE> ci configure_inherited_params \
  --process_group_id "<PG_ID>" \
  --parameters '{
    "AWS Access Key ID": "<AWS_ACCESS_KEY>",
    "AWS Secret Access Key": "<AWS_SECRET_KEY>",
    "AWS Region Code": "<AWS_REGION>",
    "Kinesis Stream Name": "<STREAM_NAME>",
    "Kinesis Application Name": "<APP_NAME>",
    "Kinesis Stream To Table Map": "<STREAM_NAME>:<TABLE_NAME>",
    "Snowflake Warehouse": "<WAREHOUSE>",
    "Destination Database": "<DB_NAME>",
    "Destination Schema": "PUBLIC",
    "Snowflake Role": "<OPENFLOW_ROLE>"
  }'
```

### Step 6: Start Connector

```bash
~/.snowflake/venv/nipyapi-env/bin/nipyapi --profile <OPENFLOW_PROFILE> ci start_flow \
  --process_group_id "<PG_ID>"
```

## Verification

```bash
# Connector status
~/.snowflake/venv/nipyapi-env/bin/nipyapi --profile <OPENFLOW_PROFILE> ci get_status \
  --process_group_id "<PG_ID>"
```

```sql
-- Data in Snowflake
SELECT COUNT(*) FROM <DB_NAME>.PUBLIC.<TABLE_NAME>;
SELECT * FROM <DB_NAME>.PUBLIC.<TABLE_NAME> ORDER BY INGESTED_AT DESC LIMIT 10;
```

```bash
# KCL checkpoint health (DynamoDB)
aws dynamodb scan --table-name <APP_NAME> \
  --region <AWS_REGION> --profile <AWS_PROFILE> \
  --query 'Items[*].{shard:leaseKey.S,checkpoint:checkpoint.S,counter:leaseCounter.N}'
```


## Cost Estimation (Optional)

### Estimate Actual Costs Based on Running Pipeline

Once your pipeline is flowing, calculate actual costs based on real throughput and usage patterns.

**1. Measure Kinesis Throughput**

```bash
# Get stream metrics for the last hour
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name IncomingRecords \
  --dimensions Name=StreamName,Value=<STREAM_NAME> \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Sum \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE>

# Get data volume (bytes)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name IncomingBytes \
  --dimensions Name=StreamName,Value=<STREAM_NAME> \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Sum \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE>
```

**2. Check DynamoDB Usage**

```bash
# Get table size and read/write capacity
aws dynamodb describe-table \
  --table-name <APP_NAME> \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> \
  --query 'Table.{TableSizeBytes:TableSizeBytes,ItemCount:ItemCount}'
```

**3. Monitor Snowflake Warehouse Usage**

```sql
-- Query history for Openflow connector (last 24 hours)
SELECT
  WAREHOUSE_NAME,
  COUNT(*) as query_count,
  SUM(TOTAL_ELAPSED_TIME)/1000 as total_seconds,
  SUM(TOTAL_ELAPSED_TIME)/1000/3600 as total_hours,
  AVG(BYTES_SCANNED) as avg_bytes_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = '<WAREHOUSE>'
  AND EXECUTION_STATUS = 'SUCCESS'
GROUP BY WAREHOUSE_NAME;

-- Check table storage
SELECT
  TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || TABLE_NAME as full_table_name,
  ROW_COUNT,
  BYTES / (1024*1024*1024) as size_gb,
  BYTES / ROW_COUNT as avg_row_bytes
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = '<TABLE_NAME>'
  AND TABLE_SCHEMA = 'PUBLIC'
  AND TABLE_CATALOG = '<DB_NAME>';
```

**4. Calculate Monthly Costs**

**Kinesis ON_DEMAND Pricing:**
- PUT Payload Units: $0.014 per 1M units (25 KB each)
- Extended Data Retention: $0.023 per GB-hour (if enabled)

```bash
# Example calculation for 1M records/day at 1KB average:
# Daily PUT units = 1,000,000 records × (1KB / 25KB) = 40,000 units
# Monthly cost = 40,000 × 30 days × ($0.014 / 1,000,000) = $0.017
```

**DynamoDB On-Demand Pricing:**
- Write Request Units: $1.25 per million WRUs
- Read Request Units: $0.25 per million RRUs
- Storage: $0.25 per GB-month

```bash
# Example for KCL checkpoint table (minimal usage):
# ~100 writes/hour (checkpoints) = 2,400 writes/day
# Storage: < 1 MB
# Monthly cost ≈ $0.003 (negligible)
```

**Snowflake Pricing:**
- Compute: Varies by edition and warehouse size
  - Standard Edition: $2/credit (us-west-2)
  - X-Small warehouse: 1 credit/hour when running
- Storage: $23-$40 per TB/month (compressed)

```sql
-- Example for 1M records/day, 100 bytes/record compressed:
-- Daily ingestion: 100 MB
-- Monthly storage: ~3 GB
-- Warehouse usage: ~1 hour/day for small warehouse
-- Monthly cost ≈ $60 (compute) + $0.12 (storage) = $60.12
```

**5. Cost Optimization Tips**

**Kinesis:**
- Use ON_DEMAND mode for variable workloads (already configured)
- Consider batching records in producer for larger payloads
- Disable extended retention if not needed (default 24 hours is free)

**DynamoDB:**
- KCL table is minimal cost (~$0.01/month)
- No optimization needed for typical workloads

**Snowflake:**
- Auto-suspend warehouse when idle (configure in Openflow runtime)
- Use appropriate warehouse size (X-Small sufficient for most streaming)
- Consider clustering keys for large tables (>100M rows)

**6. Example Real-World Costs**

| Scenario | Records/Day | Avg Size | Kinesis | DynamoDB | Snowflake | Total/Month |
|----------|-------------|----------|---------|----------|-----------|-------------|
| Low Volume | 100K | 500 bytes | $0.10 | $0.01 | $30 | **$30** |
| Medium Volume | 1M | 1 KB | $0.80 | $0.01 | $60 | **$61** |
| High Volume | 10M | 2 KB | $16.00 | $0.05 | $180 | **$196** |

*Snowflake costs assume X-Small warehouse running ~1 hour/day.*

**7. Set Up Cost Alerts**

```bash
# Create CloudWatch billing alarm (AWS total)
aws cloudwatch put-metric-alarm \
  --alarm-name kinesis-pipeline-cost-alert \
  --alarm-description "Alert when pipeline costs exceed $100/month" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ServiceName,Value=AmazonKinesis \
  --region us-east-1 \
  --profile <AWS_PROFILE>
```

```sql
-- Snowflake resource monitor
CREATE RESOURCE MONITOR kinesis_pipeline_monitor
  WITH CREDIT_QUOTA = 100
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;

-- Assign to warehouse
ALTER WAREHOUSE <WAREHOUSE> SET RESOURCE_MONITOR = kinesis_pipeline_monitor;
```

**Use this data to forecast monthly costs and optimize your pipeline configuration.**



## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Role requested has been explicitly blocked" on OAuth login | Default role is ACCOUNTADMIN/SECURITYADMIN (blocked by OAuth) | Change user's default role or append `&role=<OPENFLOW_ROLE>` to OAuth URL |
| Connector runs but "authorization error" on Snowflake writes | Role not granted to runtime service users | Grant role to `dpa`, `integration-secret`, `runtime-<key>` (see Step 1) |
| Consumer RUNNING, 0 records | DynamoDB unreachable (EAI missing) | Add `dynamodb.<AWS_REGION>.amazonaws.com:443` to network rule |
| "Table does not exist" | Grants missing or table recreated | Re-grant INSERT to Openflow role, restart connector |
| Snowpipe Streaming error on DEFAULT | Column has DEFAULT clause | Recreate table without DEFAULT values |
| KCL checkpoint stuck | Stale lease from previous deployment | Delete items in KCL DynamoDB table, restart connector |

## Cleanup

### Complete Resource Cleanup

Remove all resources created during setup to avoid ongoing charges.

**1. Stop and Delete Openflow Connector**

```bash
# Stop connector
~/.snowflake/venv/nipyapi-env/bin/nipyapi --profile <OPENFLOW_PROFILE> ci stop_flow --process_group_id "<PG_ID>"

# Delete connector from canvas
../venv/bin/python3 -c "
import nipyapi
nipyapi.profiles.switch('<OPENFLOW_PROFILE>')
pg = nipyapi.canvas.get_process_group('<PG_ID>', 'id')
nipyapi.canvas.delete_process_group(pg, force=True)
"
```

**2. Delete AWS Resources**

```bash
# Delete KCL DynamoDB table
aws dynamodb delete-table   --table-name <APP_NAME>   --region <AWS_REGION>   --profile <AWS_PROFILE>

# Delete Kinesis stream
aws kinesis delete-stream   --stream-name <STREAM_NAME>   --region <AWS_REGION>   --profile <AWS_PROFILE>

# If you migrated to Lambda (Option B only):
# Delete Lambda function
aws lambda delete-function   --function-name <LAMBDA_FUNCTION_NAME>   --region <AWS_REGION>   --profile <AWS_PROFILE>

# Delete EventBridge rule
aws events remove-targets   --rule <RULE_NAME>   --ids "1"   --region <AWS_REGION>   --profile <AWS_PROFILE>

aws events delete-rule   --name <RULE_NAME>   --region <AWS_REGION>   --profile <AWS_PROFILE>

# Delete Lambda IAM role (if created)
aws iam delete-role-policy   --role-name <LAMBDA_ROLE_NAME>   --policy-name <POLICY_NAME>

aws iam delete-role   --role-name <LAMBDA_ROLE_NAME>
```

**3. Delete Snowflake Resources**

```sql
-- Drop table, integration, and role
DROP TABLE IF EXISTS <DB_NAME>.PUBLIC.<TABLE_NAME>;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS kinesis_eai;
DROP NETWORK RULE IF EXISTS kinesis_network_rule;
DROP ROLE IF EXISTS <OPENFLOW_ROLE>;

-- Optional: Drop database/schema if created for testing
-- DROP SCHEMA IF EXISTS <DB_NAME>.PUBLIC;
-- DROP DATABASE IF EXISTS <DB_NAME>;
```

**4. Verify Cleanup**

```bash
# Verify Kinesis stream deleted
aws kinesis list-streams   --region <AWS_REGION>   --profile <AWS_PROFILE>

# Verify DynamoDB table deleted
aws dynamodb list-tables   --region <AWS_REGION>   --profile <AWS_PROFILE>

# Verify Lambda deleted (if applicable)
aws lambda list-functions   --region <AWS_REGION>   --profile <AWS_PROFILE>
```

```sql
-- Verify Snowflake cleanup
SHOW TABLES IN <DB_NAME>.PUBLIC;
SHOW INTEGRATIONS LIKE 'kinesis_eai';
SHOW NETWORK RULES LIKE 'kinesis_network_rule';
```

**Cleanup Order:**
1. Stop data flow (Openflow connector)
2. Delete Kinesis stream (stop new data)
3. Delete DynamoDB table (KCL state)
4. Delete Lambda/EventBridge (if used)
5. Delete Snowflake resources (table, integration, role)

**Important:** Deleting the Kinesis stream and DynamoDB table will stop all charges. The Snowflake table doesn't incur storage costs until it has data.

## Estimated Costs (Before Setup)

**Typical monthly costs for low-volume workloads:**

| Service | Configuration | Monthly Cost |
|---------|---------------|-------------|
| Kinesis (ON_DEMAND) | Pay per throughput | ~$0.80 (low volume) |
| DynamoDB (On-Demand) | KCL checkpoint table | ~$0.00 (free tier) |
| CloudWatch | KCL metrics | ~$0.00 (minimal) |
| Openflow SPCS | Snowflake compute | Varies by runtime size |
| **Total (AWS side)** | | **~$1/month** (low volume) |

**For detailed cost estimation based on your actual throughput**, see [Cost Estimation (Optional)](#cost-estimation-optional) after your pipeline is running.
## Complete Workflow Diagram

### Full End-to-End Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    GETTING STARTED                          │
│                  Choose Your Path                           │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
      ┌───────▼────────┐          ┌──────▼──────┐
      │   Option A:    │          │  Option B:  │
      │  Test with     │          │ Production  │
      │  OpenSky Data  │          │   Setup     │
      │                │          │             │
      │  • Learn the   │          │  • Your own │
      │    workflow    │          │    data     │
      │  • Validate    │          │  • Scale to │
      │    pipeline    │          │    Lambda   │
      └───────┬────────┘          └──────┬──────┘
              │                          │
              │ Same workflow,           │
              │ different data source    │
              │                          │
              └─────────┬────────────────┘
                        │
         ┌──────────────▼──────────────┐
         │  PREREQUISITE:              │
         │  Openflow Runtime deployed  │
         │  (../openflow-setup.md)     │
         └──────────────┬──────────────┘
                        │
┌───────────────────────▼────────────────────────┐
│        SETUP WORKFLOW (BOTH OPTIONS)           │
│      Steps 0a → 0b → 1 → 2 → 3 → 4 → 5 → 6     │
└────────────────────────────────────────────────┘

Step 0a: Create Kinesis Stream
   │
   ├─ aws kinesis create-stream (ON_DEMAND)
   ├─ Wait for ACTIVE status (~30s)
   └─ ✓ Stream ready

Step 0b: Run Local Producer
   │
   ├─ Create Python script
   ├─ Fetch data (OpenSky or your source)
   ├─ Push records to Kinesis
   ├─ Monitor output (record count)
   └─ ✓ Data flowing into Kinesis

           ┌─────────────────────────┐
           │  ⚠️  CRITICAL STEP:     │
           │  EXAMINE DATA STRUCTURE │
           └─────────────────────────┘
                    │
    aws kinesis get-records --limit 5
                    │
   ├─ View JSON structure
   ├─ Identify all fields
   ├─ Note data types
   ├─ Check for nested objects
   └─ ✓ Schema documented

Step 1: Identify the Openflow Role
   │
   ├─ SHOW GRANTS ON data plane integration
   ├─ Find role with OWNERSHIP → <OPENFLOW_ROLE>
   ├─ Verify role granted to service users
   ├─ (Production: create dedicated role instead)
   ├─ GRANT role to your user
   ├─ CREATE/GRANT warehouse
   └─ ✓ Role ready for OAuth + connector

Step 2: Create Snowflake Table
   │
   ├─ Design columns from observed data
   ├─ Map JSON → Snowflake types
   ├─ Add INGESTED_AT TIMESTAMP_NTZ
   ├─ CREATE TABLE (no DEFAULT!)
   ├─ GRANT permissions to role
   └─ ✓ Table ready

Step 3: External Access Integration
   │
   ├─ CREATE NETWORK RULE
   │    ├─ kinesis.*.amazonaws.com
   │    ├─ dynamodb.*.amazonaws.com ← REQUIRED!
   │    └─ monitoring.*.amazonaws.com
   ├─ CREATE EXTERNAL ACCESS INTEGRATION
   ├─ GRANT to Openflow role
   ├─ Attach in Openflow UI
   └─ ✓ Network access configured

Step 4: Deploy Kinesis Connector
   │
   ├─ nipyapi ci deploy_flow
   ├─ Registry: ConnectorFlowRegistryClient
   ├─ Bucket: connectors
   ├─ Flow: kinesis
   └─ ✓ Connector deployed (get PG_ID)

Step 5: Configure Connector Parameters
   │
   ├─ AWS Access Key ID
   ├─ AWS Secret Access Key
   ├─ AWS Region Code
   ├─ Kinesis Stream Name
   ├─ Kinesis Application Name (→ DynamoDB table)
   ├─ Kinesis Stream To Table Map
   ├─ Snowflake Warehouse
   ├─ Destination Database/Schema
   ├─ Snowflake Role
   └─ ✓ Connector configured

Step 6: Start Connector
   │
   ├─ nipyapi ci start_flow
   ├─ Openflow starts consuming
   ├─ KCL acquires shard leases
   ├─ Checkpoints written to DynamoDB
   └─ ✓ Connector RUNNING

┌────────────────────────────────────────────────┐
│              VERIFICATION                      │
│           Confirm End-to-End Flow              │
└────────────────────────────────────────────────┘

Check Connector Status
   │
   ├─ nipyapi ci get_status
   └─ ✓ Status: RUNNING

Check Data in Snowflake
   │
   ├─ SELECT COUNT(*) FROM table
   ├─ SELECT * ORDER BY INGESTED_AT DESC LIMIT 10
   └─ ✓ Data appearing in table

Check KCL Checkpoints
   │
   ├─ aws dynamodb scan --table-name <APP_NAME>
   ├─ View: shard, checkpoint, counter
   └─ ✓ Checkpoints updating

         ┌──────────────────────┐
         │   ✅ PIPELINE LIVE   │
         │  Data flowing E2E!   │
         └──────────────────────┘

┌────────────────────────────────────────────────┐
│      COST ESTIMATION (OPTIONAL)                │
│      After Pipeline is Running                 │
└────────────────────────────────────────────────┘

Measure Actual Usage
   │
   ├─ 1. Kinesis metrics (CloudWatch)
   │    └─ IncomingRecords, IncomingBytes
   │
   ├─ 2. DynamoDB table size
   │    └─ aws dynamodb describe-table
   │
   ├─ 3. Snowflake warehouse usage
   │    └─ ACCOUNT_USAGE.QUERY_HISTORY
   │
   └─ 4. Calculate monthly costs
        ├─ Kinesis: $0.014/1M units
        ├─ DynamoDB: $1.25/1M writes
        └─ Snowflake: $2/credit + storage

Example Costs
   │
   ├─ Low (100K/day): $30/month
   ├─ Medium (1M/day): $61/month
   └─ High (10M/day): $196/month

Set Up Alerts
   │
   ├─ AWS CloudWatch billing alarm
   └─ Snowflake Resource Monitor

┌────────────────────────────────────────────────┐
│      PRODUCTION MIGRATION (OPTIONAL)           │
│        Only for Option B users                 │
└────────────────────────────────────────────────┘

After Local Producer Validation:
   │
   ├─ Package producer → Lambda function
   ├─ Create EventBridge rule (schedule)
   ├─ Configure IAM role for Lambda
   ├─ Deploy and test Lambda
   ├─ Monitor CloudWatch logs
   ├─ Stop local producer
   └─ ✓ Production Lambda running

┌────────────────────────────────────────────────┐
│              TROUBLESHOOTING                   │
│           Common Issues & Fixes                │
└────────────────────────────────────────────────┘

Issue: Consumer RUNNING, 0 records
   │
   └─ Fix: Add DynamoDB to network rule

Issue: "Table does not exist"
   │
   └─ Fix: Re-grant INSERT, restart

Issue: Snowpipe Streaming error on DEFAULT
   │
   └─ Fix: Recreate table without DEFAULT

Issue: KCL checkpoint stuck
   │
   └─ Fix: Delete DynamoDB items, restart

┌────────────────────────────────────────────────┐
│              CLEANUP                           │
│      Complete Resource Teardown                │
└────────────────────────────────────────────────┘

Cleanup Order (Critical!):
   │
   ├─ 1. Stop Openflow Connector
   │    └─ nipyapi ci stop_flow
   │
   ├─ 2. Delete Kinesis Stream
   │    └─ aws kinesis delete-stream
   │         (Stops new data)
   │
   ├─ 3. Delete DynamoDB Table
   │    └─ aws dynamodb delete-table
   │         (Removes checkpoints)
   │
   ├─ 4. Delete Lambda + EventBridge (if used)
   │    ├─ aws lambda delete-function
   │    ├─ aws events remove-targets
   │    ├─ aws events delete-rule
   │    └─ aws iam delete-role
   │
   ├─ 5. Delete Snowflake Resources
   │    ├─ DROP TABLE
   │    ├─ DROP EXTERNAL ACCESS INTEGRATION
   │    ├─ DROP NETWORK RULE
   │    └─ DROP ROLE
   │
   └─ 6. Verify Cleanup
        ├─ aws kinesis list-streams
        ├─ aws dynamodb list-tables
        ├─ aws lambda list-functions
        └─ SHOW TABLES / SHOW INTEGRATIONS

         ┌──────────────────────┐
         │   ✅ ALL CLEANED UP  │
         │    No ongoing costs  │
         └──────────────────────┘
```

### Timeline Estimate

| Phase | Steps | Estimated Time |
|-------|-------|----------------|
| **Setup** | 0a, 0b, 1-5 | 30-60 minutes |
| **Verification** | Check flow | 5-10 minutes |
| **Cost Analysis** | Measure usage | 15-30 minutes |
| **Lambda Migration** | Package & deploy | 30-45 minutes (optional) |
| **Cleanup** | Delete all resources | 10-15 minutes |
| **Total (first time)** | | **1-2 hours** |

### Decision Points

```
Start
  │
  ├─ Learning/testing?
  │   └─→ Option A (OpenSky) → Test workflow → Apply to production data
  │
  └─ Production ready?
      └─→ Option B (Your data) → Local producer → Verify → Lambda migration
```

### Cost Breakdown by Component

| Component | Setup Cost | Running Cost | Cleanup Cost |
|-----------|------------|--------------|--------------|
| Kinesis Stream | $0 | $0.10-$16/mo | $0 |
| DynamoDB Table | $0 | ~$0.01/mo | $0 |
| Snowflake Table | $0 | $30-$180/mo | $0 |
| Lambda (optional) | $0 | ~$0.50/mo | $0 |
| **Total** | **$0** | **$30-$196/mo** | **$0** |

*Costs scale with data volume - see [Cost Estimation](#cost-estimation-optional) for detailed calculations.*

### Architecture Summary

```
Producer           AWS              Snowflake
┌─────┐          ┌─────┐          ┌─────────┐
│Local│─────────▶│Kine-│─────────▶│Openflow │
│ or  │  PUT     │sis  │  KCL     │  SPCS   │
│Lam- │          │     │          │         │
│bda  │          └──┬──┘          │         │
└─────┘             │              └────┬────┘
                    │                   │
                    ▼                   ▼
                 ┌─────┐          ┌─────────┐
                 │Dyna-│          │Snowflake│
                 │moDB │          │  Table  │
                 │(KCL)│          │         │
                 └─────┘          └─────────┘
```

**Data Flow:**
1. Producer → Kinesis Stream (PutRecords)
2. Openflow → Kinesis Stream (GetRecords via KCL)
3. KCL → DynamoDB (Checkpoints)
4. Openflow → Snowflake (Snowpipe Streaming)
5. Snowflake → Target Table (INSERT)

### Key Takeaways

✅ **Universal Workflow** - Both Option A and B follow identical steps (only data source differs)

✅ **Schema-First Approach** - Always examine real data before designing table

✅ **Local Testing First** - Start with local producer, migrate to Lambda after validation

✅ **Cost Transparency** - Measure actual costs after pipeline runs, not before

✅ **Complete Cleanup** - Follow teardown order to avoid orphaned resources

✅ **DynamoDB Required** - Missing DynamoDB access = consumer runs but reads zero records

---

**Ready to start?** Jump to [Getting Started](#getting-starte                        

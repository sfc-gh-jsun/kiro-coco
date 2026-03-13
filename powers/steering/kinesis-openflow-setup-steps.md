<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Setup Steps: Kinesis → Openflow → Snowflake

Steps 0a through 6 for deploying the streaming ingestion pipeline.

> All `nipyapi` commands below use `~/kiro-coco-venv/bin/nipyapi`.

---

## Step 0a: Create Kinesis Stream

**For testing:** Create a new test stream to validate the pipeline architecture.

**For production:** Create your production stream with appropriate name and capacity.

```bash
# Create ON_DEMAND stream (no shard provisioning needed)
# Note: create-stream is async — it may appear to hang on AWS CLI v1. This is normal.
# The stream is created on AWS regardless; always verify status separately.
aws kinesis create-stream \
  --stream-name <STREAM_NAME> \
  --stream-mode-config StreamMode=ON_DEMAND \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> 2>&1 || true

# Wait for stream to become ACTIVE (polls every 10s, ~3 min timeout)
aws kinesis wait stream-exists \
  --stream-name <STREAM_NAME> \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> && echo "Stream is ACTIVE"
```

**If `create-stream` hangs:** Ctrl-C and run the `wait stream-exists` command directly — if the stream already exists it returns immediately.

## Step 0b: Run Local Producer

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
STREAM_NAME = "<STREAM_NAME>"
AWS_REGION = "<AWS_REGION>"
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

> **Tip: Run continuously in the background with a 30s interval**
> Change `POLL_INTERVAL = 10` to `POLL_INTERVAL = 30` in the script, then:
> ```bash
> # Run in background, log to file
> nohup python3 /tmp/opensky_producer.py > /tmp/opensky_producer.log 2>&1 &
> echo "Producer PID: $!"
>
> # Monitor output
> tail -f /tmp/opensky_producer.log
>
> # Stop the producer
> kill <PID>
> ```

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
  --stream-name <STREAM_NAME> \
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

## Step 1: Identify the Openflow Role

> **Two-role pattern:** This step produces two distinct roles with different purposes:
>
> | Role | Purpose | Used in |
> |------|---------|---------|
> | `<OPENFLOW_ROLE>` | **Base role** — pre-existing customer role that owns the Openflow deployment. The runtime authenticates as this role via OAuth. Used directly for Snowpipe Streaming writes. | Step 5 "Snowflake Role" param |
> | `<CANVAS_ROLE>` | **Canvas role** — new dedicated role for human UI access to NiFi canvas | Canvas login only |
>
> The base role is a **pre-existing customer role** — it was created before (or during) the Openflow deployment setup, not auto-generated by Snowflake. It may be shared across multiple deployments. You discover it automatically; users don't need to know its name.
>
> See `../connector-auth.md` for the full authentication architecture.

**1a. Find the base role that owns the data plane integration:**

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

**1e. Create a canvas UI user — MANDATORY, DO NOT SKIP**

> This step is MANDATORY. Do NOT skip it, even for demos or quick tests.
> The base `<OPENFLOW_ROLE>` is for connector service authentication only — it must NOT be used
> for human UI login. Privileged roles (ACCOUNTADMIN, SECURITYADMIN, ORGADMIN) are blocked by
> Snowflake OAuth. A dedicated canvas role + canvas user with a non-privileged default role is
> always required for NiFi canvas access.

A dedicated canvas user must always be created. This separates human UI access from the connector's
service authentication and avoids using privileged roles (ACCOUNTADMIN, SECURITYADMIN, ORGADMIN
are blocked by Snowflake's OAuth).

First, discover the SPCS service names:

```sql
SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
```

Create a dedicated `<CANVAS_ROLE>` with endpoint access on both SPCS services:

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS <CANVAS_ROLE>;
GRANT ROLE <CANVAS_ROLE> TO ROLE ACCOUNTADMIN;

-- Canvas UI endpoint access (runtime + data plane services)
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_RUNTIME_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_DATAPLANE_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;

-- Integration access (view/operate the canvas)
GRANT USAGE   ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
GRANT OPERATE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
GRANT USAGE   ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <CANVAS_ROLE>;

-- Create the canvas user
CREATE USER IF NOT EXISTS <CANVAS_USER>
  PASSWORD          = '<PASSWORD>'
  DEFAULT_ROLE      = <CANVAS_ROLE>
  MUST_CHANGE_PASSWORD = FALSE;

GRANT ROLE <CANVAS_ROLE> TO USER <CANVAS_USER>;
```

Log in at: `https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/<RUNTIME_KEY>/nifi/`

If OAuth blocks the login, append `?role=<CANVAS_ROLE>` to the URL.

> See `../openflow-setup.md` Section 5 for full discovery steps and grant reference.

## Step 2: Create Snowflake Database & Grants

```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS <DB_NAME>;
CREATE SCHEMA IF NOT EXISTS <DB_NAME>.PUBLIC;

-- Grant to Openflow role
GRANT USAGE ON DATABASE <DB_NAME> TO ROLE <OPENFLOW_ROLE>;
GRANT USAGE ON SCHEMA <DB_NAME>.PUBLIC TO ROLE <OPENFLOW_ROLE>;
GRANT USAGE ON WAREHOUSE <WAREHOUSE> TO ROLE <OPENFLOW_ROLE>;

-- Schema evolution grants (modularized connector auto-creates tables)
GRANT CREATE TABLE ON SCHEMA <DB_NAME>.PUBLIC TO ROLE <OPENFLOW_ROLE>;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA <DB_NAME>.PUBLIC TO ROLE <OPENFLOW_ROLE>;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA <DB_NAME>.PUBLIC TO ROLE <OPENFLOW_ROLE>;
```

> **Modularized connector (default):** No need to pre-create a table. The connector uses
> schema evolution to auto-create a table named after the Kinesis stream (uppercased).
> For example, stream `my-events-stream` creates table `"MY-EVENTS-STREAM"` (quoted due to hyphens).
> The `CREATE TABLE ON SCHEMA` + `FUTURE TABLES` grants above are required for this.

**Legacy connector only — pre-create the target table:**

If using the legacy `kinesis` flow, you must create the table manually. The modularized connector
ignores pre-created tables entirely.

**Schema requirements** (Snowpipe Streaming limitation):
No DEFAULT values, no AUTOINCREMENT, no GEO columns.
Every column must have a matching field in the source JSON, or you'll get a `SchemaMismatchException`.

```sql
-- [Legacy only] Flight data schema from OpenSky (all 8 fields from source)
-- Sample record: {"utc":1773416947,"id":"DAL1742","icao":"acd120",
--   "orig":"KATL","dest":"KSJC","alt":"23275","lat":"37.17","lon":"-120.45"}
CREATE TABLE <DB_NAME>.PUBLIC.<TABLE_NAME> (
    UTC VARCHAR,
    ID VARCHAR,
    ICAO VARCHAR,
    ORIG VARCHAR,
    DEST VARCHAR,
    ALT VARCHAR,
    LAT VARCHAR,
    LON VARCHAR
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE <DB_NAME>.PUBLIC.<TABLE_NAME> TO ROLE <OPENFLOW_ROLE>;
```

## Step 3: Create External Access Integration

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

## Step 4: Deploy Kinesis Connector

```bash
# Deploy modularized connector from registry (default)
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci deploy_flow \
  --registry_client ConnectorFlowRegistryClient \
  --bucket connectors \
  --flow kinesis-json-modularized
```

> **Legacy alternative:** If the runtime only has the legacy `kinesis` flow in its registry
> (older runtimes), use `--flow kinesis` instead. Check available flows with:
> `~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci list_registry_flows --registry_client ConnectorFlowRegistryClient --bucket connectors`

## Step 5: Configure Connector Parameters

The modularized connector has 3 nested sub-PGs (Kinesis JSON Source, Streaming Destination, Custom Transformations), each with its own parameter context. You must configure them separately, and sensitive parameters (AWS keys) require the NiFi REST API.

**5a. Discover sub-PG IDs:**

```bash
# Get the NiFi URL and bearer token
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> profiles resolve_profile_config

# List sub-PGs inside the deployed connector
curl -s -H "Authorization: Bearer <TOKEN>" \
  "<NIFI_URL>/process-groups/<PG_ID>/process-groups" | python3 -m json.tool
```

Note the `id` of each sub-PG and the `parameterContext.id` of the Kinesis JSON Source.

**5b. Configure non-sensitive Source parameters:**

```bash
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci configure_inherited_params \
  --process_group_id "<SOURCE_PG_ID>" \
  --parameters '{
    "AWS Region Code": "<AWS_REGION>",
    "Kinesis Stream Name": "<STREAM_NAME>",
    "Kinesis Application Name": "<APP_NAME>",
    "Kinesis Consumer Type": "SHARED_THROUGHPUT",
    "Kinesis Initial Stream Position": "TRIM_HORIZON"
  }'
```

**5c. Configure sensitive parameters (AWS keys) via NiFi REST API:**

> **WARNING:** Do NOT use `configure_inherited_params` or `configure_params` for sensitive
> parameters on the modularized connector. nipyapi will attempt to change them from sensitive
> to non-sensitive, causing a 409 Conflict error.

> **IMPORTANT:** You must fetch the **current revision version** before submitting the update.
> Step 5b increments the revision, so hardcoding `"version": 0` will fail with
> "is not the most up-to-date revision" (HTTP 400).

> **TIP:** If your AWS secret key contains special characters (e.g., `/`, `+`), inline JSON
> in curl will break. Write the JSON to a temp file using a heredoc (`<< 'JSONEOF'`) and
> pass it with `curl -d @/tmp/file.json`.

```bash
# Get the parameter context ID for the Source sub-PG
SOURCE_CTX_ID=$(~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> \
  ci export_parameters --process_group_id "<SOURCE_PG_ID>" 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['context_id'])")

# Fetch current revision version (REQUIRED — do not hardcode)
REVISION=$(curl -s -H "Authorization: Bearer <TOKEN>" \
  "<NIFI_URL>/parameter-contexts/$SOURCE_CTX_ID" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['revision']['version'])")

# Submit update request with sensitive: true
curl -s -X POST \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  "<NIFI_URL>/parameter-contexts/$SOURCE_CTX_ID/update-requests" \
  -d "{
    \"revision\": {\"version\": $REVISION},
    \"id\": \"$SOURCE_CTX_ID\",
    \"component\": {
      \"id\": \"$SOURCE_CTX_ID\",
      \"parameters\": [
        {\"parameter\": {\"name\": \"AWS Access Key ID\", \"sensitive\": true, \"value\": \"<AWS_ACCESS_KEY>\"}},
        {\"parameter\": {\"name\": \"AWS Secret Access Key\", \"sensitive\": true, \"value\": \"<AWS_SECRET_KEY>\"}}
      ]
    }
  }"
```

**5d. Configure Streaming Destination parameters:**

```bash
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci configure_inherited_params \
  --process_group_id "<DEST_PG_ID>" \
  --parameters '{
    "Destination Database": "<DB_NAME>",
    "Destination Schema": "PUBLIC",
    "Snowflake Role": "<OPENFLOW_ROLE>"
  }'
```

> **Note:** `Snowflake Authentication Strategy` defaults to `SNOWFLAKE_MANAGED` — correct for SPCS runtimes. Do not change it.

---

**Legacy connector alternative** (`kinesis` flow — single PG, single `configure_inherited_params` call):

If using the legacy `kinesis` flow, all parameters are set in one call:

```bash
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci configure_inherited_params \
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

## Step 6: Start Connector

```bash
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci start_flow \
  --process_group_id "<PG_ID>"
```

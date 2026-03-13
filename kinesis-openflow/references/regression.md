# Regression: Kinesis → Openflow → Snowflake (Batch Mode)

Non-interactive end-to-end regression test. All values come from `params-regression.yaml`.

> **Only manual step:** Attaching the EAI to the Openflow runtime in the Control Plane UI (Phase 2c).

SKILL_DIR = `~/.claude/skills/kiro-coco`

---

## Phase 0: Cleanup Previous Run

Skip this phase on first run. On subsequent runs, tear down previous resources first.

### 0a. Stop and delete Openflow connector

```bash
# Stop connector (may timeout — Kinesis consumer checkpointing is slow, ~60s)
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci stop_flow \
  --process_group_id "<PG_ID>"

# Delete connector from canvas
~/.claude/skills/kiro-coco/venv/bin/python3 -c "
import nipyapi
nipyapi.profiles.switch('spcs1-regression-test')
pg = nipyapi.canvas.get_process_group('<PG_ID>', 'id')
nipyapi.canvas.delete_process_group(pg, force=True)
print('Deleted process group')
"
```

### 0b. Delete AWS resources

```bash
# Delete KCL DynamoDB table
aws dynamodb delete-table \
  --table-name opensky-regression-consumer \
  --region us-west-2 \
  --profile jsnow 2>&1 || echo "Table doesn't exist, skipping"

# Delete Kinesis stream
aws kinesis delete-stream \
  --stream-name opensky-regression-stream \
  --enforce-consumer-deletion \
  --region us-west-2 \
  --profile jsnow 2>&1 || echo "Stream doesn't exist, skipping"

# Wait for stream deletion
aws kinesis wait stream-not-exists \
  --stream-name opensky-regression-stream \
  --region us-west-2 \
  --profile jsnow 2>&1 || true
```

### 0c. Delete Snowflake resources

```sql
-- Run via: snow sql -c HOL -q "<sql>"
DROP TABLE IF EXISTS KINESIS_REGRESSION_DB.PUBLIC.FLIGHT_DATA;
DROP EXTERNAL ACCESS INTEGRATION IF EXISTS kinesis_regression_eai;
DROP NETWORK RULE IF EXISTS kinesis_regression_network_rule;
DROP DATABASE IF EXISTS KINESIS_REGRESSION_DB;
```

### 0d. Detach EAI from runtime

In the Openflow Control Plane UI, detach `kinesis_regression_eai` from spcs1-regression-test runtime (if attached).

---

## Phase 1: AWS Setup

### 1a. Create Kinesis stream

```bash
aws kinesis create-stream \
  --stream-name opensky-regression-stream \
  --stream-mode-config StreamMode=ON_DEMAND \
  --region us-west-2 \
  --profile jsnow 2>&1 || true

aws kinesis wait stream-exists \
  --stream-name opensky-regression-stream \
  --region us-west-2 \
  --profile jsnow && echo "Stream ACTIVE"
```

### 1b. Start local producer (background)

```bash
cat > /tmp/regression_producer.py << 'PRODUCER_EOF'
#!/usr/bin/env python3
import json, time, boto3, requests, sys
from datetime import datetime

OPENSKY_URL = "http://ecs-alb-1504531980.us-west-2.elb.amazonaws.com:8502/opensky"
STREAM_NAME = "opensky-regression-stream"
DURATION = int(sys.argv[1]) if len(sys.argv) > 1 else 120

session = boto3.Session(profile_name="jsnow", region_name="us-west-2")
kinesis = session.client('kinesis')

print(f"Producer starting — {DURATION}s duration, stream={STREAM_NAME}")
start = time.time()
total = 0

while time.time() - start < DURATION:
    try:
        resp = requests.get(OPENSKY_URL, timeout=10)
        data = resp.json()
        if data:
            batch = [{'Data': json.dumps(r), 'PartitionKey': r.get('icao','unknown')} for r in data[:500]]
            result = kinesis.put_records(StreamName=STREAM_NAME, Records=batch)
            sent = len(batch) - result.get('FailedRecordCount', 0)
            total += sent
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Sent {sent} (total: {total})")
    except Exception as e:
        print(f"Error: {e}")
    time.sleep(10)

print(f"Producer done. Total: {total} records in {int(time.time()-start)}s")
PRODUCER_EOF

# Run producer for 120s in background
nohup python3 /tmp/regression_producer.py 120 > /tmp/regression_producer.log 2>&1 &
PRODUCER_PID=$!
echo "Producer PID: $PRODUCER_PID"
```

### 1c. Verify data in stream

```bash
# Wait 15s for first batch, then check
sleep 15

SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name opensky-regression-stream \
  --shard-id shardId-000000000000 \
  --shard-iterator-type TRIM_HORIZON \
  --region us-west-2 \
  --profile jsnow \
  --query 'ShardIterator' --output text)

RECORD_COUNT=$(aws kinesis get-records \
  --shard-iterator "$SHARD_ITERATOR" \
  --limit 5 \
  --region us-west-2 \
  --profile jsnow \
  --query 'length(Records)' --output text)

echo "Records found: $RECORD_COUNT"
[ "$RECORD_COUNT" -gt 0 ] && echo "PASS: Data flowing" || echo "FAIL: No data"
```

---

## Phase 2: Snowflake Setup

### 2a. Create database and table

```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS KINESIS_REGRESSION_DB;

-- NOTE: The modularized connector (kinesis-json-modularized) does NOT use this table.
-- It uses schema evolution to auto-create a table named after the Kinesis stream
-- (e.g., "OPENSKY-REGRESSION-STREAM"). This pre-created table is only needed for
-- the legacy `kinesis` connector on spcs1.
CREATE TABLE IF NOT EXISTS KINESIS_REGRESSION_DB.PUBLIC.FLIGHT_DATA (
    UTC VARCHAR,        -- Unix epoch timestamp
    ID VARCHAR,         -- Flight callsign
    ICAO VARCHAR,       -- Aircraft ICAO hex code
    ORIG VARCHAR,       -- Origin airport ICAO code
    DEST VARCHAR,       -- Destination airport ICAO code
    ALT VARCHAR,        -- Altitude in feet
    LAT VARCHAR,        -- Latitude
    LON VARCHAR         -- Longitude
);

GRANT USAGE ON DATABASE KINESIS_REGRESSION_DB TO ROLE ADF_PL_RL;
GRANT USAGE ON SCHEMA KINESIS_REGRESSION_DB.PUBLIC TO ROLE ADF_PL_RL;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE KINESIS_REGRESSION_DB.PUBLIC.FLIGHT_DATA TO ROLE ADF_PL_RL;
GRANT USAGE ON WAREHOUSE ADF_PL_WH TO ROLE ADF_PL_RL;

-- IMPORTANT: Modularized connector uses schema evolution to auto-create tables.
-- The role needs CREATE TABLE + full privileges on future tables.
GRANT CREATE TABLE ON SCHEMA KINESIS_REGRESSION_DB.PUBLIC TO ROLE ADF_PL_RL;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA KINESIS_REGRESSION_DB.PUBLIC TO ROLE ADF_PL_RL;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA KINESIS_REGRESSION_DB.PUBLIC TO ROLE ADF_PL_RL;
```

### 2b. Create network rule and EAI

```sql
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE NETWORK RULE kinesis_regression_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = (
    'kinesis.us-west-2.amazonaws.com:443',
    'kinesis.us-west-2.api.aws:443',
    '*.control-kinesis.us-west-2.amazonaws.com:443',
    '*.data-kinesis.us-west-2.amazonaws.com:443',
    '*.control-kinesis.us-west-2.api.aws:443',
    '*.data-kinesis.us-west-2.api.aws:443',
    'dynamodb.us-west-2.amazonaws.com:443',
    'monitoring.us-west-2.amazonaws.com:443',
    'monitoring.us-west-2.api.aws:443'
  );

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION kinesis_regression_eai
  ALLOWED_NETWORK_RULES = ('kinesis_regression_network_rule')
  ENABLED = true;

GRANT USAGE ON INTEGRATION kinesis_regression_eai TO ROLE ADF_PL_RL;
```

### 2c. MANUAL STEP — Attach EAI to runtime

**This is the only step that cannot be automated.**

1. Open the Openflow Control Plane UI
2. Navigate to the spcs1-regression-test runtime
3. Attach `kinesis_regression_eai`
4. Wait for the runtime to restart (~1-2 min)

> After attaching, verify the runtime is still RUNNING:
> ```sql
> SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
> ```

---

## Phase 3: Deploy & Configure Connector

### 3a. Deploy connector

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci deploy_flow \
  --registry_client ConnectorFlowRegistryClient \
  --bucket connectors \
  --flow kinesis-json-modularized
```

Capture the process group ID from the output — this is `<PG_ID>`.

### 3b. Discover sub-process group IDs

The `kinesis-json-modularized` connector has **3 nested sub-PGs**, each with its own parameter context.
You CANNOT use a single `configure_inherited_params` on the parent PG — it has no parameter context.

```bash
# List child process groups inside the deployed connector
NIFI_URL=$(~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test \
  profiles resolve_profile_config spcs1-regression-test 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['nifi_url'])")
TOKEN=$(~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test \
  profiles resolve_profile_config spcs1-regression-test 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['nifi_bearer_token'])")

curl -s -H "Authorization: Bearer $TOKEN" \
  "$NIFI_URL/process-groups/<PG_ID>/process-groups" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
for pg in data.get('processGroups', []):
    c = pg['component']
    ctx = c.get('parameterContext', {}).get('component', {})
    print(f'{c[\"name\"]:40s} PG_ID={c[\"id\"]}  Context={ctx.get(\"name\",\"NONE\")}')
"
```

Expected output (3 sub-PGs):
```
Kinesis JSON Source                       PG_ID=<SOURCE_PG_ID>    Context=Kinesis JSON Source Parameters
Custom Transformations                    PG_ID=<TRANSFORM_PG_ID> Context=Custom Transformations Parameters
Streaming Destination                     PG_ID=<DEST_PG_ID>      Context=Streaming Destination Parameters
```

Capture `<SOURCE_PG_ID>` and `<DEST_PG_ID>`. The Custom Transformations sub-PG is a passthrough — no config needed.

### 3c. Configure Kinesis JSON Source (non-sensitive params)

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci configure_inherited_params \
  --process_group_id "<SOURCE_PG_ID>" \
  --parameters '{
    "AWS Region Code": "us-west-2",
    "Kinesis Stream Name": "opensky-regression-stream",
    "Kinesis Application Name": "opensky-regression-consumer",
    "Kinesis Initial Stream Position": "TRIM_HORIZON",
    "Kinesis Consumer Type": "SHARED_THROUGHPUT"
  }'
```

> **IMPORTANT — Consumer Type:**
> - `SHARED_THROUGHPUT` (recommended for regression): Polling-based, starts immediately, shares 2 MB/s per shard across consumers.
> - `ENHANCED_FAN_OUT`: Dedicated 2 MB/s per consumer via HTTP/2 push. Takes **up to 10 minutes** to initialize on first run (AWS consumer registration + KCL scheduler setup). Can cause stuck processor shutdown during the init window. Only use for production with multiple consumers.

### 3d. Configure Kinesis JSON Source (sensitive params — AWS credentials)

`configure_inherited_params` and `configure_params` **cannot set sensitive parameters** — they attempt to change the parameter from sensitive to non-sensitive, causing a 409 Conflict error.

Use the NiFi REST API directly to preserve the `sensitive: true` flag:

```bash
# Get the parameter context ID for the Source sub-PG
SOURCE_CTX_ID=$(~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test \
  ci export_parameters --process_group_id "<SOURCE_PG_ID>" 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['context_id'])")

# Get current revision version
REVISION=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "$NIFI_URL/parameter-contexts/$SOURCE_CTX_ID" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['revision']['version'])")

# Submit update request with sensitive: true
REQUEST_ID=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$NIFI_URL/parameter-contexts/$SOURCE_CTX_ID/update-requests" \
  -d "{
    \"revision\": {\"version\": $REVISION},
    \"id\": \"$SOURCE_CTX_ID\",
    \"component\": {
      \"id\": \"$SOURCE_CTX_ID\",
      \"parameters\": [
        {\"parameter\": {\"name\": \"AWS Access Key ID\", \"sensitive\": true, \"value\": \"AKIAXBUYSSFIFQEVCHFR\"}},
        {\"parameter\": {\"name\": \"AWS Secret Access Key\", \"sensitive\": true, \"value\": \"<AWS_SECRET_KEY>\"}}
      ]
    }
  }" | python3 -c "import json,sys; print(json.load(sys.stdin)['request']['requestId'])")

echo "Update request: $REQUEST_ID"

# Poll until complete (typically 5-15 seconds)
for i in $(seq 1 12); do
  sleep 5
  STATUS=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$NIFI_URL/parameter-contexts/$SOURCE_CTX_ID/update-requests/$REQUEST_ID" | \
    python3 -c "import json,sys; r=json.load(sys.stdin)['request']; print(f'{r[\"complete\"]} {r[\"state\"]}')")
  echo "  [$i] $STATUS"
  [[ "$STATUS" == True* ]] && break
done
```

### 3e. Configure Streaming Destination

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci configure_inherited_params \
  --process_group_id "<DEST_PG_ID>" \
  --parameters '{
    "Destination Database": "KINESIS_REGRESSION_DB",
    "Destination Schema": "PUBLIC",
    "Snowflake Role": "ADF_PL_RL"
  }'
```

> **Note:** `Snowflake Authentication Strategy` defaults to `SNOWFLAKE_MANAGED` — correct for SPCS runtimes. Do not change it.

### 3f. Start connector

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci start_flow \
  --process_group_id "<PG_ID>"
```

---

## Phase 4: Verify

> **Wait 5 minutes** after starting before checking. KCL needs time to initialize leases and flush.

### 4a. Connector status

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test ci get_status \
  --process_group_id "<PG_ID>"
```

Expected: all processors RUNNING, no STOPPED/INVALID.

### 4b. Row count in Snowflake

**For modularized connector** (`kinesis-json-modularized`): The table is auto-created by schema evolution and named after the Kinesis stream (uppercase, hyphenated — must be quoted):

```sql
-- Modularized connector (spcs1-regression-test): auto-created table
SELECT COUNT(*) AS ROW_COUNT FROM KINESIS_REGRESSION_DB.PUBLIC."OPENSKY-REGRESSION-STREAM";
SELECT * FROM KINESIS_REGRESSION_DB.PUBLIC."OPENSKY-REGRESSION-STREAM" ORDER BY RECORD_METADATA:CreateTimestamp::TIMESTAMP DESC LIMIT 5;
```

**For legacy connector** (`kinesis`): Uses the pre-created `FLIGHT_DATA` table:

```sql
-- Legacy connector (spcs1): pre-created table
SELECT COUNT(*) AS ROW_COUNT FROM KINESIS_REGRESSION_DB.PUBLIC.FLIGHT_DATA;
SELECT * FROM KINESIS_REGRESSION_DB.PUBLIC.FLIGHT_DATA ORDER BY INGESTED_AT DESC LIMIT 5;
```

Expected: ROW_COUNT > 0 after 5 min.

> **Tip:** If unsure which table the data went to, run:
> ```sql
> SHOW TABLES IN SCHEMA KINESIS_REGRESSION_DB.PUBLIC;
> ```

### 4c. KCL checkpoint health

```bash
aws dynamodb scan \
  --table-name opensky-regression-consumer \
  --region us-west-2 \
  --profile jsnow \
  --query 'Items[*].{shard:leaseKey.S,checkpoint:checkpoint.S,counter:leaseCounter.N}'
```

Expected: at least one shard with a non-null checkpoint.

### 4d. Check for errors (bulletins)

```bash
~/.claude/skills/kiro-coco/venv/bin/nipyapi --profile spcs1-regression-test bulletins get_bulletin_board
```

Expected: no new error bulletins with fresh timestamps (stale ones from previous runs are OK).

---

## Regression Pass/Fail Criteria

| Check | Pass | Fail |
|-------|------|------|
| Kinesis stream ACTIVE | Stream exists and has records | Stream missing or empty |
| Snowflake table exists | Table with correct schema | Table missing or wrong schema |
| Connector RUNNING | All processors in RUNNING state | Any processor STOPPED/INVALID |
| Row count > 0 | Data flowing after 5 min | 0 rows after 5 min |
| KCL checkpoints | At least 1 shard with checkpoint | No checkpoints (DynamoDB empty) |
| No fresh error bulletins | No new errors | New errors with recent timestamps |

---

## Timing Summary

| Phase | Duration |
|-------|----------|
| Phase 0: Cleanup | ~2 min |
| Phase 1: AWS Setup + Producer | ~2 min setup + 2 min data |
| Phase 2: Snowflake Setup | ~1 min SQL + **manual EAI attach ~2 min** |
| Phase 3: Deploy & Configure | ~2 min |
| Phase 4: Verify (wait + check) | ~5 min wait + 1 min checks |
| **Total** | **~15 min** |

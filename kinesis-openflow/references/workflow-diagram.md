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

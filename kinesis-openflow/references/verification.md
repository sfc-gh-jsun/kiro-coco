# Verification: Kinesis → Openflow → Snowflake

> **Wait at least 5 minutes** after starting the connector before checking for data.
> KCL needs time to initialize, acquire shard leases, and flush the first batch via
> Snowpipe Streaming. Checking too early will show 0 rows and cause false alarms.

```bash
# Connector status
<SKILL_DIR>/venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci get_status \
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

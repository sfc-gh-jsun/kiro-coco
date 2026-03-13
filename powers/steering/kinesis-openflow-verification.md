<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Verification: Kinesis → Openflow → Snowflake

> **Wait at least 5 minutes** after starting the connector before checking for data.
> KCL needs time to initialize, acquire shard leases, and flush the first batch via
> Snowpipe Streaming. Checking too early will show 0 rows and cause false alarms.

```bash
# Connector status
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci get_status \
  --process_group_id "<PG_ID>"
```

**Data in Snowflake (modularized connector — default):**

The modularized connector auto-creates a table named after the Kinesis stream (uppercased).
If unsure of the table name, run `SHOW TABLES IN <DB_NAME>.PUBLIC;` first.

```sql
-- Modularized connector: auto-created table (quoted due to hyphens/special chars)
SELECT COUNT(*) AS ROW_COUNT FROM <DB_NAME>.PUBLIC."<AUTO_TABLE_NAME>";
SELECT * FROM <DB_NAME>.PUBLIC."<AUTO_TABLE_NAME>"
  ORDER BY RECORD_METADATA:CreateTimestamp::TIMESTAMP DESC LIMIT 10;
```

> **TIP:** Run `SHOW TABLES IN SCHEMA <DB_NAME>.PUBLIC;` to discover the auto-created table name.

**Data in Snowflake (legacy connector):**

```sql
-- Legacy connector: pre-created table
SELECT COUNT(*) FROM <DB_NAME>.PUBLIC.<TABLE_NAME>;
SELECT * FROM <DB_NAME>.PUBLIC.<TABLE_NAME> ORDER BY INGESTED_AT DESC LIMIT 10;
```

```bash
# KCL checkpoint health (DynamoDB)
aws dynamodb scan --table-name <APP_NAME> \
  --region <AWS_REGION> --profile <AWS_PROFILE> \
  --query 'Items[*].{shard:leaseKey.S,checkpoint:checkpoint.S,counter:leaseCounter.N}'
```

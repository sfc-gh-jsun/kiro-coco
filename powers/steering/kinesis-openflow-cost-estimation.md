<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Cost Estimation: Kinesis → Openflow → Snowflake

Once your pipeline is flowing, calculate actual costs based on real throughput and usage patterns.

## 1. Measure Kinesis Throughput

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

## 2. Check DynamoDB Usage

```bash
# Get table size and read/write capacity
aws dynamodb describe-table \
  --table-name <APP_NAME> \
  --region <AWS_REGION> \
  --profile <AWS_PROFILE> \
  --query 'Table.{TableSizeBytes:TableSizeBytes,ItemCount:ItemCount}'
```

## 3. Monitor Snowflake Warehouse Usage

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

## 4. Calculate Monthly Costs

**Kinesis ON_DEMAND Pricing:**
- PUT Payload Units: $0.014 per 1M units (25 KB each)
- Extended Data Retention: $0.023 per GB-hour (if enabled)

```bash
# Example calculation for 1M records/day at 1KB average:
# Daily PUT units = 1,000,000 records x (1KB / 25KB) = 40,000 units
# Monthly cost = 40,000 x 30 days x ($0.014 / 1,000,000) = $0.017
```

**DynamoDB On-Demand Pricing:**
- Write Request Units: $1.25 per million WRUs
- Read Request Units: $0.25 per million RRUs
- Storage: $0.25 per GB-month

```bash
# Example for KCL checkpoint table (minimal usage):
# ~100 writes/hour (checkpoints) = 2,400 writes/day
# Storage: < 1 MB
# Monthly cost ~ $0.003 (negligible)
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
-- Monthly cost ~ $60 (compute) + $0.12 (storage) = $60.12
```

## 5. Cost Optimization Tips

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

## 6. Example Real-World Costs

| Scenario | Records/Day | Avg Size | Kinesis | DynamoDB | Snowflake | Total/Month |
|----------|-------------|----------|---------|----------|-----------|-------------|
| Low Volume | 100K | 500 bytes | $0.10 | $0.01 | $30 | **$30** |
| Medium Volume | 1M | 1 KB | $0.80 | $0.01 | $60 | **$61** |
| High Volume | 10M | 2 KB | $16.00 | $0.05 | $180 | **$196** |

*Snowflake costs assume X-Small warehouse running ~1 hour/day.*

## 7. Set Up Cost Alerts

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

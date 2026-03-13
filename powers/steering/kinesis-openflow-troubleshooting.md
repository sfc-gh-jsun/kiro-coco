<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Troubleshooting & Cleanup: Kinesis → Openflow → Snowflake

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Role requested has been explicitly blocked" on OAuth login | Default role is ACCOUNTADMIN/SECURITYADMIN (blocked by OAuth) | Change user's default role or append `&role=<OPENFLOW_ROLE>` to OAuth URL |
| Connector runs but "authorization error" on Snowflake writes | Role not granted to runtime service users | Grant role to `dpa`, `integration-secret`, `runtime-<key>` (see Step 1) |
| Consumer RUNNING, 0 records | DynamoDB unreachable (EAI missing) | Add `dynamodb.<AWS_REGION>.amazonaws.com:443` to network rule |
| "Table does not exist" | Grants missing or table recreated | Re-grant INSERT to Openflow role, restart connector |
| Snowpipe Streaming error on DEFAULT | Column has DEFAULT clause | Recreate table without DEFAULT values |
| KCL checkpoint stuck | Stale lease from previous deployment | Delete items in KCL DynamoDB table, restart connector |
| **Modularized: 409 Conflict on `configure_params`/`configure_inherited_params`** | nipyapi tries to set sensitive params (AWS keys) as non-sensitive, NiFi rejects the change | Use NiFi REST API directly: `POST /parameter-contexts/{id}/update-requests` with `"sensitive": true` in the parameter payload. See `regression.md` Phase 3d. |
| **Modularized: Consumer processor INVALID — "Given value not found in allowed set"** | `Kinesis Consumer Type` set to invalid value like `POLLING` | Valid values are `SHARED_THROUGHPUT` (polling) or `ENHANCED_FAN_OUT` (dedicated). Do NOT use `POLLING`. |
| **Modularized: Data goes to unexpected table** | Schema evolution auto-creates table named after the Kinesis stream (uppercased) instead of using a pre-created table | This is by design. Check `SHOW TABLES IN SCHEMA` to find the auto-created table (e.g., `"OPENSKY-REGRESSION-STREAM"`). Must be quoted in SQL due to hyphens. |
| **Modularized: "Insufficient privileges to operate on schema"** | Connector needs CREATE TABLE to auto-create tables via schema evolution, plus ALL on future tables | Grant `CREATE TABLE ON SCHEMA`, `ALL PRIVILEGES ON ALL TABLES IN SCHEMA`, and `ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA` to the Openflow role. |
| **Modularized: REST API 400 "not the most up-to-date revision"** | Hardcoded `"version": 0` in the sensitive param update, but `configure_inherited_params` (Step 5b) already incremented the revision | Always `GET /parameter-contexts/{id}` first to fetch the current revision version, then use that version in the update request. |
| **Modularized: JSON parse error on sensitive param curl** | AWS secret key contains `/`, `+`, or other shell-special characters that break inline JSON | Write JSON to a temp file using heredoc (`cat << 'JSONEOF' > /tmp/params.json`) and use `curl -d @/tmp/params.json`. The single-quoted heredoc prevents shell interpretation. |

## Cleanup

### Complete Resource Cleanup

Remove all resources created during setup to avoid ongoing charges.

**1. Stop and Delete Openflow Connector**

```bash
# Stop connector
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> ci stop_flow --process_group_id "<PG_ID>"

# Delete connector from canvas
~/kiro-coco-venv/bin/python3 -c "
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

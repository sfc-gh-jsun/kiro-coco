# Openflow Runtime Setup (Manual)

Minimal steps to get an Openflow runtime accessible via nipyapi.

> All `snow` and `nipyapi` commands below assume the venv created by `SKILL.md` prerequisites.
> Use `venv/bin/snow` and `venv/bin/nipyapi` from the skill root directory.

## 1. Verify tooling

```bash
venv/bin/snow --version && venv/bin/nipyapi --help > /dev/null && echo "OK"
```

If the venv doesn't exist yet, create it first (see `SKILL.md` Prerequisites).

## 2. Discover deployments and runtimes

### 2a. Find deployments

```bash
venv/bin/snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW DATA PLANE INTEGRATIONS;" --format json
```

| Result | Action |
|--------|--------|
| Empty result | No Openflow deployed — deploy via the Snowflake Control Plane UI first |
| Returns rows | Extract deployment names, continue |

For each deployment, get details:

```bash
venv/bin/snow sql -c <SNOWFLAKE_CONNECTION> -q "DESCRIBE INTEGRATION <data_plane_integration>;" --format json
```

Extract `DATA_PLANE_ID` and `EVENT_TABLE` from the output.

### 2b. Find runtimes

```bash
venv/bin/snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW RUNTIME INTEGRATIONS;" --format json
```

Each row has an `OAUTH_REDIRECT_URI` field. Extract the NiFi API endpoint from it:
- **Host**: the domain before the runtime path
- **Runtime key**: the path segment before `/login/oauth2/...`
- **NiFi API URL**: `https://<host>/<runtime_key>/nifi-api`

### 2c. Detect deployment type

| URL pattern | Type |
|-------------|------|
| Host starts with `of--` | SPCS |
| Host contains `snowflake-customer.app` | BYOC |

If no runtimes exist, deploy Openflow via the Snowflake Control Plane UI first.

## 3. Create nipyapi profile

Using the values extracted from step 2b:

```bash
venv/bin/nipyapi profiles resolve_profile_config \
  --profile_name "<OPENFLOW_PROFILE>" \
  --nifi_url "https://<host>/<runtime_key>/nifi-api" \
  --nifi_bearer_token "<BEARER_TOKEN>" \
  --nifi_verify_ssl true
```

**Example** — given this `OAUTH_REDIRECT_URI` from step 2b:
```
https://of--sfsenorthamerica-jsnow-vhol-demo.snowflakecomputing.app/spcs1/login/oauth2/code/snowflake-openflow
```
The profile command would be:
```bash
venv/bin/nipyapi profiles resolve_profile_config \
  --profile_name "spcs1" \
  --nifi_url "https://of--sfsenorthamerica-jsnow-vhol-demo.snowflakecomputing.app/spcs1/nifi-api" \
  --nifi_bearer_token "<BEARER_TOKEN>" \
  --nifi_verify_ssl true
```

> Generate a bearer token via Snowflake PAT or OAuth for the Openflow service role.

## 4. Verify connectivity

```bash
venv/bin/nipyapi --profile <OPENFLOW_PROFILE> system get_nifi_version_info
```

| Result | Action |
|--------|--------|
| Returns NiFi version | Profile is ready — set `OPENFLOW_PROFILE` in `params.yaml` |
| 401/403 error | Token expired — regenerate bearer token |
| Connection refused | Runtime may be stopped — check Openflow Control Plane UI |

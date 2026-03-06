# Openflow Runtime Setup

Discover existing Openflow runtimes via SQL and create a nipyapi profile.

<!-- AI INSTRUCTIONS
IMPORTANT: Always run the SQL discovery steps (2a, 2b) FIRST.
Do NOT ask the user to deploy Openflow unless the SQL queries return empty results.
Most users already have Openflow deployed — discover it, don't assume it's missing.
-->

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
| Returns rows | Extract deployment names, continue to 2b |
| Empty result | Ask user if they have Openflow deployed — they may need to deploy via the Snowflake Control Plane UI |

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

<!-- AI INSTRUCTIONS
The nipyapi CLI `profiles resolve_profile_config` command may not work reliably in all environments.
Always create the profiles.yml file directly by writing to ~/.nipyapi/profiles.yml.
Use the template at SKILL_DIR/templates/profiles.yml as the base structure.
The bearer token is the same as the Snowflake connection password from connections.toml.
Read ~/.snowflake/connections.toml to get the password value automatically — do NOT ask the user for it.
-->

Create `~/.nipyapi/profiles.yml` directly with the NiFi URL from step 2b and the bearer token.

Template: [`templates/profiles.yml`](templates/profiles.yml)

```yaml
# ~/.nipyapi/profiles.yml
<PROFILE_NAME>:
  nifi_url: "<NIFI_API_URL>"
  nifi_bearer_token: "<BEARER_TOKEN>"
```

**How to get the values:**
- `<PROFILE_NAME>`: the runtime key from step 2b (e.g., `spcs1`, `byoc1`)
- `<NIFI_API_URL>`: constructed from `OAUTH_REDIRECT_URI` — `https://<host>/<runtime_key>/nifi-api`
- `<BEARER_TOKEN>`: the Snowflake connection `password` field from `~/.snowflake/connections.toml`

**Example** with two runtimes:

```yaml
spcs1:
  nifi_url: "https://of--<account>.snowflakecomputing.app/spcs1/nifi-api"
  nifi_bearer_token: "<SNOWFLAKE_PAT>"
byoc1:
  nifi_url: "https://<id>.openflow.<account>.<region>.aws.snowflake-customer.app/byoc1/nifi-api"
  nifi_bearer_token: "<SNOWFLAKE_PAT>"
```

```bash
mkdir -p ~/.nipyapi
cat > ~/.nipyapi/profiles.yml << 'EOF'
<PROFILE_NAME>:
  nifi_url: "<NIFI_API_URL>"
  nifi_bearer_token: "<BEARER_TOKEN>"
EOF
```

## 4. Verify connectivity

```bash
venv/bin/nipyapi --profile <OPENFLOW_PROFILE> system get_nifi_version_info
```

| Result | Action |
|--------|--------|
| Returns NiFi version | Profile is ready — set `OPENFLOW_PROFILE` in `params.yaml` |
| 401/403 error | Token expired — regenerate bearer token |
| Connection refused | Runtime may be stopped — check Openflow Control Plane UI |

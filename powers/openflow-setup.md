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

### 2c. Filter for Snowflake-managed runtimes only

Only SPCS (Snowflake-managed) runtimes are supported for this workflow. BYOC runtimes are not supported.

| URL pattern | Type | Supported |
|-------------|------|-----------|
| Host starts with `of--` | SPCS (Snowflake-managed) | Yes |
| Host contains `snowflake-customer.app` | BYOC | No — skip these |

> **AI instruction:** When presenting runtimes to the user, filter out any BYOC runtimes (host contains `snowflake-customer.app`). Only show SPCS runtimes (host starts with `of--`). If no SPCS runtimes exist, tell the user they need to deploy a Snowflake-managed Openflow runtime first via the Control Plane UI.

If no SPCS runtimes exist, deploy Openflow via the Snowflake Control Plane UI first.

## 3. Create nipyapi profile

Write the profile directly to `~/.nipyapi/profiles.yml` using the template at `templates/profiles.yml`.

Each profile needs only two fields: `nifi_url` and `nifi_bearer_token`.

**Template** (from `templates/profiles.yml`):
```yaml
<PROFILE_NAME>:
  nifi_url: "<NIFI_API_URL>"
  nifi_bearer_token: "<BEARER_TOKEN>"
```

- `<PROFILE_NAME>` — runtime key from step 2b (e.g., `spcs1`, `byoc1`)
- `<NIFI_API_URL>` — derived from `OAUTH_REDIRECT_URI`: `https://<host>/<runtime_key>/nifi-api`
- `<BEARER_TOKEN>` — either:
  - **Option 1 (recommended):** Use the `password` field from `~/.snowflake/connections.toml` for the Openflow connection (it's a Snowflake PAT that works as a bearer token)
  - **Option 2:** User provides their own token (e.g., from OAuth or a different PAT)

> **AI instruction:** Read `~/.snowflake/connections.toml`, find the connection that matches the Openflow account, and offer its `password` value as the bearer token. Ask the user: "Use the token from your `<CONNECTION_NAME>` connection, or provide a different one?"

**Example** — given this `OAUTH_REDIRECT_URI` from step 2b:
```
https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/spcs1/login/oauth2/code/snowflake-openflow
```

Write to `~/.nipyapi/profiles.yml`:
```yaml
spcs1:
  nifi_url: "https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/spcs1/nifi-api"
  nifi_bearer_token: "<BEARER_TOKEN>"
```

Multiple SPCS profiles can coexist in the same file:
```yaml
spcs1:
  nifi_url: "https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/spcs1/nifi-api"
  nifi_bearer_token: "<BEARER_TOKEN>"
spcs2:
  nifi_url: "https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/spcs2/nifi-api"
  nifi_bearer_token: "<BEARER_TOKEN>"
```

**Important:** If `~/.nipyapi/profiles.yml` already exists, check it first — append new profiles rather than overwriting.

## 4. Verify connectivity

```bash
venv/bin/nipyapi --profile <OPENFLOW_PROFILE> system get_nifi_version_info
```

| Result | Action |
|--------|--------|
| Returns NiFi version | Profile is ready — set `OPENFLOW_PROFILE` in `params.yaml` |
| 401/403 error | Token expired — regenerate bearer token |
| Connection refused | Runtime may be stopped — check Openflow Control Plane UI |

# Openflow Runtime Setup (Manual)

Minimal steps to get an Openflow runtime accessible via nipyapi.

> All `snow` and `nipyapi` commands below use the system `snow` CLI and `~/kiro-coco-venv/bin/nipyapi`.

## 1. Verify tooling

```bash
snow --version && ~/kiro-coco-venv/bin/nipyapi --help > /dev/null && echo "OK"
```

If the venv doesn't exist yet, create it first (see `SKILL.md` Prerequisites).

## 2. Discover deployments and runtimes

### 2a. Find deployments

```bash
snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW DATA PLANE INTEGRATIONS;" --format json
```

| Result | Action |
|--------|--------|
| Empty result | No Openflow deployed — deploy via the Snowflake Control Plane UI first |
| Returns rows | Extract deployment names, continue |

For each deployment, get details:

```bash
snow sql -c <SNOWFLAKE_CONNECTION> -q "DESCRIBE INTEGRATION <data_plane_integration>;" --format json
```

Extract `DATA_PLANE_ID` and `EVENT_TABLE` from the output.

### 2b. Find runtimes

```bash
snow sql -c <SNOWFLAKE_CONNECTION> -q "SHOW OPENFLOW RUNTIME INTEGRATIONS;" --format json
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
~/kiro-coco-venv/bin/nipyapi --profile <OPENFLOW_PROFILE> system get_nifi_version_info
```

| Result | Action |
|--------|--------|
| Returns NiFi version | Profile is ready — set `OPENFLOW_PROFILE` in `params.yaml` |
| 401/403 error | Token expired — regenerate bearer token |
| Connection refused | Runtime may be stopped — check Openflow Control Plane UI |

---

## 5. Create Canvas UI User (Optional)

If a Snowflake user needs to log into the Openflow canvas UI (NiFi UI) to create or manage flows, they need a dedicated non-privileged role with the correct service role grants.

> **Why non-privileged:** Snowflake's OAuth blocks privileged roles (`ACCOUNTADMIN`, `SECURITYADMIN`, `ORGADMIN`) from logging into SPCS services. The user's default role must be a regular role.

### Step 1: Discover SPCS service names

```sql
SHOW SERVICES LIKE '%OPENFLOW%' IN ACCOUNT;
```

Note the two service names — a runtime service and a data plane service. Both will have an `ALL_ENDPOINTS_USAGE` service role.

### Step 2: Create role and grant permissions

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS <CANVAS_ROLE>;

-- Canvas UI endpoint access (runtime service)
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_RUNTIME_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;

-- Data plane endpoint access
GRANT SERVICE ROLE <DB>.<SCHEMA>.<OPENFLOW_DATAPLANE_SERVICE>!ALL_ENDPOINTS_USAGE
  TO ROLE <CANVAS_ROLE>;

-- Runtime integration access
GRANT USAGE   ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION> TO ROLE <CANVAS_ROLE>;
GRANT OPERATE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION> TO ROLE <CANVAS_ROLE>;

-- Data plane integration access
GRANT USAGE ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <CANVAS_ROLE>;

-- Optional: allow ACCOUNTADMIN to manage this role
GRANT ROLE <CANVAS_ROLE> TO ROLE ACCOUNTADMIN;
```

### Step 3: Create user

```sql
CREATE USER IF NOT EXISTS <USERNAME>
  PASSWORD          = '<PASSWORD>'
  DEFAULT_ROLE      = <CANVAS_ROLE>
  MUST_CHANGE_PASSWORD = FALSE;

GRANT ROLE <CANVAS_ROLE> TO USER <USERNAME>;
```

### Step 4: Log in

The canvas URL for an SPCS runtime follows this pattern:

```
https://of--<ORG>-<ACCOUNT>.snowflakecomputing.app/<RUNTIME_KEY>/nifi/
```

Open the URL — Snowflake OAuth handles login and redirects back to the canvas.

**If OAuth blocks the login**, append `?role=<CANVAS_ROLE>` to the URL to force the correct role.

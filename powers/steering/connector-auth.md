<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->

# Openflow Connector Authentication Architecture

How the Kinesis connector authenticates to Snowflake for Snowpipe Streaming writes.
Understanding this prevents common role configuration mistakes.

---

## The Base Role

### What it is

The **base role** is the pre-existing customer role that owns the Openflow data plane
integration. When the Openflow runtime starts, it authenticates via OAuth and receives an
OIDC identity token containing this role. All Snowflake sessions from the connector are
scoped to the base role.

### Key properties (verified empirically)

- **Not auto-created by Snowflake.** It is a customer-created role that predates the
  Openflow deployment. The admin creates it and then selects it when configuring the
  deployment in the Control Plane UI.
- **May be shared across multiple deployments.** One base role can own multiple data plane
  integrations in the same account.
- **Different environments use different names.** Common names: `ADF_PL_RL`, `OPENFLOW_RL`,
  `NIFI_RL`, etc. Never hardcode a name — always discover it.

### How to discover it

```sql
SHOW OPENFLOW DATA PLANE INTEGRATIONS;
SHOW GRANTS ON INTEGRATION <data_plane_integration_name>;
-- Look for OWNERSHIP → that role is the base role
```

---

## Authentication Flow

```
Openflow Runtime
    │
    ├─ OAuth client credentials (stored in container)
    │      │
    │      ▼
    │  Snowflake OAuth Server
    │      │
    │      └─ OIDC ID token  { role: <BASE_ROLE> }
    │
    ├─ Request session token for <BASE_ROLE>
    │      │
    │      ▼
    │  Snowflake Session Manager
    │      │
    │      └─ Short-lived session token (scoped to <BASE_ROLE>)
    │
    └─ JDBC connection  authenticator=oauth&token=<session_token>&role=<BASE_ROLE>
           │
           ▼
       PutSnowpipeStreaming writes data as <BASE_ROLE>
```

---

## Why You Cannot Use an Arbitrary New Role

The session token is always scoped to the base role. The SnowflakeConnectionService `Role`
parameter must be either the base role itself or a role in its hierarchy (granted TO the
base role). An arbitrary new role not connected to the OAuth identity will be rejected.

**Attempts that fail:**
```sql
-- Fails: dpa/integration-secret/runtime-* are Snowflake-internal system users,
-- not accessible via customer SQL DDL
GRANT ROLE MY_NEW_ROLE TO USER dpa;  -- error: user does not exist or not authorized
```

**What works:**
```sql
-- Grant data privileges directly to the base role
GRANT USAGE ON DATABASE ... TO ROLE <BASE_ROLE>;
GRANT INSERT ON TABLE ...   TO ROLE <BASE_ROLE>;

-- OR grant a sub-role to the base role (advanced/production use)
GRANT ROLE MY_CONNECTOR_ROLE TO ROLE <BASE_ROLE>;
-- Then set "Snowflake Role" = MY_CONNECTOR_ROLE in the connector
```

---

## Internal Service Users (dpa, integration-secret, runtime-*)

These appear as USER grants on the base role (`SHOW GRANTS OF ROLE <BASE_ROLE>`).
They are Snowflake-internal Openflow service users, **not** related to Snowpipe Streaming
writes. They are used for control plane operations and cannot receive additional role grants
via customer SQL DDL.

---

## Canvas Role vs Base Role

| | Base Role | Canvas Role |
|---|---|---|
| **Purpose** | Snowpipe Streaming writes | Human NiFi canvas UI login |
| **Created by** | Customer, before Openflow deployment | Created during kiro-coco setup |
| **Used in** | Step 5 "Snowflake Role" connector param | Canvas login URL |
| **Discovery** | `SHOW GRANTS ON INTEGRATION → OWNERSHIP` | Named by user during setup |
| **User involvement** | None (skill handles silently) | User chooses name + password |

### What each role can access

**Base role** (`<OPENFLOW_BASE_ROLE>`) — data access only:
```sql
GRANT USAGE  ON DATABASE <DB_NAME>           TO ROLE <OPENFLOW_BASE_ROLE>;
GRANT USAGE  ON SCHEMA   <DB_NAME>.PUBLIC    TO ROLE <OPENFLOW_BASE_ROLE>;
GRANT INSERT, SELECT ON TABLE <DB_NAME>.PUBLIC.<TABLE> TO ROLE <OPENFLOW_BASE_ROLE>;
GRANT USAGE  ON WAREHOUSE <WAREHOUSE>        TO ROLE <OPENFLOW_BASE_ROLE>;
-- No canvas/SPCS access
```

**Canvas role** (`<CANVAS_ROLE>`) — UI access only:
```sql
GRANT SERVICE ROLE <DB>.<SCHEMA>.<RUNTIME_SERVICE>!ALL_ENDPOINTS_USAGE   TO ROLE <CANVAS_ROLE>;
GRANT SERVICE ROLE <DB>.<SCHEMA>.<DATAPLANE_SERVICE>!ALL_ENDPOINTS_USAGE TO ROLE <CANVAS_ROLE>;
GRANT USAGE   ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
GRANT OPERATE ON INTEGRATION <OPENFLOW_RUNTIME_INTEGRATION>   TO ROLE <CANVAS_ROLE>;
GRANT USAGE   ON INTEGRATION <OPENFLOW_DATAPLANE_INTEGRATION> TO ROLE <CANVAS_ROLE>;
-- No database, table, or warehouse access
```

**Canvas user** (`<CANVAS_USER>`):
- Default role = `<CANVAS_ROLE>`
- Can log into the NiFi canvas UI and operate flows
- Has zero access to the Snowflake data written by the connector
- Complete isolation from the data layer

---

## Practical Implications for kiro-coco

1. **Discover base role automatically** — user never needs to know its name
2. **Grant data privileges to base role** — database, schema, table, warehouse
3. **Use base role as "Snowflake Role"** in Step 5 connector parameters
4. **Canvas role is separate** — created fresh for each demo, for human UI access only
5. **No sub-role creation needed** for demos — grant directly to base role

**Advanced / production pattern** (optional):
```sql
CREATE ROLE <CONNECTOR_ROLE>;
GRANT <data privileges> TO ROLE <CONNECTOR_ROLE>;
GRANT ROLE <CONNECTOR_ROLE> TO ROLE <BASE_ROLE>;
-- Then use <CONNECTOR_ROLE> as "Snowflake Role" in Step 5
```
This achieves least-privilege isolation without touching internal service users.

# Infrastructure Services Catalog

Shared infrastructure services available to all TIM apps. These run in the k3s cluster and are consumed via ExternalSecrets + environment variables. To request access for a new app, file an inter-team comms entry to infra.

## Versioning

Each service is versioned via **git tags** in the infra repo. Tags follow the format `{service}/v{major}.{minor}.{patch}` (e.g., `redis/v1.1.0`). The version tracks the **service contract** (connection patterns, credentials, capabilities) — not the upstream software version.

- **Patch** (1.0.x): Bug fixes, config tweaks, no app changes needed
- **Minor** (1.x.0): New capabilities, new consumers onboarded, backward compatible
- **Major** (x.0.0): Breaking changes to connection patterns, credential formats, or APIs

```bash
git tag -l 'redis/*'           # list all Redis versions
git log redis/ --oneline redis/v1.0.0..redis/v1.1.0  # changelog between versions
```

## Services

### Central PostgreSQL `v1.0.0`

Shared PostgreSQL cluster for all app databases. Each app gets its own database and user.

| | Dev | Prod |
|---|---|---|
| Namespace | `postgres-dev` | `postgres-prod` |
| Pooled host | `central-db.postgres-dev:5432` | `central-db.postgres-prod:5432` |
| Direct host | `central-db-direct.postgres-dev:5433` | `central-db-direct.postgres-prod:5433` |
| TLS | Required | Required |

- **Pooled** (port 5432): PgBouncer, use with sync drivers (`psycopg2`, Prisma)
- **Direct** (port 5433): Raw PostgreSQL, use with async drivers (`asyncpg`)
- **Vault path**: `shared/db/{app}` (keys: `password`, `user`, `database`)
- **Connection string**: `postgresql+asyncpg://{user}:{password}@central-db-direct.postgres-{env}:5433/{database}`

**To onboard**: Infra creates the database, user, and Vault entry. App gets an ExternalSecret that syncs credentials into a `central-db-credentials` k8s Secret.

### Central Redis `v1.1.0`

Shared Redis for caching, pub/sub, and session storage. TLS-only, password-authenticated.

| | Dev | Prod |
|---|---|---|
| Namespace | `redis-dev` | `redis-prod` |
| Host | `central-redis.redis-dev:6379` | `central-redis.redis-prod:6379` |
| TLS | Required (`rediss://`) | Required (`rediss://`) |

- **Vault path**: `shared/redis/dev` or `shared/redis/prod` (key: `password`)
- **Connection string**: `rediss://:{password}@central-redis.redis-{env}:6379/{db}?ssl_cert_reqs=none`
- **DB index assignment**: Each app gets a dedicated index to avoid key collisions

| App | DB Index |
|-----|----------|
| truefol-compass | 0 |
| jamphoria | 2 |
| arcade | 3 |
| flights | 4 |

**tim-lib modules that use Redis**:
- `EventBus` — cross-pod pub/sub for WebSocket broadcasting
- `RedisRevocationStore` — token revocation with auto-expiry

**To onboard**: Infra assigns a DB index, adds the app namespace to the Redis NetworkPolicy, creates an ExternalSecret syncing the password into `central-redis-credentials`, and updates the Vault project policy.

Infra must also add the app namespace to `DEPENDENT_NAMESPACES` in the Redis connection watchdog — the NetworkPolicy and the watchdog are kept in step, and the watchdog can restart deployments in those namespaces when Redis client counts stay abnormally low.

## Consuming a shared credential from a generated project

This trips up every project onboarding to a shared service, because `ops-config.yaml` shows `env.secret:` as though it were a global constraint. It is not — it is only the *default*. Any individual env entry may name a different Secret:

```yaml
env:
  - { name: FLIGHTS_REDIS_PASSWORD, secret: { name: central-redis-credentials, key: REDIS_PASSWORD } }
```

The env var's `name` and the Secret's `key` are independent, so a shared Secret's bare key can arrive in the container under an app-specific prefix. That matters for anything using `env_prefix` in pydantic-settings, and it removes the temptation to copy the shared credential into the project's own Secret — a second copy is a second thing to rotate and a second thing to forget.

`secret.optional: true` is also supported. Prefer leaving it off: a required shared credential fails at startup, which is louder and safer than a silent "if configured" branch.

`envFrom: secretRef` is NOT the route for a generated project — that is the shape used by hand-written manifests (arcade), and there is no ops-config field for it.

### Vault `v1.0.0`

Centralized secrets management. Apps never store secrets in code or k8s manifests — all secrets live in Vault and are synced to k8s Secrets via External Secrets Operator.

| | |
|---|---|
| Namespace | `vault` |
| Host | `vault.vault.svc.cluster.local:8200` |
| Protocol | HTTP (in-cluster) |

- **Path layout**: `secret/projects/{app}/*` (app-owned), `secret/shared/*` (infra-owned, read-only to apps)
- **App access**: Project-scoped token in `vault-project-token` k8s Secret per namespace
- **SecretStore**: Each app namespace has a `vault-project` SecretStore CRD

**To onboard**: Infra creates a Vault policy (`project-{app}`), generates a scoped token, and deploys the SecretStore CRD in the app namespace.

### Zitadel (OIDC) `v1.0.0`

Shared OIDC identity provider for all apps. Single instance, multi-org.

| | |
|---|---|
| Issuer | `https://auth.truefol.com` |
| Protocol | OIDC / OAuth 2.0 (PKCE) |
| Login v2 | Separate container, per-org branding via org scopes |

- **Per-app setup**: OIDC app (client) in a Zitadel org, PKCE flow (no client secret)
- **Vault path**: `projects/{app}/app` (keys: `zitadel_client_id`, `zitadel_audience`, `zitadel_org_id`)
- **tim-lib modules**: `OIDCVerifier` (JWT validation), `FastAPIAuth` (FastAPI dependency)

**To onboard**: Infra creates a Zitadel org, OIDC app, and stores credentials in Vault. Apps use PKCE — no client secret needed.

### MinIO (S3 Object Storage) `v1.0.0`

S3-compatible object storage for file uploads, backups, and media.

| | |
|---|---|
| Namespace | `minio` |
| API host | `minio.minio.svc.cluster.local:9000` |
| Console | `minio.minio.svc.cluster.local:9001` |
| Protocol | HTTP (in-cluster) |

- **Vault path**: `projects/{app}/minio` or `secret/shared/minio`
- **Per-app setup**: Dedicated MinIO user + policy scoped to app buckets

**To onboard**: Infra creates a MinIO user, policy, and bucket. Credentials stored in Vault.

### Container Registry `v1.0.0`

In-cluster Docker registry for app images. No authentication (cluster-internal only).

| | |
|---|---|
| Namespace | `registry` |
| Host | `registry.registry.svc.cluster.local:5000` |
| Protocol | HTTP |

- **Usage**: ops.sh `build` pushes images here via BuildKit, `deploy` pulls from here
- **Image naming**: `registry.registry.svc.cluster.local:5000/{project}-{service}:{sha}`

**No onboarding needed** — all apps use this automatically via ops.sh build.

### BuildKit `v1.0.0`

Persistent build daemon for container image builds. Used by ops.sh, not directly by apps.

| | |
|---|---|
| Namespace | `buildkit` |
| Host | `buildkit.buildkit.svc.cluster.local:1234` |
| Protocol | gRPC |

- **GitHub PAT**: `github-pat` secret in `buildkit` namespace (for private repo clones)
- **All image builds go through BuildKit** — never build locally

**No onboarding needed** — ops.sh handles all interaction.

## Requesting Access

To consume a service in a new app:

1. File an inter-team comms entry to infra specifying which services you need
2. Infra provisions: Vault paths, ExternalSecrets, NetworkPolicy rules, per-app credentials
3. App adds the synced k8s Secret to its deployment `envFrom` or `env`
4. App reads credentials from environment variables (validated by Pydantic settings)

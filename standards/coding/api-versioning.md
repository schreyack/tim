# API Versioning Standard

This document defines API versioning requirements for all TIM projects.

## Overview

All TIM APIs must implement versioning to:

- Allow breaking changes without disrupting clients
- Support multiple API versions simultaneously during migrations
- Provide clear upgrade paths for consumers

## Versioning Strategy

### URL Path Versioning (Required)

TIM uses URL path versioning as the primary strategy.

```text
/api/v1/users
/api/v2/users
```

**Rationale**:

- Explicit and visible
- Easy to route in load balancers
- Clear in logs and debugging
- AI developers can easily identify version in code

### Version Format

```text
v{major}
```

- Major version only (v1, v2, v3)
- No minor/patch versions in URL
- Minor changes are backward-compatible (no new version needed)

## Implementation

### Python (FastAPI)

```python
from fastapi import APIRouter, FastAPI

# Create versioned routers
v1_router = APIRouter(prefix="/api/v1")
v2_router = APIRouter(prefix="/api/v2")

# Version-specific endpoints
@v1_router.get("/users/{user_id}")
async def get_user_v1(user_id: str) -> UserResponseV1:
    ...

@v2_router.get("/users/{user_id}")
async def get_user_v2(user_id: str) -> UserResponseV2:
    ...

# Mount routers
app = FastAPI()
app.include_router(v1_router)
app.include_router(v2_router)
```

### Node.js (Express)

```typescript
import { Router } from "express";

// Create versioned routers
const v1Router = Router();
const v2Router = Router();

// Version-specific endpoints
v1Router.get("/users/:id", getUserV1);
v2Router.get("/users/:id", getUserV2);

// Mount routers
app.use("/api/v1", v1Router);
app.use("/api/v2", v2Router);
```

## Version Lifecycle

### Active Versions

| Status | Description | Support Level |
|--------|-------------|---------------|
| Current | Latest version | Full support |
| Supported | Previous version(s) | Bug fixes, security patches |
| Deprecated | Scheduled for removal | Security patches only |
| Removed | No longer available | None |

### Deprecation Policy

1. **Announce deprecation** - Minimum 6 months before removal
2. **Add deprecation headers** - Warn clients in responses
3. **Monitor usage** - Track deprecated endpoint calls
4. **Communicate timeline** - Notify known consumers
5. **Remove after deadline** - Only after usage drops to acceptable level

### Deprecation Headers

```http
Deprecation: true
Sunset: Sat, 31 Dec 2025 23:59:59 GMT
Link: </api/v2/users>; rel="successor-version"
```

## Breaking vs Non-Breaking Changes

### Breaking Changes (Require New Version)

- Removing an endpoint
- Removing a required field from request
- Removing a field from response
- Changing field type
- Changing endpoint URL structure
- Changing authentication mechanism

### Non-Breaking Changes (Same Version)

- Adding new optional request fields
- Adding new response fields
- Adding new endpoints
- Adding new optional headers
- Improving error messages
- Performance improvements

## Schema Evolution

### Response Schemas

Each version should have its own response schemas:

```python
# schemas/v1/user.py
class UserResponseV1(BaseModel):
    id: str
    email: str
    name: str

# schemas/v2/user.py
class UserResponseV2(BaseModel):
    id: str
    email: str
    first_name: str  # Renamed from 'name'
    last_name: str   # New field
    profile: ProfileV2  # New nested object
```

### Mapping Between Versions

When multiple versions exist, create explicit mappers:

```python
def user_to_v1(user: User) -> UserResponseV1:
    return UserResponseV1(
        id=str(user.id),
        email=user.email,
        name=f"{user.first_name} {user.last_name}",
    )

def user_to_v2(user: User) -> UserResponseV2:
    return UserResponseV2(
        id=str(user.id),
        email=user.email,
        first_name=user.first_name,
        last_name=user.last_name,
        profile=profile_to_v2(user.profile),
    )
```

## Documentation

### OpenAPI/Swagger

Each version must have separate OpenAPI specs:

```text
/docs/v1  →  OpenAPI spec for v1
/docs/v2  →  OpenAPI spec for v2
```

### Version in Response

Include API version in all responses:

```json
{
  "data": { ... },
  "meta": {
    "api_version": "v2"
  }
}
```

## Routing Rules

### Load Balancer Configuration

```yaml
# Example: nginx configuration
location /api/v1/ {
    proxy_pass http://api-v1-service/;
}

location /api/v2/ {
    proxy_pass http://api-v2-service/;
}
```

### Version Routing Middleware

```python
from fastapi import Request

async def version_middleware(request: Request, call_next):
    version = request.url.path.split("/")[2]  # Extract v1, v2, etc.
    request.state.api_version = version
    return await call_next(request)
```

## Testing Requirements

### Version-Specific Tests

Each version needs its own test suite:

```text
tests/
├── v1/
│   ├── test_users_api_v1.py
│   └── test_auth_api_v1.py
└── v2/
    ├── test_users_api_v2.py
    └── test_auth_api_v2.py
```

### Backward Compatibility Tests

When adding v2, also add tests ensuring v1 still works:

```python
class TestV1BackwardCompatibility:
    """Ensure v1 behavior unchanged after v2 release."""

    async def test_v1_user_response_format_unchanged(self, client):
        response = await client.get("/api/v1/users/123")
        assert "name" in response.json()  # v1 has 'name'
        assert "first_name" not in response.json()  # v1 doesn't have 'first_name'
```

## Maximum Supported Versions

- **Maximum active versions**: 2 (current + 1 supported)
- **Deprecation period**: 6 months minimum
- **Removal deadline**: After deprecation period + usage threshold met

## Pattern Registration

Register API versioning in `.tim-patterns.yaml`:

```yaml
patterns:
  api_versioning:
    standard: "url-path"
    reference: "standards/coding/api-versioning.md"
    implemented: true
    current_version: "v2"
    supported_versions: ["v1", "v2"]
    deprecated_versions: []
```

## See Also

- [Python Standard](python.md)
- [TypeScript Standard](typescript.md)
- [Gates](../enforcement/gates.md)

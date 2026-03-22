# Auth Integration Guide

tim-lib provides OIDC authentication for FastAPI backends and Next.js frontends, backed by Zitadel as the identity provider. Token revocation, email verification, and OIDC sign-out are built in.

## Prerequisites

- Zitadel instance with a project and OIDC application configured
- Redis (for token revocation — optional but recommended)
- `tim-lib` installed (Python) and `@timlib/lib` installed (Node)

## Backend (FastAPI)

### 1. Install tim-lib with Redis support

```bash
pip install tim-lib[redis]
```

### 2. Create your User model

tim-lib doesn't own your User model. Your model must satisfy the `AuthUser` protocol:

```python
# models/user.py
from sqlalchemy.orm import Mapped, mapped_column
from tim_lib.db import Base

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    auth_id: Mapped[str] = mapped_column(unique=True)       # OIDC subject ID
    email: Mapped[str] = mapped_column(unique=True)
    display_name: Mapped[str]
    avatar_url: Mapped[str | None] = mapped_column(default=None)
    role: Mapped[str] = mapped_column(default="user")
    is_active: Mapped[bool] = mapped_column(default=True)    # Required by AuthUser
    deleted_at: Mapped[datetime | None] = mapped_column(default=None)
```

The `AuthUser` protocol requires three properties: `auth_id`, `email`, `is_active`. Add whatever other fields your project needs.

### 3. Write the two callbacks

These tell tim-lib how to load and create users in your database:

```python
# services/auth_service.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import User

async def lookup_user(session: AsyncSession, auth_id: str) -> User | None:
    """Load a non-deleted user by auth_id. Returns None if not found."""
    result = await session.execute(
        select(User).where(User.auth_id == auth_id, User.deleted_at.is_(None))
    )
    return result.scalar_one_or_none()


async def create_user(db: AsyncSession, claims: dict) -> User:
    """Create a user from JWT claims. Called on first login."""
    user = User(
        auth_id=claims["sub"],
        email=claims.get("email", ""),
        display_name=claims.get("name", claims.get("email", "User")),
        avatar_url=claims.get("picture"),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user
```

**That's the only project-specific code.** Customize `create_user` for your schema — add org assignment, default permissions, welcome emails, whatever your project needs.

#### Userinfo fallback

If your OIDC provider doesn't always include `email` in the JWT (Zitadel sometimes omits it), fetch it from the userinfo endpoint. The raw token is available as `claims["__token__"]` inside `create_user`:

```python
async def create_user(db: AsyncSession, claims: dict) -> User:
    email = claims.get("email")
    if not email:
        # __token__ is injected by FastAPIAuth, cleaned up automatically
        token = claims.get("__token__")
        if token:
            info = await fetch_userinfo(token)  # your Zitadel userinfo call
            email = info.get("email")
    # ... create user with email
```

### 4. Wire it up in deps.py

```python
# deps.py
from tim_lib.oidc import OIDCVerifier
from tim_lib.revocation import RedisRevocationStore
from tim_lib.auth_fastapi import FastAPIAuth
from app.services.auth_service import lookup_user, create_user
from app.config import settings

oidc = OIDCVerifier(
    issuer_url=settings.zitadel_issuer_url,
    audience=settings.zitadel_project_id,
)

revocation = RedisRevocationStore(redis_url=settings.redis_url)

auth = FastAPIAuth(
    verifier=oidc,
    user_loader=lookup_user,
    user_creator=create_user,
    revocation_store=revocation,        # omit if you don't need revocation
    admin_check=lambda u: u.is_admin,   # omit if you don't have admin roles
    email_verified_required=True,       # reject unverified emails (default)
)
```

### 5. Add FastAPI dependencies

```python
# deps.py (continued)
from typing import Annotated, Optional
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession

security = HTTPBearer(auto_error=False)

async def get_current_user(
    credentials: Annotated[Optional[HTTPAuthorizationCredentials], Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return await auth.authenticate(credentials.credentials, db)

async def get_current_user_optional(
    credentials: Annotated[Optional[HTTPAuthorizationCredentials], Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User | None:
    if credentials is None:
        return None
    return await auth.authenticate(credentials.credentials, db)

async def get_current_admin(
    user: Annotated[User, Depends(get_current_user)],
) -> User:
    return auth.check_admin(user)

# Type aliases for clean endpoint signatures
CurrentUser = Annotated[User, Depends(get_current_user)]
OptionalCurrentUser = Annotated[User | None, Depends(get_current_user_optional)]
CurrentAdmin = Annotated[User, Depends(get_current_admin)]
```

### 6. Use in endpoints

```python
@router.get("/me")
async def get_me(user: CurrentUser):
    return {"id": user.id, "email": user.email}

@router.get("/feed")
async def get_feed(user: OptionalCurrentUser):
    # user is None if no token provided
    ...

@router.delete("/users/{id}")
async def delete_user(id: int, admin: CurrentAdmin):
    ...
```

### 7. Clean up on shutdown

Wire `revocation.close()` into your FastAPI lifespan:

```python
# main.py
from app.deps import revocation

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await revocation.close()
```

### 8. WebSocket / streaming auth

WebSocket and streaming endpoints can't use FastAPI's `Depends()`. Use `oidc.verify_token()` directly:

```python
from app.deps import oidc
from tim_lib.oidc import OIDCVerificationError

async def authenticate_ws(websocket: WebSocket):
    data = await websocket.receive_json()
    try:
        claims = await oidc.verify_token(data["token"])
    except OIDCVerificationError:
        await websocket.close(code=4001)
        return None
    return claims
```

## Frontend (Next.js)

### 1. Install @timlib/lib

```bash
npm install @timlib/lib
```

### 2. Configure auth.ts

```typescript
// src/auth.ts
import NextAuth from "next-auth";
import { createZitadelAuthConfig } from "@timlib/lib/auth";

const config = createZitadelAuthConfig({
  issuerUrl: process.env.ZITADEL_ISSUER_URL!,
  clientId: process.env.ZITADEL_CLIENT_ID!,
  projectId: process.env.ZITADEL_PROJECT_ID!,
});

export const { auth, handlers, signIn, signOut } = NextAuth(config);
```

This gives you PKCE, JWT/session callbacks, and automatic token refresh.

### 3. Configure middleware.ts

```typescript
// src/middleware.ts
import { auth } from "@/auth";
import { createAuthMiddleware } from "@timlib/lib/auth";

const { handler } = createAuthMiddleware({
  publicRoutes: ["/", "/about", "/signin"],
});

export default auth((req) => handler(req));
export const config = {
  matcher: ["/((?!api/auth|_next/static|_next/image|favicon.ico|api/).*)"],
};
```

### 4. Add the Auth.js API route

```typescript
// src/app/api/auth/[...nextauth]/route.ts
import { handlers } from "@/auth";
export const { GET, POST } = handlers;
```

### 5. OIDC sign-out

For client components that need to trigger Zitadel sign-out (not just Next.js session clear):

```typescript
// In any "use client" component
import { buildOidcSignOutUrl } from "@timlib/lib/auth-client";

function handleSignOut(idToken: string) {
  const url = buildOidcSignOutUrl(
    process.env.NEXT_PUBLIC_ZITADEL_ISSUER_URL!,
    idToken,
    `${window.location.origin}/api/auth/post-logout`,
  );
  window.location.href = url;
}
```

Note: import from `@timlib/lib/auth-client` (not `auth`) — the client module has no server dependencies and is safe for "use client" components.

## Frontend UI Patterns

tim-lib handles the auth plumbing. You still build your own UI pages. Here are the common patterns.

### Sign-in page

Zitadel handles the actual login form (PKCE redirect). Your sign-in page just triggers it:

```typescript
// src/app/signin/page.tsx
import { signIn } from "@/auth";

export default function SignInPage() {
  return (
    <form
      action={async () => {
        "use server";
        await signIn("zitadel");
      }}
    >
      <button type="submit">Sign in</button>
    </form>
  );
}
```

### Auth error page

Auth.js redirects here on failures. Show the error and a retry link:

```typescript
// src/app/auth/error/page.tsx
export default function AuthErrorPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  return (
    <div>
      <h1>Authentication Error</h1>
      <p>{searchParams.error ?? "Something went wrong"}</p>
      <a href="/signin">Try again</a>
    </div>
  );
}
```

### Session-aware navigation

Access the session in a server component, pass tokens to a client component for sign-out:

```typescript
// src/components/NavAuth.tsx (server wrapper)
import { auth } from "@/auth";
import { NavAuthClient } from "./NavAuthClient";

export async function NavAuth() {
  const session = await auth();
  if (!session?.user) return <a href="/signin">Sign in</a>;
  return <NavAuthClient session={session} />;
}
```

```typescript
// src/components/NavAuthClient.tsx (client component)
"use client";

import { buildOidcSignOutUrl } from "@timlib/lib/auth-client";

export function NavAuthClient({ session }: { session: any }) {
  const handleSignOut = async () => {
    // 1. Clear the Next.js session
    await fetch("/api/auth/signout", { method: "POST" });
    // 2. Clear the Zitadel session (full OIDC sign-out)
    const url = buildOidcSignOutUrl(
      process.env.NEXT_PUBLIC_ZITADEL_ISSUER_URL!,
      session.idToken,
      `${window.location.origin}/api/auth/post-logout`,
    );
    window.location.href = url;
  };

  return (
    <div>
      <span>{session.user.name}</span>
      {session.user.image && <img src={session.user.image} alt="" />}
      <button onClick={handleSignOut}>Sign out</button>
    </div>
  );
}
```

### Post-logout callback

Zitadel redirects here after OIDC sign-out. Clear any remaining session state and redirect home:

```typescript
// src/app/api/auth/post-logout/route.ts
import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.redirect(new URL("/", process.env.AUTH_URL!));
}
```

### Accessing the session

**Server components** — use `auth()` directly:

```typescript
import { auth } from "@/auth";

export default async function DashboardPage() {
  const session = await auth();
  if (!session) redirect("/signin");
  // session.user.id, session.accessToken, session.idToken
}
```

**Client components** — pass the session as a prop from a server parent, or use Auth.js `SessionProvider`:

```typescript
// layout.tsx (server)
import { auth } from "@/auth";
import { SessionProvider } from "next-auth/react";

export default async function Layout({ children }) {
  const session = await auth();
  return <SessionProvider session={session}>{children}</SessionProvider>;
}

// any-client-component.tsx
"use client";
import { useSession } from "next-auth/react";

function UserGreeting() {
  const { data: session } = useSession();
  return <p>Hello {session?.user?.name}</p>;
}
```

**API routes** — use `auth()` as middleware:

```typescript
import { auth } from "@/auth";

export const GET = auth(async (req) => {
  if (!req.auth) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json({ user: req.auth.user });
});
```

### Account deletion with sign-out

Full flow: confirm deletion, call backend, then sign out of both Next.js and Zitadel:

```typescript
"use client";

import { buildOidcSignOutUrl } from "@timlib/lib/auth-client";

async function handleDeleteAccount(session: any) {
  const res = await fetch("/api/v1/auth/me", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.accessToken}`,
    },
    body: JSON.stringify({ confirmation: "DELETE" }),
  });

  if (!res.ok) throw new Error("Deletion failed");

  // Sign out after deletion
  const url = buildOidcSignOutUrl(
    process.env.NEXT_PUBLIC_ZITADEL_ISSUER_URL!,
    session.idToken,
    `${window.location.origin}/api/auth/post-logout`,
  );
  window.location.href = url;
}
```

### Sign-out: why two steps?

Calling `signOut()` from Auth.js only clears the **Next.js session cookie**. The user is still logged in at **Zitadel**. If they visit your app again, Zitadel silently re-issues tokens and they're logged back in.

To fully sign out, you need both:
1. Clear the Next.js session (`/api/auth/signout`)
2. Redirect to Zitadel's `end_session` endpoint (`buildOidcSignOutUrl`)

The `id_token_hint` parameter tells Zitadel which session to destroy. Without it, Zitadel shows a "which account?" prompt.

## Environment Variables

### Backend

| Variable | Description |
|----------|-------------|
| `ZITADEL_ISSUER_URL` | Zitadel issuer (e.g. `https://auth.example.com`) |
| `ZITADEL_PROJECT_ID` | Zitadel project ID (used as JWT audience) |
| `ZITADEL_API_URL` | Zitadel API base URL (for admin operations) |
| `ZITADEL_API_TOKEN` | Service account token (for user deletion/lookup) |
| `REDIS_URL` | Redis connection URL (for revocation store) |

### Frontend

| Variable | Description |
|----------|-------------|
| `ZITADEL_ISSUER_URL` | Same as backend |
| `ZITADEL_CLIENT_ID` | OIDC client ID from Zitadel |
| `ZITADEL_PROJECT_ID` | Same as backend |
| `AUTH_SECRET` | Auth.js session encryption secret |
| `AUTH_URL` | Public URL of the app (e.g. `https://myapp.example.com`) |
| `AUTH_TRUST_HOST` | Set to `true` behind reverse proxy |
| `NEXT_PUBLIC_ZITADEL_ISSUER_URL` | Client-side issuer URL (for sign-out) |

## Token Revocation

Revocation is optional but recommended. It closes the window where a deleted user's JWT remains valid until expiry (up to 1 hour with Zitadel's default).

```python
# Revoke a user's auth_id (e.g. after account deletion)
await revocation.revoke(user.auth_id, ttl_seconds=7200)
```

- **Fail-open design:** if Redis is down, requests pass through. JWT expiry is the hard boundary.
- **TTL must exceed token lifetime.** Default 7200s (2 hours) covers Zitadel's 1-hour access tokens. If you change Zitadel's token lifetime, update the TTL.
- **No revocation without Redis.** Omit `revocation_store` from `FastAPIAuth` if you don't have Redis — auth still works, just without revocation.

## Authentication Flow

```
Request with Bearer token
         │
         ▼
   OIDCVerifier.verify_token()     ← JWKS validation (cached 1hr)
         │
         ▼
   Email verified?                 ← 403 if explicitly False
         │
         ▼
   RevocationStore.is_revoked()?   ← 401 if revoked (fail-open on Redis error)
         │
         ▼
   user_loader(db, auth_id)        ← Your callback: find user in DB
         │
    found? ──yes──▶ check is_active ──▶ return user
         │
        no
         │
         ▼
   user_creator(db, claims)        ← Your callback: create user in DB
         │
         ▼
   check is_active ──▶ return user
```

## API Reference

### Python — `tim_lib.oidc`

| Symbol | Description |
|--------|-------------|
| `OIDCVerifier(issuer_url, audience?, jwks_path?, algorithms?)` | JWKS-based JWT verifier |
| `OIDCVerifier.verify_token(token) -> dict` | Verify and decode JWT (async) |
| `OIDCVerifier.reset_jwks_cache()` | Force JWKS re-fetch on next call |
| `AuthUser` | Protocol: `auth_id`, `email`, `is_active` properties |
| `OIDCVerificationError(message, code)` | Base verification error |
| `TokenExpiredError` | JWT expired (code: `token_expired`) |
| `InvalidTokenError` | Bad JWT or JWKS unreachable (code: `invalid_token`) |

### Python — `tim_lib.revocation`

| Symbol | Description |
|--------|-------------|
| `RevocationStore` | Protocol: `is_revoked(auth_id)`, `revoke(auth_id, ttl)` |
| `RedisRevocationStore(redis_url, key_prefix?)` | Redis-backed implementation |
| `RedisRevocationStore.close()` | Shut down connection pool |

### Python — `tim_lib.auth_fastapi`

| Symbol | Description |
|--------|-------------|
| `FastAPIAuth(verifier, user_loader, user_creator, ...)` | Auth orchestrator |
| `FastAPIAuth.authenticate(token, db) -> AuthUser` | Full auth flow |
| `FastAPIAuth.check_admin(user) -> AuthUser` | Admin gate (raises 403) |

### TypeScript — `@timlib/lib/auth`

| Symbol | Description |
|--------|-------------|
| `createZitadelAuthConfig(config) -> NextAuthConfig` | Zitadel OIDC config with PKCE + token refresh |
| `createAuthMiddleware({ publicRoutes }) -> { handler, config }` | Route protection middleware |
| `ZitadelAuthConfig` | Config interface |
| `ZitadelSession` | Session type with tokens |
| `ZitadelJWT` | JWT type with tokens |

### TypeScript — `@timlib/lib/auth-client`

| Symbol | Description |
|--------|-------------|
| `buildOidcSignOutUrl(issuerUrl, idToken, postLogoutUri) -> string` | OIDC end_session URL builder |

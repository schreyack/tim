"""TIM FastAPI Auth Integration Module.

Callback-based, ORM-agnostic authentication for FastAPI applications.
Combines OIDC verification, revocation checking, and user loading
into a single authenticate() flow.

Example:
    from tim_lib.oidc import OIDCVerifier
    from tim_lib.revocation import RedisRevocationStore
    from tim_lib.auth_fastapi import FastAPIAuth

    verifier = OIDCVerifier(issuer_url="https://auth.example.com")
    store = RedisRevocationStore(redis_url="redis://localhost:6379/0")
    auth = FastAPIAuth(
        verifier=verifier,
        user_loader=lookup_user_by_auth_id,
        user_creator=create_user_from_claims,
        revocation_store=store,
    )
    user = await auth.authenticate(token, db)
"""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi import HTTPException, status

from tim_lib.oidc import AuthUser, OIDCVerificationError, OIDCVerifier
from tim_lib.revocation import RevocationStore


logger = logging.getLogger(__name__)


class FastAPIAuth:
    """FastAPI authentication orchestrator.

    Methods are not FastAPI dependencies themselves; they're called from
    thin wrapper dependencies in the app's deps.py. This avoids complex
    FastAPI DI coupling in the shared library.

    Args:
        verifier: OIDC token verifier instance.
        user_loader: Async callback to load a user by auth_id.
            Signature: (db_session, auth_id) -> AuthUser | None.
        user_creator: Async callback to create a user from JWT claims.
            Signature: (db_session, claims_dict) -> AuthUser.
        revocation_store: Optional revocation backend. If None, revocation
            checking is skipped.
        admin_check: Optional callback to check admin status. Called by
            check_admin(). Signature: (user) -> bool.
        email_verified_required: If True, reject tokens where
            email_verified is explicitly False. Missing claim is allowed
            (some providers don't include it).
    """

    def __init__(
        self,
        verifier: OIDCVerifier,
        user_loader: Callable[[Any, str], Awaitable[AuthUser | None]],
        user_creator: Callable[[Any, dict[str, Any]], Awaitable[AuthUser]],
        revocation_store: RevocationStore | None = None,
        admin_check: Callable[[Any], bool] | None = None,
        email_verified_required: bool = True,
    ) -> None:
        self._verifier = verifier
        self._user_loader = user_loader
        self._user_creator = user_creator
        self._revocation_store = revocation_store
        self._admin_check = admin_check
        self._email_verified_required = email_verified_required

    async def authenticate(self, token: str, db: Any) -> AuthUser:
        """Full authentication flow: verify, check revocation, load/create user.

        Flow:
        1. Verify JWT via OIDC/JWKS -> claims
        2. Check email_verified if required (reject explicit False -> 403)
        3. Check revocation store if configured (revoked -> 401)
        4. Load user by auth_id from claims["sub"]
        5. If user not found, create via user_creator callback
        6. Check user.is_active (inactive -> 401)
        7. Return authenticated user

        Args:
            token: Raw JWT string from Authorization header.
            db: Database session (passed to user_loader/user_creator callbacks).

        Returns:
            Authenticated user satisfying the AuthUser protocol.

        Raises:
            HTTPException: 401 for auth failures, 403 for email not verified.
        """
        claims = await self._verify_and_check(token)
        user = await self._load_or_create_user(db, claims, token)
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account is deactivated",
            )
        return user

    async def _verify_and_check(self, token: str) -> dict[str, Any]:
        """Verify token, check email verification and revocation."""
        try:
            claims = await self._verifier.verify_token(token)
        except OIDCVerificationError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=str(exc),
            ) from exc

        if self._email_verified_required and claims.get("email_verified") is False:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email address not verified",
            )

        if self._revocation_store is not None:
            sub = claims.get("sub", "")
            if await self._revocation_store.is_revoked(sub):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Account has been revoked",
                )

        return claims

    async def _load_or_create_user(
        self, db: Any, claims: dict[str, Any], token: str
    ) -> AuthUser:
        """Load existing user or create a new one from claims."""
        sub: str = claims.get("sub", "")
        user = await self._user_loader(db, sub)
        if user is not None:
            return user

        claims["__token__"] = token
        try:
            user = await self._user_creator(db, claims)
        finally:
            claims.pop("__token__", None)
        return user

    def check_admin(self, user: AuthUser) -> AuthUser:
        """Verify user has admin privileges.

        Args:
            user: Authenticated user to check.

        Returns:
            The same user if admin check passes.

        Raises:
            HTTPException: 403 if user is not an admin or no admin_check
                callback is configured.
        """
        if self._admin_check is None or not self._admin_check(user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin access required",
            )
        return user

"""TIM OIDC JWT Verification Module.

Provider-agnostic OIDC JWT verification via JWKS endpoint.
No Redis, SQLAlchemy, or FastAPI dependency — pure JWT verification.

Naming note: security.py has verify_token() for symmetric-key (HS256) JWTs.
This module handles asymmetric OIDC provider tokens via JWKS.

Example:
    from tim_lib.oidc import OIDCVerifier

    verifier = OIDCVerifier(
        issuer_url="https://auth.example.com",
        audience="my-project-id",
    )
    claims = await verifier.verify_token(token)
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Protocol, runtime_checkable

import jwt
from jwt import PyJWKClient, PyJWKClientConnectionError, PyJWKClientError


logger = logging.getLogger(__name__)


@runtime_checkable
class AuthUser(Protocol):
    """Structural type for user models.

    Apps provide their own User model; tim-lib type-checks structurally.
    """

    @property
    def auth_id(self) -> str: ...

    @property
    def email(self) -> str: ...

    @property
    def is_active(self) -> bool: ...


class OIDCVerificationError(Exception):
    """Base exception for OIDC verification failures.

    Attributes:
        code: Machine-readable error code for programmatic handling.
    """

    def __init__(self, message: str, code: str) -> None:
        super().__init__(message)
        self.code = code


class TokenExpiredError(OIDCVerificationError):
    """Raised when a JWT has expired."""

    def __init__(self, message: str = "Token has expired") -> None:
        super().__init__(message, code="token_expired")


class InvalidTokenError(OIDCVerificationError):
    """Raised when a JWT is malformed, has invalid signature, or JWKS fetch fails."""

    def __init__(self, message: str = "Invalid token") -> None:
        super().__init__(message, code="invalid_token")


class OIDCVerifier:
    """OIDC JWT verification via JWKS endpoint.

    Class-based to support multiple providers per app. JWKS keys are cached
    in memory by PyJWKClient with a configurable lifespan.

    Args:
        issuer_url: OIDC issuer URL (e.g. "https://auth.example.com").
        audience: Expected audience claim. If None, audience is not validated.
        jwks_path: Path to JWKS endpoint. Zitadel: "/oauth/v2/keys",
            Auth0: "/.well-known/jwks.json".
        algorithms: JWT algorithms to accept. Defaults to ["RS256"].
    """

    def __init__(
        self,
        issuer_url: str,
        audience: str | None = None,
        jwks_path: str = "/oauth/v2/keys",
        algorithms: list[str] | None = None,
    ) -> None:
        self._issuer_url = issuer_url.rstrip("/")
        self._audience = audience
        self._algorithms = algorithms or ["RS256"]
        self._jwks_url = f"{self._issuer_url}{jwks_path}"
        self._jwks_client = PyJWKClient(self._jwks_url, lifespan=3600)

    async def verify_token(self, token: str) -> dict[str, Any]:
        """Verify and decode an OIDC JWT.

        Fetches the signing key via JWKS (cached, refreshed hourly).
        Validates issuer claim. Validates audience if configured.

        Args:
            token: Raw JWT string from Authorization header.

        Returns:
            Decoded JWT claims dictionary.

        Raises:
            TokenExpiredError: If the JWT has expired.
            InvalidTokenError: If the JWT is malformed, signature is invalid,
                issuer doesn't match, or JWKS endpoint is unreachable.
        """
        loop = asyncio.get_running_loop()
        try:
            signing_key = await loop.run_in_executor(
                None, self._jwks_client.get_signing_key_from_jwt, token
            )
        except (PyJWKClientConnectionError, PyJWKClientError) as exc:
            logger.warning("jwks_fetch_failed", exc_info=exc)
            raise InvalidTokenError(f"JWKS fetch failed: {exc}") from exc

        decode_options: dict[str, Any] = {
            "issuer": self._issuer_url,
        }
        if self._audience is not None:
            decode_options["audience"] = self._audience

        try:
            payload: dict[str, Any] = jwt.decode(
                token,
                signing_key.key,
                algorithms=self._algorithms,
                **decode_options,
            )
        except jwt.ExpiredSignatureError as exc:
            raise TokenExpiredError() from exc
        except jwt.InvalidTokenError as exc:
            raise InvalidTokenError(str(exc)) from exc

        return payload

    def reset_jwks_cache(self) -> None:
        """Reset the internal JWKS key cache.

        Forces a fresh fetch on the next verify_token call.
        """
        self._jwks_client = PyJWKClient(self._jwks_url, lifespan=3600)

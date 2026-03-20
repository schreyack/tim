/**
 * TIM Shared Auth Module (Client)
 *
 * Client-safe auth utilities with no server dependencies.
 * Safe to import from "use client" React components.
 *
 * @example
 * import { buildOidcSignOutUrl } from "@tim/lib/auth-client";
 *
 * const url = buildOidcSignOutUrl(issuerUrl, idToken, postLogoutUri);
 * window.location.href = url;
 */

/**
 * Build a Zitadel OIDC end_session URL for sign-out.
 *
 * Constructs the provider sign-out URL with id_token_hint for proper
 * session termination. The post_logout_redirect_uri tells Zitadel
 * where to redirect after the session is destroyed.
 *
 * @param issuerUrl - Zitadel issuer URL (e.g. "https://auth.example.com")
 * @param idToken - The user's current ID token from the session
 * @param postLogoutUri - Full URI to redirect to after sign-out
 * @returns The complete end_session URL to redirect the browser to
 */
export function buildOidcSignOutUrl(
  issuerUrl: string,
  idToken: string,
  postLogoutUri: string,
): string {
  return `${issuerUrl}/oidc/v1/end_session?id_token_hint=${idToken}&post_logout_redirect_uri=${encodeURIComponent(postLogoutUri)}`;
}

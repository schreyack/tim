/**
 * TIM Shared Auth Module (Server)
 *
 * Provides Zitadel OIDC integration for Next.js applications using Auth.js v5.
 * Server-only — do not import from "use client" components.
 *
 * @example
 * import { createZitadelAuthConfig, createAuthMiddleware } from "@tim/lib/auth";
 *
 * const config = createZitadelAuthConfig({ issuerUrl, clientId, projectId });
 * export const { auth, handlers, signIn, signOut } = NextAuth(config);
 */

import type { NextAuthConfig, Session } from "next-auth";
import type { JWT } from "next-auth/jwt";


/** Configuration for Zitadel OIDC auth. */
export interface ZitadelAuthConfig {
  /** Zitadel issuer URL (e.g. "https://auth.example.com"). */
  issuerUrl: string;
  /** Zitadel OIDC client ID. */
  clientId: string;
  /** Zitadel project ID — used in audience scope. */
  projectId: string;
  /** Path for post-logout redirect. Defaults to "/api/auth/post-logout". */
  postLogoutRedirectPath?: string;
  /** Sign-in page path. Defaults to "/signin". */
  signInPage?: string;
}

/** Auth.js session shape with Zitadel tokens. */
export interface ZitadelSession {
  accessToken: string;
  idToken: string;
  error?: "RefreshAccessTokenError";
  user: {
    id: string;
    name?: string | null;
    email?: string | null;
    image?: string | null;
  };
}

/** Auth.js JWT shape with Zitadel tokens. */
export interface ZitadelJWT {
  accessToken: string;
  refreshToken: string;
  idToken: string;
  expires_at: number;
  error?: "RefreshAccessTokenError";
}

/** Request shape provided by Auth.js auth() wrapper. */
export interface AuthMiddlewareRequest {
  auth?: {
    user?: { id?: string };
    error?: string;
  } | null;
  nextUrl: URL;
  url: string;
}

async function refreshAccessToken(
  token: JWT,
  issuerUrl: string,
  clientId: string,
): Promise<JWT> {
  try {
    const tokenUrl = `${issuerUrl}/oauth/v2/token`;
    const response = await fetch(tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        client_id: clientId,
        refresh_token: token.refreshToken as string,
      }),
    });

    if (!response.ok) {
      return { ...token, error: "RefreshAccessTokenError" as const };
    }

    const data = (await response.json()) as Record<string, unknown>;

    return {
      ...token,
      accessToken: data.access_token as string,
      refreshToken:
        typeof data.refresh_token === "string"
          ? data.refresh_token
          : (token.refreshToken as string),
      idToken:
        typeof data.id_token === "string"
          ? data.id_token
          : (token.idToken as string),
      expires_at:
        Math.floor(Date.now() / 1000) + (data.expires_in as number),
      error: undefined,
    };
  } catch {
    return { ...token, error: "RefreshAccessTokenError" as const };
  }
}

function buildZitadelProvider(config: ZitadelAuthConfig): NextAuthConfig["providers"][number] {
  return {
    id: "zitadel",
    name: "Zitadel",
    type: "oidc",
    issuer: config.issuerUrl,
    clientId: config.clientId,
    clientSecret: "",
    authorization: {
      params: {
        scope: `openid profile email offline_access urn:zitadel:iam:org:project:id:${config.projectId}:aud`,
        code_challenge_method: "S256",
      },
    },
    checks: ["pkce"],
  };
}

function buildAuthCallbacks(
  config: ZitadelAuthConfig,
): NonNullable<NextAuthConfig["callbacks"]> {
  return {
    jwt({ token, account }: { token: JWT; account?: Record<string, unknown> | null }) {
      if (account) {
        token.accessToken = account.access_token as string;
        token.refreshToken = account.refresh_token as string;
        token.idToken = account.id_token as string;
        token.expires_at = account.expires_at as number;
        return token;
      }

      if (Date.now() < (token.expires_at as number) * 1000 - 60_000) {
        return token;
      }

      return refreshAccessToken(token, config.issuerUrl, config.clientId);
    },
    session({ session, token }: { session: Session; token: JWT }) {
      const s = session as unknown as ZitadelSession;
      s.accessToken = token.accessToken as string;
      s.idToken = token.idToken as string;
      s.user.id = token.sub as string;
      if (token.error) {
        s.error = token.error as "RefreshAccessTokenError";
      }
      return session;
    },
  };
}

/**
 * Create a NextAuthConfig pre-configured for Zitadel OIDC with PKCE.
 *
 * Includes JWT/session callbacks with automatic token refresh.
 * The caller passes the result to NextAuth():
 *
 * ```ts
 * const config = createZitadelAuthConfig({ issuerUrl, clientId, projectId });
 * export const { auth, handlers, signIn, signOut } = NextAuth(config);
 * ```
 */
export function createZitadelAuthConfig(config: ZitadelAuthConfig): NextAuthConfig {
  return {
    providers: [buildZitadelProvider(config)],
    pages: {
      signIn: config.signInPage ?? "/signin",
      error: "/auth/error",
    },
    session: { strategy: "jwt" },
    callbacks: buildAuthCallbacks(config),
  };
}

/**
 * Create a Next.js auth middleware handler that protects routes.
 *
 * Public routes bypass auth. All other matched routes redirect unauthenticated
 * users to the sign-in page.
 *
 * Returns a handler and the Next.js matcher config. The consumer wraps the
 * handler with NextAuth's auth() to inject session data:
 * ```ts
 * const { handler, config } = createAuthMiddleware({ publicRoutes });
 * export default auth((req) => handler(req));
 * export { config };
 * ```
 */
export function createAuthMiddleware(options: {
  publicRoutes: string[];
}): {
  handler: (req: AuthMiddlewareRequest) => Response | undefined;
  config: { matcher: string[] };
} {
  const handler = (req: AuthMiddlewareRequest): Response | undefined => {
    const { pathname } = req.nextUrl;
    const isPublic = options.publicRoutes.some(
      (r) => pathname === r || pathname.startsWith(r + "/"),
    );
    const needsAuth =
      !req.auth?.user?.id || req.auth?.error === "RefreshAccessTokenError";

    if (needsAuth && !isPublic) {
      return Response.redirect(
        new URL(
          "/api/auth/signin?callbackUrl=" + encodeURIComponent(req.url),
          req.url,
        ).toString(),
        302,
      );
    }
    return undefined;
  };

  return {
    handler,
    config: {
      matcher: [
        "/((?!api/auth|_next/static|_next/image|favicon.ico|api/).*)",
      ],
    },
  };
}

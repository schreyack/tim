# Security Headers

All TIM applications must include these HTTP security headers on every response. Missing headers block deployment.

## Required Headers

### Content-Security-Policy (CSP)

Controls resources the browser can load.

```text
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://api.stripe.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'
```

**Directives**:

- `default-src 'self'` - Only load from same origin by default
- `script-src 'self'` - Scripts only from same origin (no inline)
- `style-src 'self' 'unsafe-inline'` - Styles from same origin + inline (for frameworks)
- `img-src 'self' data: https:` - Images from same origin, data URIs, or HTTPS
- `connect-src 'self'` - XHR/fetch only to same origin + allowed APIs
- `frame-ancestors 'none'` - Cannot be embedded in frames
- `base-uri 'self'` - Restrict base tag
- `form-action 'self'` - Forms only submit to same origin

### Strict-Transport-Security (HSTS)

Forces HTTPS connections.

```text
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

- `max-age=31536000` - Remember for 1 year
- `includeSubDomains` - Apply to all subdomains
- `preload` - Eligible for browser preload list

### X-Content-Type-Options

Prevents MIME type sniffing.

```text
X-Content-Type-Options: nosniff
```

### X-Frame-Options

Prevents clickjacking.

```text
X-Frame-Options: DENY
```

### X-XSS-Protection

Legacy XSS filter (for older browsers).

```text
X-XSS-Protection: 1; mode=block
```

### Referrer-Policy

Controls referrer information.

```text
Referrer-Policy: strict-origin-when-cross-origin
```

### Permissions-Policy

Disables browser features.

```text
Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=(), usb=()
```

## Implementation

### Python (FastAPI)

```python
from fastapi import FastAPI
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=(), payment=(), usb=()",
}

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        for header, value in SECURITY_HEADERS.items():
            response.headers[header] = value
        return response

app = FastAPI()
app.add_middleware(SecurityHeadersMiddleware)
```

### TypeScript (Express)

```typescript
import helmet from "helmet";
import { Express } from "express";

export function configureSecurityHeaders(app: Express): void {
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          imgSrc: ["'self'", "data:", "https:"],
          fontSrc: ["'self'"],
          connectSrc: ["'self'"],
          frameAncestors: ["'none'"],
          baseUri: ["'self'"],
          formAction: ["'self'"],
        },
      },
      hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true,
      },
      frameguard: { action: "deny" },
      referrerPolicy: { policy: "strict-origin-when-cross-origin" },
    })
  );

  // Permissions-Policy not in helmet, add manually
  app.use((req, res, next) => {
    res.setHeader(
      "Permissions-Policy",
      "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
    );
    next();
  });
}
```

## Verification

### CI Pipeline Check

```yaml
# .github/workflows/ci.yml
security-headers:
  runs-on: ubuntu-latest
  needs: deploy-staging
  steps:
    - name: Check security headers
      run: |
        RESPONSE=$(curl -sI https://staging.example.com)

        echo "$RESPONSE" | grep -qi "content-security-policy" || exit 1
        echo "$RESPONSE" | grep -qi "strict-transport-security" || exit 1
        echo "$RESPONSE" | grep -qi "x-content-type-options: nosniff" || exit 1
        echo "$RESPONSE" | grep -qi "x-frame-options: deny" || exit 1
        echo "$RESPONSE" | grep -qi "referrer-policy" || exit 1
        echo "$RESPONSE" | grep -qi "permissions-policy" || exit 1

        echo "All security headers present"
```

### Local Verification Script

```bash
#!/bin/bash
# scripts/check-headers.sh

URL=${1:-http://localhost:8000}

echo "Checking security headers for $URL"

HEADERS=$(curl -sI "$URL")

check_header() {
    if echo "$HEADERS" | grep -qi "$1"; then
        echo "✓ $1"
    else
        echo "✗ $1 MISSING"
        exit 1
    fi
}

check_header "content-security-policy"
check_header "strict-transport-security"
check_header "x-content-type-options"
check_header "x-frame-options"
check_header "referrer-policy"
check_header "permissions-policy"

echo ""
echo "All required headers present"
```

## Environment-Specific Adjustments

### Development

CSP may need adjustments for hot reload:

```python
if settings.debug:
    SECURITY_HEADERS["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self' 'unsafe-eval'; "
        "style-src 'self' 'unsafe-inline'; connect-src 'self' ws://localhost:*"
    )
```

### Production

HSTS preload requires:

1. Valid HTTPS certificate
2. Redirect HTTP to HTTPS
3. All subdomains serve HTTPS
4. HSTS header on base domain

## Common Issues

### CSP Violations

1. **Inline scripts blocked**: Move to external files or use nonces
2. **Third-party resources blocked**: Add to appropriate directive
3. **WebSocket blocked**: Add `ws://` or `wss://` to `connect-src`

### CORS vs CSP

- **CORS**: Server controls who can make requests TO it
- **CSP**: Server controls what resources browser can load FROM other origins

They serve different purposes and both are required.

## Monitoring

Set up CSP violation reporting:

```text
Content-Security-Policy: ...; report-uri /api/csp-report; report-to csp-endpoint
```

```python
@app.post("/api/csp-report")
async def csp_report(request: Request) -> dict:
    report = await request.json()
    logger.warning("csp_violation", report=report)
    return {"status": "received"}
```

# Feature Flags Standard

Feature flags enable shipping incomplete features safely, gradual rollouts, and instant rollback without code deployment. For AI development, flags provide a critical safety net.

## Why Feature Flags for AI Development

| Benefit | Description |
|---------|-------------|
| Ship faster | AI can commit incomplete features behind flags |
| Reduce risk | AI-introduced regressions affect only flagged users |
| Human control | Humans can enable/disable AI-written features instantly |
| A/B testing | Validate AI implementations against alternatives |
| Instant rollback | No deploy needed to disable problematic code |

## Requirements

### All New Features Behind Flags

```typescript
// Required for any user-facing feature
if (featureFlags.isEnabled('new-checkout-flow', user)) {
  return renderNewCheckout();
}
return renderLegacyCheckout();
```

**Exception**: Internal tooling and infrastructure changes don't require flags.

### Flag Naming Convention

```
<scope>-<feature>-<variant>

Examples:
  billing-stripe-integration
  auth-oauth-google
  ui-dashboard-redesign
  api-v2-endpoints
```

### Required Metadata

Every flag must have:

```yaml
flags:
  billing-stripe-integration:
    description: "New Stripe payment processing"
    owner: "billing-team"
    created: "2025-01-15"
    expires: "2025-02-15"    # Max 30 days from creation
    rollout:
      dev: 100%
      uat: 100%
      prod: 0%               # Start at 0, increment after validation
    ticket: "JIRA-1234"      # Tracking ticket required
```

### Expiration Policy

| Rule | Enforcement |
|------|-------------|
| Max lifetime: 30 days | Flags older than 30 days trigger CI warning |
| Max lifetime: 60 days | Flags older than 60 days block deploy |
| Cleanup sprint | Monthly sprint to remove stale flags |

### Stale Flag Detection

```yaml
# In CI pipeline
- name: Check for stale flags
  run: |
    ./scripts/check-stale-flags.sh
    # Fails if any flag > 60 days old
```

## Flag Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FLAG LIFECYCLE                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  CREATE          ROLLOUT           VALIDATE         CLEANUP          │
│  ┌──────┐       ┌──────┐          ┌──────┐        ┌──────┐          │
│  │ Flag │  ──►  │ Dev  │  ──►     │ UAT  │  ──►   │ Prod │  ──►     │
│  │ 0%   │       │ 100% │          │ 100% │        │ 100% │          │
│  └──────┘       └──────┘          └──────┘        └──────┘          │
│                                                                      │
│                                        │                  │          │
│                                        ▼                  ▼          │
│                                   ┌──────────┐      ┌──────────┐    │
│                                   │ Rollback │      │ Remove   │    │
│                                   │ to 0%    │      │ flag &   │    │
│                                   │ if issue │      │ old code │    │
│                                   └──────────┘      └──────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Implementation

### Recommended Libraries

**Python (FastAPI)**:
```python
# Using LaunchDarkly or custom implementation
from app.core.flags import feature_flags

@router.get("/checkout")
async def checkout(user: User = Depends(get_current_user)):
    if feature_flags.is_enabled("new-checkout-flow", user.id):
        return await new_checkout_handler(user)
    return await legacy_checkout_handler(user)
```

**Node.js (TypeScript)**:
```typescript
// Using LaunchDarkly, Unleash, or custom implementation
import { featureFlags } from '@/core/flags';

app.get('/checkout', async (req, res) => {
  if (await featureFlags.isEnabled('new-checkout-flow', req.user.id)) {
    return newCheckoutHandler(req, res);
  }
  return legacyCheckoutHandler(req, res);
});
```

### Custom Flag Store (Simple Implementation)

```typescript
// config/flags.yaml
flags:
  new-checkout-flow:
    enabled: true
    rollout_percentage: 10
    allowed_users: ["internal-testers"]

// core/flags.ts
import { load } from 'js-yaml';

class FeatureFlags {
  private flags: Record<string, FlagConfig>;

  async isEnabled(flag: string, userId: string): Promise<boolean> {
    const config = this.flags[flag];
    if (!config?.enabled) return false;

    // Check allowed users
    if (config.allowed_users?.includes(userId)) return true;

    // Check rollout percentage
    const hash = this.hashUserId(userId, flag);
    return hash < config.rollout_percentage;
  }

  private hashUserId(userId: string, flag: string): number {
    // Consistent hashing for sticky rollout
    const combined = `${userId}-${flag}`;
    return Math.abs(this.hash(combined)) % 100;
  }
}
```

## Rollout Strategy

### Gradual Rollout

```yaml
# Day 1: Internal only
rollout:
  prod: 0%
  allowed_users: ["@internal.example.com"]

# Day 2: 5% of users
rollout:
  prod: 5%

# Day 3: 25% of users (if metrics stable)
rollout:
  prod: 25%

# Day 4: 50% of users
rollout:
  prod: 50%

# Day 5: 100% of users
rollout:
  prod: 100%

# Week 2: Remove flag and old code
status: cleanup
```

### Kill Switch

Every flag can be instantly disabled:

```bash
# Emergency disable
./ops.sh flag disable new-checkout-flow --env prod --reason "P1 incident"
```

This takes effect immediately without code deployment.

## AI Development Workflow

1. **AI creates feature behind flag** (0% rollout)
2. **AI writes tests** for both paths (flag on and off)
3. **Human reviews** and approves
4. **Gradual rollout** with monitoring
5. **Full rollout** after validation
6. **Cleanup** - AI removes flag and old code

### Required Tests

```typescript
describe('Checkout', () => {
  describe('with new-checkout-flow enabled', () => {
    beforeEach(() => {
      featureFlags.override('new-checkout-flow', true);
    });

    it('should render new checkout', async () => {
      // Test new implementation
    });
  });

  describe('with new-checkout-flow disabled', () => {
    beforeEach(() => {
      featureFlags.override('new-checkout-flow', false);
    });

    it('should render legacy checkout', async () => {
      // Test legacy implementation
    });
  });
});
```

## Enforcement

| Check | Gate | Action |
|-------|------|--------|
| New user-facing feature without flag | CI | Warning (soft) |
| Flag > 30 days old | CI | Warning |
| Flag > 60 days old | Deploy | Block |
| Flag without expiration | CI | Block |
| Flag without owner | CI | Block |
| Flag without ticket | CI | Warning |

## Flag Cleanup Sprint

Monthly cleanup process:

1. **Identify stale flags** (> 30 days at 100% rollout)
2. **Create cleanup tickets**
3. **Remove flag conditionals** (keep winning code path)
4. **Delete flag configuration**
5. **Verify no regression** in tests

```bash
# List stale flags
./ops.sh flags list --stale

# Generate cleanup report
./ops.sh flags report --format markdown > cleanup-sprint.md
```

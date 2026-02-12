# Canary Deployment Standard

Canary deployments route a small percentage of traffic to new code before full rollout. This catches production issues before they affect all users - critical for AI-written code where "plausible-looking" bugs may escape testing.

## Why Canary for AI Development

AI-written code can:

- Pass all tests but fail in production edge cases
- Have subtle logic errors that look correct
- Make assumptions that don't hold at scale

Canary deployments provide a production safety net that catches what testing misses.

## Deployment Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CANARY DEPLOYMENT FLOW                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐           │
│  │ Deploy   │     │ Canary   │     │ Observe  │     │ Promote  │           │
│  │ to 10%   │ ──► │ Traffic  │ ──► │ Metrics  │ ──► │ to 100%  │           │
│  │          │     │ 5 min    │     │          │     │          │           │
│  └──────────┘     └──────────┘     └──────────┘     └──────────┘           │
│       │                                  │                                   │
│       │                                  │ Error rate > 0.5%                 │
│       │                                  │ or P99 > 2s                       │
│       │                                  ▼                                   │
│       │                           ┌──────────┐                              │
│       │                           │ AUTO     │                              │
│       └─────────────────────────► │ ROLLBACK │                              │
│         Any failure               └──────────┘                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Requirements

### Traffic Split

| Stage | Traffic | Duration | Gate |
|-------|---------|----------|------|
| Canary | 10% | 5 minutes minimum | Automated |
| Validation | 10% | Until metrics stable | Manual approval |
| Rollout | 100% | - | After approval |

### Auto-Rollback Triggers

Immediate rollback if ANY of these occur during canary:

| Metric | Threshold | Action |
|--------|-----------|--------|
| Error rate (5xx) | > 0.5% | Rollback |
| P99 latency | > 2x baseline | Rollback |
| Health check failures | Any | Rollback |
| Memory usage | > 90% | Rollback |
| CPU usage | > 85% sustained | Rollback |
| Unhandled exceptions | Any new type | Rollback |

### Minimum Canary Duration

- **5 minutes minimum** observation window
- Must see at least **100 requests** to canary instances
- Low-traffic services may need longer windows

## Implementation

### Using ops.sh

```bash
# Start canary deployment (10% traffic)
./ops.sh deploy --environment prod --canary

# Monitor canary metrics
./ops.sh canary status

# Approve promotion to 100%
./ops.sh canary promote --confirm

# Emergency rollback
./ops.sh canary rollback --reason "Error rate spike"
```

### Docker Compose / Traefik

```yaml
# docker-compose.prod.yml
services:
  app:
    image: myapp:stable
    labels:
      - "traefik.http.routers.app.rule=Host(`app.example.com`)"
      - "traefik.http.services.app.loadbalancer.weight=90"

  app-canary:
    image: myapp:canary
    labels:
      - "traefik.http.routers.app-canary.rule=Host(`app.example.com`)"
      - "traefik.http.services.app-canary.loadbalancer.weight=10"
```

### Kubernetes

```yaml
# canary-deployment.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: app
spec:
  replicas: 10
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 100

---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
    - name: success-rate
      interval: 30s
      successCondition: result[0] >= 0.995
      provider:
        prometheus:
          query: |
            sum(rate(http_requests_total{status!~"5.."}[5m])) /
            sum(rate(http_requests_total[5m]))
```

### GitHub Actions Integration

```yaml
# .github/workflows/deploy-prod.yml
jobs:
  deploy-canary:
    runs-on: ubuntu-latest
    environment: production-canary
    steps:
      - name: Deploy canary (10%)
        run: ./ops.sh deploy --environment prod --canary

      - name: Wait for traffic
        run: sleep 300  # 5 minute observation

      - name: Check canary metrics
        id: metrics
        run: |
          METRICS=$(./ops.sh canary metrics --json)
          ERROR_RATE=$(echo $METRICS | jq '.error_rate')
          if (( $(echo "$ERROR_RATE > 0.005" | bc -l) )); then
            echo "::error::Canary error rate too high: $ERROR_RATE"
            exit 1
          fi

      - name: Promote to 100%
        if: success()
        run: ./ops.sh canary promote --confirm

  rollback:
    runs-on: ubuntu-latest
    needs: deploy-canary
    if: failure()
    steps:
      - name: Auto-rollback
        run: ./ops.sh canary rollback --reason "Automated: Canary check failed"

      - name: Alert team
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d '{"text":"🚨 Canary deployment rolled back automatically"}'
```

## Monitoring During Canary

### Required Dashboards

```text
┌─────────────────────────────────────────────────────────────────┐
│                    CANARY MONITORING DASHBOARD                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Error Rate (5xx)              Latency P99                       │
│  ┌─────────────────────┐      ┌─────────────────────┐           │
│  │ Stable: 0.1%        │      │ Stable: 150ms       │           │
│  │ Canary: 0.2%    ⚠️  │      │ Canary: 180ms   ✓   │           │
│  └─────────────────────┘      └─────────────────────┘           │
│                                                                  │
│  Request Count                 Memory Usage                      │
│  ┌─────────────────────┐      ┌─────────────────────┐           │
│  │ Stable: 450/min     │      │ Stable: 65%         │           │
│  │ Canary: 50/min  ✓   │      │ Canary: 68%     ✓   │           │
│  └─────────────────────┘      └─────────────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Comparison Queries

```promql
# Error rate comparison
sum(rate(http_requests_total{status=~"5..",version="canary"}[5m]))
/
sum(rate(http_requests_total{version="canary"}[5m]))
-
sum(rate(http_requests_total{status=~"5..",version="stable"}[5m]))
/
sum(rate(http_requests_total{version="stable"}[5m]))

# Result > 0 means canary is worse
```

## Human Approval Gates

### Canary Approval Checklist

Before promoting canary to 100%:

- [ ] Error rate within threshold (< 0.5%)
- [ ] Latency within threshold (< 2x baseline)
- [ ] No new exception types
- [ ] Memory usage stable
- [ ] No anomalies in business metrics
- [ ] Minimum observation time elapsed (5 min)
- [ ] Minimum request count (100+ requests)

### Approval Process

1. **Canary deploys automatically** after CI passes
2. **Monitoring runs for 5+ minutes**
3. **Automated checks** verify metrics
4. **Human reviews** dashboard and approves
5. **Full rollout** proceeds

```bash
# Human approves after review
./ops.sh canary promote --confirm --approver "tim@example.com"

# Logged for audit:
# {
#   "action": "canary_promoted",
#   "version": "v2.1.0",
#   "canary_duration_min": 8,
#   "canary_requests": 523,
#   "error_rate": 0.002,
#   "approver": "tim@example.com",
#   "timestamp": "2025-01-15T14:30:00Z"
# }
```

## Rollback Procedure

### Automatic Rollback

Triggered by monitoring when thresholds exceeded:

```typescript
// Pseudo-code for canary monitor
async function monitorCanary(): Promise<void> {
  while (canaryActive) {
    const metrics = await getCanaryMetrics();

    if (metrics.errorRate > 0.005) {
      await rollback('Error rate exceeded threshold');
      return;
    }

    if (metrics.p99Latency > baseline.p99Latency * 2) {
      await rollback('Latency exceeded threshold');
      return;
    }

    await sleep(30000); // Check every 30 seconds
  }
}
```

### Manual Rollback

```bash
# Emergency rollback - no confirmation needed
./ops.sh canary rollback --emergency --reason "User reports checkout failures"

# Normal rollback with confirmation
./ops.sh canary rollback --confirm --reason "Elevated error rate in payments"
```

## Enforcement

| Check | Stage | Action |
|-------|-------|--------|
| Canary enabled for prod deploys | CI | Required |
| Minimum 5 min observation | Deploy | Enforced |
| Auto-rollback configured | Deploy | Required |
| Monitoring dashboard exists | Deploy | Warning |
| Human approval for promotion | Deploy | Required |

## Exceptions

Canary may be skipped ONLY for:

- Emergency security patches (with documented approval)
- Database migrations (handled separately)
- Configuration-only changes

All exceptions require:

- Written justification
- Security team approval for security patches
- Post-deploy verification

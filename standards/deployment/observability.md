# Production Observability Standard

Observability is the "shift right" complement to testing. While tests catch issues before production, observability catches what testing misses - critical for AI-written code where subtle bugs may only manifest under real-world conditions.

## The Three Pillars

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY PILLARS                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  LOGS                    METRICS                   TRACES                │
│  ┌──────────────┐       ┌──────────────┐         ┌──────────────┐       │
│  │ What         │       │ How much     │         │ How it       │       │
│  │ happened     │       │ /how fast    │         │ flows        │       │
│  │              │       │              │         │              │       │
│  │ • Events     │       │ • Counters   │         │ • Request    │       │
│  │ • Errors     │       │ • Gauges     │         │   path       │       │
│  │ • Context    │       │ • Histograms │         │ • Latency    │       │
│  │              │       │              │         │   breakdown  │       │
│  └──────────────┘       └──────────────┘         └──────────────┘       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Requirements

### Logging

#### Structured Logging (Required)

All logs must be structured JSON:

```typescript
// ❌ Bad - unstructured
console.log('User login failed');

// ✓ Good - structured
logger.warn('User login failed', {
  userId: user.id,
  email: user.email,
  reason: 'invalid_password',
  attempt: 3,
  correlationId: req.correlationId,
});
```

#### Correlation IDs (Required)

Every request must have a correlation ID that propagates through all services:

```typescript
// Middleware to add correlation ID
app.use((req, res, next) => {
  req.correlationId = req.headers['x-correlation-id'] || uuid();
  res.setHeader('x-correlation-id', req.correlationId);
  next();
});

// Include in all logs
logger.info('Processing payment', {
  correlationId: req.correlationId,
  paymentId: payment.id,
  amount: payment.amount,
});
```

#### Log Levels

| Level | Use For | Example |
|-------|---------|---------|
| ERROR | Failures requiring attention | Payment failed, DB connection lost |
| WARN | Potential issues, degraded state | Retry attempt, cache miss |
| INFO | Business events, happy path | User registered, order completed |
| DEBUG | Detailed diagnostic info | Function entry/exit, variable values |

**Production**: ERROR, WARN, INFO only
**Development**: All levels

#### Required Log Fields

Every log entry must include:

```json
{
  "timestamp": "2025-01-15T14:30:00.000Z",
  "level": "INFO",
  "message": "Payment processed",
  "service": "payment-service",
  "environment": "prod",
  "correlationId": "abc123",
  "traceId": "def456",
  "data": {
    "paymentId": "pay_123",
    "amount": 9900,
    "currency": "USD"
  }
}
```

### Metrics

#### Required Metrics

Every service must expose:

| Metric | Type | Description |
|--------|------|-------------|
| `http_requests_total` | Counter | Total requests by status, method, path |
| `http_request_duration_seconds` | Histogram | Request latency |
| `http_requests_in_flight` | Gauge | Active requests |
| `app_errors_total` | Counter | Application errors by type |
| `db_query_duration_seconds` | Histogram | Database query latency |
| `external_api_duration_seconds` | Histogram | External API call latency |
| `queue_size` | Gauge | Message queue depth |
| `memory_usage_bytes` | Gauge | Memory consumption |

#### Implementation

**Python (FastAPI + Prometheus)**:

```python
from prometheus_client import Counter, Histogram, Gauge
from prometheus_fastapi_instrumentator import Instrumentator

# Auto-instrument HTTP metrics
Instrumentator().instrument(app).expose(app)

# Custom business metrics
payments_processed = Counter(
    'payments_processed_total',
    'Total payments processed',
    ['status', 'payment_method']
)

payment_amount = Histogram(
    'payment_amount_dollars',
    'Payment amounts',
    buckets=[10, 50, 100, 500, 1000, 5000]
)

@app.post('/payments')
async def process_payment(payment: Payment):
    result = await payment_service.process(payment)
    payments_processed.labels(
        status=result.status,
        payment_method=payment.method
    ).inc()
    payment_amount.observe(payment.amount / 100)
    return result
```

**Node.js (Express + Prometheus)**:

```typescript
import promClient from 'prom-client';
import promBundle from 'express-prom-bundle';

// Auto-instrument HTTP metrics
app.use(promBundle({ includeMethod: true, includePath: true }));

// Custom metrics
const paymentsProcessed = new promClient.Counter({
  name: 'payments_processed_total',
  help: 'Total payments processed',
  labelNames: ['status', 'payment_method'],
});

app.post('/payments', async (req, res) => {
  const result = await paymentService.process(req.body);
  paymentsProcessed.labels({
    status: result.status,
    payment_method: req.body.method,
  }).inc();
  res.json(result);
});
```

### Distributed Tracing

#### Required for All Services

Every service must:

1. Propagate trace context (W3C Trace Context headers)
2. Create spans for significant operations
3. Add relevant attributes to spans

```typescript
import { trace, SpanStatusCode } from '@opentelemetry/api';

const tracer = trace.getTracer('payment-service');

async function processPayment(payment: Payment): Promise<Result> {
  return tracer.startActiveSpan('processPayment', async (span) => {
    try {
      span.setAttribute('payment.id', payment.id);
      span.setAttribute('payment.amount', payment.amount);
      span.setAttribute('payment.method', payment.method);

      const result = await stripe.charges.create({
        amount: payment.amount,
        currency: payment.currency,
      });

      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (error) {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.recordException(error);
      throw error;
    } finally {
      span.end();
    }
  });
}
```

## Alerting

### Required Alerts

| Alert | Threshold | Severity | Action |
|-------|-----------|----------|--------|
| Error rate high | > 1% for 5 min | Critical | Page on-call |
| Error rate elevated | > 0.5% for 10 min | Warning | Notify Slack |
| P99 latency high | > 2s for 5 min | Critical | Page on-call |
| P99 latency elevated | > 1s for 10 min | Warning | Notify Slack |
| Service down | Health check failing | Critical | Page immediately |
| Database connection pool exhausted | > 90% for 2 min | Critical | Page on-call |
| Memory usage high | > 85% for 5 min | Warning | Notify Slack |
| Queue depth high | > 1000 for 10 min | Warning | Notify Slack |

### Alert Configuration

```yaml
# Prometheus alert rules
groups:
  - name: app-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m])) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate: {{ $value | humanizePercentage }}"
          runbook: "https://wiki/runbooks/high-error-rate"

      - alert: HighLatency
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
          ) > 2
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "P99 latency above 2s: {{ $value }}s"
          runbook: "https://wiki/runbooks/high-latency"
```

## Dashboards

### Required Dashboards

#### 1. Service Health Dashboard

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                      SERVICE HEALTH DASHBOARD                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Request Rate           Error Rate            P99 Latency                │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐            │
│  │  1.2k/min   │       │    0.1%     │       │   145ms     │            │
│  │  ▂▃▅▆▇▇▆▅▃▂ │       │  ▁▁▁▁▁▁▁▁▂▁ │       │  ▂▂▂▃▂▂▂▂▂▂ │            │
│  └─────────────┘       └─────────────┘       └─────────────┘            │
│                                                                          │
│  Active Instances      Memory Usage          CPU Usage                   │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐            │
│  │     4       │       │    65%      │       │    32%      │            │
│  │   ●  ●  ●  ●│       │  ▅▅▅▅▅▅▅▅▅▅ │       │  ▃▃▃▃▃▃▃▃▃▃ │            │
│  └─────────────┘       └─────────────┘       └─────────────┘            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 2. Business Metrics Dashboard

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    BUSINESS METRICS DASHBOARD                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Orders/Hour           Revenue/Hour          Conversion Rate             │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐            │
│  │    152      │       │   $12.4k    │       │    3.2%     │            │
│  │  ▂▃▅▆▇▇▆▅▃▂ │       │  ▂▃▄▅▆▇▇▆▄▃ │       │  ▃▃▃▃▃▃▃▃▃▃ │            │
│  └─────────────┘       └─────────────┘       └─────────────┘            │
│                                                                          │
│  Failed Payments       Cart Abandonment      User Signups                │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐            │
│  │    2.1%     │       │   68%       │       │    45/hr    │            │
│  │  ▁▁▁▁▂▁▁▁▁▁ │       │  ▇▇▇▇▇▇▇▇▇▇ │       │  ▂▃▄▅▆▇▅▄▃▂ │            │
│  └─────────────┘       └─────────────┘       └─────────────┘            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 3. Error Investigation Dashboard

Shows:

- Error count by type
- Error timeline
- Sample error logs
- Affected users
- Related traces

## Anomaly Detection

### Business Metric Anomalies

Detect unusual patterns that may indicate AI-introduced bugs:

```python
# Detect significant deviation from baseline
def detect_anomaly(current: float, baseline: float, threshold: float = 0.3) -> bool:
    if baseline == 0:
        return current > 0
    deviation = abs(current - baseline) / baseline
    return deviation > threshold

# Alert on anomalies
if detect_anomaly(current_orders_per_hour, baseline_orders_per_hour):
    alert.send(
        severity='warning',
        message=f'Order rate anomaly: {current_orders_per_hour} vs baseline {baseline_orders_per_hour}'
    )
```

### Recommended Anomaly Checks

| Metric | Baseline | Alert If |
|--------|----------|----------|
| Orders/hour | Rolling 7-day average | < 50% or > 200% |
| Revenue/hour | Rolling 7-day average | < 50% or > 200% |
| Signups/hour | Rolling 7-day average | < 30% |
| Error rate by type | Previous week | New error type appears |
| API response times | Previous day | > 2x increase |

## Stack Recommendations

### Logging

- **Cloud**: CloudWatch Logs, GCP Cloud Logging, DataDog Logs
- **Self-hosted**: Loki + Grafana

### Metrics

- **Cloud**: CloudWatch Metrics, GCP Cloud Monitoring, DataDog
- **Self-hosted**: Prometheus + Grafana

### Tracing

- **Cloud**: AWS X-Ray, GCP Cloud Trace, DataDog APM
- **Self-hosted**: Jaeger, Zipkin

### All-in-One

- **Cloud**: DataDog, New Relic, Honeycomb
- **Self-hosted**: Grafana Stack (Loki + Prometheus + Tempo)

## Enforcement

| Check | Gate | Action |
|-------|------|--------|
| Structured logging configured | Deploy | Required |
| Health endpoint exposes metrics | Deploy | Required |
| Correlation ID propagation | Deploy | Required |
| Core alerts configured | Deploy | Required |
| Business dashboard exists | First production deploy | Required |
| Tracing instrumented | Deploy | Warning (grace period 30 days) |

## Implementation Checklist

- [ ] Structured logging with correlation IDs
- [ ] Prometheus metrics endpoint (`/metrics`)
- [ ] Health check endpoints (`/health`, `/health/ready`)
- [ ] Core dashboards created
- [ ] Error rate alert configured
- [ ] Latency alert configured
- [ ] Service down alert configured
- [ ] Business metrics tracked
- [ ] Anomaly detection for key metrics
- [ ] Distributed tracing instrumented
- [ ] Runbooks linked to alerts

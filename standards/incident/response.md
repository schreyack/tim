# Incident Response Standard

This document defines incident response procedures for all TIM projects.

## Incident Classification

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| P0 | Critical | Immediate (< 15 min) | Data breach, system down, security exploit |
| P1 | High | < 1 hour | Major feature broken, significant data loss |
| P2 | Medium | < 4 hours | Feature degraded, minor data issues |
| P3 | Low | < 24 hours | Minor bugs, cosmetic issues |

### Automatic Escalation

- P2 without update for 2 hours → P1
- P1 without resolution for 4 hours → P0

## Detection

### Monitoring Triggers

Incidents may be detected through:

1. **Automated alerts** - Error rate spikes, latency increases
2. **User reports** - Support tickets, direct feedback
3. **Security scans** - Vulnerability detection, intrusion alerts
4. **CI/CD failures** - Production deployment issues

### Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Error rate | > 1% | > 5% |
| Latency (p99) | > 500ms | > 2000ms |
| Failed logins | > 10/min | > 50/min |
| CPU usage | > 70% | > 90% |

## Response Procedures

### Immediate Actions (First 15 Minutes)

1. **Acknowledge** - Claim the incident
2. **Assess** - Determine severity and scope
3. **Communicate** - Notify stakeholders
4. **Contain** - Stop the bleeding

### Containment Strategies

| Incident Type | Containment Action |
|---------------|-------------------|
| Bad deployment | Rollback immediately |
| Security breach | Revoke compromised credentials |
| Data corruption | Halt writes, preserve state |
| Service overload | Enable rate limiting |
| API abuse | Block offending IPs/tokens |

### Rollback Procedure

```bash
# Check current deployment
./ops.sh --env prod status

# Rollback to previous version
./ops.sh --env prod rollback

# Verify rollback succeeded
./ops.sh --env prod health
```

## Communication Protocol

### Internal Updates

| Severity | Update Frequency | Channel |
|----------|------------------|---------|
| P0 | Every 15 minutes | Slack + Phone |
| P1 | Every 30 minutes | Slack |
| P2 | Every 2 hours | Slack |
| P3 | Daily | Email |

### Update Template

```text
INCIDENT UPDATE - [P0/P1/P2/P3]

Status: [Investigating | Identified | Monitoring | Resolved]
Impact: [Description of user impact]
Timeline:
  - HH:MM - [Event]
  - HH:MM - [Event]
Next Update: HH:MM
Actions: [What we're doing now]
```

### External Communication

For user-facing incidents:

1. **Acknowledge** within 30 minutes on status page
2. **Update** every hour during active incident
3. **Resolve** with summary once stable
4. **Post-mortem** within 48 hours (public if appropriate)

## Resolution

### Verification Steps

1. **Metrics normalized** - Error rates back to baseline
2. **Functionality tested** - Core features working
3. **Monitoring clear** - No new alerts
4. **User confirmation** - If reported by user

### Closure Criteria

- Root cause identified
- Fix deployed and verified
- Monitoring updated if needed
- Documentation updated
- Post-mortem scheduled

## Post-Mortem Process

### Timeline

| Action | Deadline |
|--------|----------|
| Schedule post-mortem | Within 24 hours |
| Complete draft | Within 48 hours |
| Team review | Within 72 hours |
| Action items assigned | Within 1 week |

### Post-Mortem Template

```markdown
# Incident Post-Mortem: [Title]

**Date**: YYYY-MM-DD
**Duration**: X hours Y minutes
**Severity**: P0/P1/P2/P3
**Author**: [Name]

## Summary
[One paragraph describing what happened]

## Timeline
| Time (UTC) | Event |
|------------|-------|
| HH:MM | [Event description] |

## Root Cause
[Technical explanation of why it happened]

## Impact
- Users affected: [Number/Percentage]
- Duration of impact: [Time]
- Data loss: [Yes/No, details]
- Revenue impact: [If applicable]

## Detection
How was it detected? How long before detection?

## Response
What went well? What could be improved?

## Prevention
What changes will prevent recurrence?

## Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| [Action] | [Name] | YYYY-MM-DD |
```

### Blameless Culture

Post-mortems focus on systems, not individuals:

- **Good**: "The deployment pipeline lacked rollback automation"
- **Bad**: "Developer X forgot to test the change"

## Security Incidents

### Additional Requirements

Security incidents have special handling:

1. **Preserve evidence** - Don't delete logs or artifacts
2. **Limit access** - Need-to-know basis only
3. **Legal consultation** - If data breach suspected
4. **Regulatory notification** - Within required timeframes

### Secret Compromise

See [Secrets Management - Emergency Procedures](../security/secrets.md#emergency-procedures)

Quick actions:

1. Rotate compromised secrets immediately
2. Audit access logs
3. Determine scope of compromise
4. Notify affected parties

## Runbooks

### Required Runbooks

Each service must maintain runbooks for:

1. **Service restart** - How to safely restart
2. **Database recovery** - Backup restoration procedure
3. **Rollback** - How to revert deployments
4. **Dependency failure** - What to do when dependencies fail
5. **Scale up** - How to add capacity quickly

### Runbook Template

````markdown
# Runbook: [Action Name]

## When to Use
[Conditions that trigger this runbook]

## Prerequisites
- [ ] Access to [system]
- [ ] Knowledge of [topic]

## Steps
1. Step one
   ```bash
   command example
   ```

1. Step two

## Verification

How to confirm success

## Rollback

How to undo if something goes wrong

## Contacts

- Primary: [Name, Contact]
- Secondary: [Name, Contact]

````

## Training

### Required Training

All team members must:

1. Know how to access monitoring dashboards
2. Understand incident severity levels
3. Know who to escalate to
4. Practice runbook execution quarterly

### Incident Drills

Quarterly fire drills:

1. Simulate P1 or P0 incident
2. Practice communication protocol
3. Execute relevant runbooks
4. Debrief and improve

## Tools

### Required Tooling

| Purpose | Tool |
|---------|------|
| Monitoring | Grafana, Datadog, or equivalent |
| Alerting | PagerDuty, Opsgenie, or equivalent |
| Communication | Slack with dedicated #incidents channel |
| Status page | Statuspage.io or equivalent |
| Post-mortem | Notion, Confluence, or equivalent |

## See Also

- [Observability Standard](../deployment/observability.md)
- [Secrets Management](../security/secrets.md)
- [Ops Security](../deployment/ops-security.md)

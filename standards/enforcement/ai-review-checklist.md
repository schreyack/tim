# AI Code Review Checklist

When humans review AI-written code, they need different focus areas than when reviewing human code. AI makes different types of mistakes - often plausible-sounding but subtly wrong.

## The AI Difference

| Human Developer Issue | AI Developer Issue |
|----------------------|-------------------|
| Typos and syntax errors | Rare - AI gets syntax right |
| Missing edge cases | Common - AI may mention but not handle |
| Copy-paste mistakes | Rare - AI generates fresh |
| Inconsistent naming | Rare - AI follows patterns well |
| **Correct-looking but wrong logic** | **Common - biggest risk** |
| **Hallucinated APIs or methods** | **Common - may not exist** |
| **Overly complex solutions** | **Common - AI can over-engineer** |
| **Placeholder/stub code presented as complete** | **Common - looks done but isn't** |

## Mandatory Review Checklist

Every PR with AI-written code requires human verification of these items:

### Logic Correctness

- [ ] **Logic makes sense** - Read line by line. Does the code actually do what comments/PR description claim?
- [ ] **Control flow is correct** - Are conditionals, loops, and early returns logically sound?
- [ ] **Edge cases handled** - Not just mentioned in comments, but actually implemented
- [ ] **Error paths tested** - What happens when things fail? Is recovery correct?
- [ ] **Off-by-one errors** - Array bounds, loop iterations, pagination
- [ ] **Null/undefined handling** - Are all nullable values properly checked?

```typescript
// AI might write:
if (items.length > 0) {
  return items[items.length];  // ❌ Off-by-one: should be length - 1
}

// Or:
async function getUser(id: string): Promise<User> {
  const user = await db.users.findUnique({ where: { id } });
  return user;  // ❌ Returns null if not found, but return type says User
}
```

### API and Method Verification

- [ ] **Methods actually exist** - AI may hallucinate method names
- [ ] **Parameters are correct** - Right number, right types, right order
- [ ] **Return types match** - What the method returns vs. how it's used
- [ ] **Third-party API compatibility** - AI may use outdated or wrong API signatures

```typescript
// AI might hallucinate:
await stripe.customers.createPaymentMethod({...});  // ❌ This method doesn't exist

// Correct API:
await stripe.paymentMethods.create({...});  // ✓ Actual Stripe API
```

### Completeness

- [ ] **No TODO or FIXME left** - AI sometimes leaves placeholders
- [ ] **No placeholder implementations** - `throw new Error('Not implemented')`
- [ ] **No stub data** - Hardcoded values that should be dynamic
- [ ] **All paths implemented** - Not just the happy path
- [ ] **Feature is complete** - What's described is what's delivered

```typescript
// AI placeholder patterns to catch:
function calculateDiscount(items: Item[]): number {
  // TODO: implement discount logic
  return 0;  // ❌ Placeholder
}

async function sendEmail(to: string, body: string): Promise<void> {
  console.log(`Would send email to ${to}`);  // ❌ Stub implementation
}
```

### Security Scrutiny

- [ ] **Input validation exists** - All external input validated
- [ ] **No SQL injection** - Parameterized queries only
- [ ] **No XSS vulnerabilities** - Output properly escaped
- [ ] **Auth checks present** - Protected routes actually check auth
- [ ] **Secrets not exposed** - No API keys in code, logs, or error messages
- [ ] **Rate limiting considered** - Especially for public endpoints

```typescript
// AI might write vulnerable code that looks correct:
const query = `SELECT * FROM users WHERE id = '${userId}'`;  // ❌ SQL injection

// Or miss auth:
app.get('/admin/users', async (req, res) => {
  const users = await db.users.findMany();  // ❌ No auth check!
  res.json(users);
});
```

### Test Quality

- [ ] **Assertions are meaningful** - Not just `expect(true).toBe(true)`
- [ ] **Tests test the right thing** - Name matches what's being tested
- [ ] **Failure cases covered** - Not just happy path
- [ ] **Mocks are realistic** - Return values match real API behavior
- [ ] **No hardcoded "pass" values** - Tests that always pass

```typescript
// AI test anti-patterns:
it('should process payment', async () => {
  const result = await processPayment(100);
  expect(result).toBeDefined();  // ❌ Too weak - what should result be?
});

it('should validate email', () => {
  expect(validateEmail('test@test.com')).toBe(true);  // ✓ Good
  // ❌ Missing: invalid email tests, edge cases
});
```

### Code Quality

- [ ] **No over-engineering** - Is this simpler than it needs to be?
- [ ] **No unnecessary abstractions** - Does this pattern earn its complexity?
- [ ] **Error messages are helpful** - Include context, not just "Error occurred"
- [ ] **Logging is appropriate** - Not too verbose, not too sparse
- [ ] **No duplicate code** - AI may repeat patterns instead of extracting

```typescript
// AI over-engineering example:
// Asked to add a "save" button, AI creates:
class SaveButtonFactory implements ButtonFactoryInterface {
  private readonly strategySelectorService: StrategySelectorService;
  // ... 50 lines of abstraction for a single button
}

// When this would suffice:
<button onClick={handleSave}>Save</button>
```

## Red Flags - Request AI Revision

If you see any of these, return to AI for revision:

| Red Flag | Action |
|----------|--------|
| `// TODO` or `// FIXME` | Must be implemented, not left as comment |
| `throw new Error('Not implemented')` | Placeholder - feature incomplete |
| `console.log` for production logging | Use proper logging framework |
| Hardcoded URLs, IDs, or credentials | Must use config/env vars |
| `any` type in TypeScript | Must have proper typing |
| `# type: ignore` in Python | Must fix the type issue |
| Commented-out code | Remove or explain |
| Generic error messages | Add context |
| Missing error handling | Add try/catch with proper handling |
| Tests without assertions | Add meaningful assertions |

## Approval Requirements

### Minimum for Approval

1. All checklist items verified
2. No red flags present
3. Tests pass locally (human verified)
4. Code compiles/type-checks
5. At least 1 human reviewer approves

### Additional for Security-Sensitive Code

For auth, payments, PII handling:

1. 2 human reviewers required
2. Security-specific checklist completed
3. Manual security testing documented
4. No new dependencies without security review

## Review Comments

When leaving comments for AI revision:

**Be specific:**
```markdown
# Good
❌ Line 45: This method `stripe.customers.createPaymentMethod` doesn't exist.
   Use `stripe.paymentMethods.create` instead.
   See: https://stripe.com/docs/api/payment_methods/create

# Bad
❌ "This doesn't look right"
```

**Reference documentation:**
```markdown
❌ Line 72: Password hashing should use bcrypt, not sha256.
   See: standards/security/owasp-checklist.md#password-storage
```

**Explain the issue:**
```markdown
❌ Line 23-25: This loop will fail on empty arrays.
   When `items.length === 0`, `items[0]` returns undefined, causing
   the TypeError on line 24.

   Fix: Add guard clause `if (items.length === 0) return [];`
```

## Integration with CI

```yaml
# .github/workflows/pr-checklist.yml
name: AI Code Review Reminder

on:
  pull_request:
    types: [opened, ready_for_review]

jobs:
  add-checklist:
    runs-on: ubuntu-latest
    steps:
      - name: Add review checklist
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## AI Code Review Checklist

              Reviewer: Please verify before approving:

              - [ ] Logic makes sense (line-by-line review)
              - [ ] Methods/APIs actually exist
              - [ ] All edge cases handled (not just mentioned)
              - [ ] No TODO/FIXME/placeholder code
              - [ ] Security checks present
              - [ ] Tests have meaningful assertions
              - [ ] No over-engineering

              See: [Full Checklist](link-to-standards/ai-review-checklist.md)`
            });
```

## Tracking Review Quality

Log review outcomes to improve AI prompts:

```typescript
// After review
const reviewOutcome = {
  pr_id: 'PR-1234',
  ai_model: 'claude-opus-4',
  issues_found: [
    { type: 'hallucinated_api', file: 'payments.ts', line: 45 },
    { type: 'missing_error_handling', file: 'auth.ts', line: 72 },
  ],
  revision_rounds: 2,
  final_status: 'approved',
};

// Use this data to:
// 1. Improve AI prompts
// 2. Add specific checks to CI
// 3. Train reviewers on common issues
```

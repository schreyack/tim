# Dev Server Verification Patterns

Advisory standard for frontend verification during AI development.

## Status: Advisory

This is NOT a hard gate. It provides patterns for visual verification when:
- E2E tests don't cover all UI states
- Console errors indicate runtime issues
- Visual regressions need human review

## When to Use Dev Server Verification

### Good Use Cases

| Scenario | Verification Goal |
|----------|------------------|
| New UI component | Visual renders correctly |
| Style changes | No layout regressions |
| Error boundaries | Error states display properly |
| Loading states | Skeleton/spinner appears |
| Responsive design | Works at different viewports |

### Not a Replacement For

- Unit tests (logic verification)
- Integration tests (API interaction)
- E2E tests (user flow verification)
- Type checking (compile-time safety)

## Console Error Detection

AI should monitor browser console for errors during dev server verification.

### Patterns That Indicate Problems

```javascript
// React errors (check console for these)
"Warning: Each child in a list should have a unique 'key' prop"
"Warning: Cannot update a component while rendering a different component"
"Uncaught TypeError:"
"Uncaught ReferenceError:"

// Network errors
"Failed to fetch"
"net::ERR_"
"CORS error"
```

### What to Do

1. Start dev server: `npm run dev`
2. Open browser to localhost
3. Open browser DevTools console
4. Navigate to affected pages
5. Note any red errors (warnings may be acceptable)
6. Fix errors before considering verification complete

## Screenshot Verification

For visual changes, AI can take screenshots for human review.

### Integration with Tim-Loop

Tim-loop completion criteria can include visual verification:

```markdown
## Completion Criteria

- [ ] All tests pass
- [ ] No console errors on /dashboard page
- [ ] Screenshot captured: `screenshots/dashboard-new-widget.png`
- [ ] Human reviewed screenshot for visual correctness
```

### Screenshot Best Practices

| Practice | Rationale |
|----------|-----------|
| Consistent viewport | Reproducible comparisons |
| Clear naming | `feature-page-state.png` |
| Before/after pairs | Shows what changed |
| Store in `/screenshots` | Gitignored, not committed |

## Integration with AI Workflow

### Automated Verification (What AI Can Do)

1. Start dev server
2. Wait for compilation
3. Check for build errors
4. Open browser console
5. Report any errors found
6. Take screenshot if visual change

### Human Verification (What Requires Human)

1. Visual correctness assessment
2. Design system compliance
3. Accessibility evaluation
4. Mobile responsiveness judgment
5. Animation/interaction quality

## Anti-Patterns

### DO NOT

| Anti-Pattern | Why It's Bad |
|--------------|--------------|
| Replace E2E tests with screenshots | Screenshots don't test functionality |
| Ignore console warnings | May indicate real issues |
| Skip dev server check | Build may succeed but runtime fail |
| Trust "looks fine" without console check | Hidden errors common |

### DO

| Pattern | Why It Works |
|---------|--------------|
| Check console EVERY time | Catches runtime issues |
| Document visual changes | Human can review later |
| Run dev server before PR | Catches build issues |
| Note viewport size | Reproducible verification |

## Example Verification Workflow

```bash
# 1. Start dev server
npm run dev

# 2. Wait for ready message
# "ready - started server on 0.0.0.0:3000"

# 3. Open in browser and check console
# Browser: http://localhost:3000/affected-page
# DevTools > Console > Filter: Errors

# 4. Report findings
# "Dev server verification: No console errors on /dashboard"
# or
# "Dev server verification: Found React key warning on /users list"
```

## Completion Criteria Template

Add to plan when dev server verification is needed:

```markdown
### Dev Server Verification

- [ ] Dev server starts without errors
- [ ] No console errors on affected pages:
  - [ ] /page-1
  - [ ] /page-2
- [ ] Screenshots captured for human review (if visual change)
- [ ] Console output documented
```

## Limitations

This standard does NOT address:
- Automated visual regression testing (Chromatic, Percy)
- Cross-browser testing
- Performance verification
- Accessibility automated testing

These require dedicated tooling beyond dev server verification.

## See Also

- [E2E Requirements](./e2e-requirements.md) - Automated user flow testing
- [Test Requirements](./requirements.md) - Overall testing standards
- [AFK Coding Patterns](../operations/afk-coding-patterns.md) - Autonomous development

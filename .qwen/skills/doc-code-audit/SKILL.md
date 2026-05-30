---
name: doc-code-audit
description: Systematic methodology for auditing documentation vs implementation mismatches across multi-project codebases
source: auto-skill
extracted_at: '2026-05-31T10:00:00.000Z'
---

# Documentation vs Implementation Audit

## When to use
- Reviewing a multi-project system for consistency between docs and code
- Preparing a comprehensive update plan for a product
- Finding bugs caused by inconsistent patterns across files

## Procedure

### Phase 1: Documentation Inventory
1. Read ALL documentation files (README, design docs, API docs, deploy docs)
2. Extract key claims: thresholds, data flows, permission models, feature lists
3. Note the "source of truth" for each claim (which doc says what)

### Phase 2: Code Tracing
1. For each documented claim, trace the actual code path
2. Read the relevant source files completely (don't just grep)
3. Compare documented behavior vs actual behavior
4. Look for **multiple implementations of the same concept** (e.g., threshold checks in different files)

### Phase 3: Inconsistency Detection Pattern
Common inconsistencies to look for:
- **Threshold divergence**: Same metric checked with different values in different files (e.g., >=80 vs >=85)
- **Dead code**: Services/models that exist but aren't used by actual UI code
- **Hardcoded vs dynamic**: Data that should come from config/JSON but is hardcoded in UI
- **Semantic mismatch**: Variable names that don't match their actual meaning (e.g., `masteryPercent` = average score, not coverage)
- **Feature stubs**: UI elements that exist but have empty callbacks or placeholder data
- **Date/time bugs**: Calculations that don't handle edge cases (month boundaries, timezones)

### Phase 4: Output Structure
Create a prioritized update plan with:
1. **Status summary**: What's already been fixed vs what's still pending (check git log)
2. **BUG list**: Things that are objectively wrong (wrong calculations, crashes)
3. **Feature gap list**: Things documented but not implemented, with P0/P1/P2 priority
4. **Improvement suggestions**: UX enhancements based on user perspective analysis
5. **File index**: Key file paths for quick reference

### Key Insight
When auditing a multi-project system, the "source of truth" for data structures may be in a different project than where they're consumed. Always check the upstream project's actual schema before assuming the consumer is wrong.

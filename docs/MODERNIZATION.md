# Platform modernization roadmap

The shared visual foundation now improves the current interface without changing
workflows. The next iterations should reduce maintenance cost as well as modernize
the experience.

## Recommended priorities

1. **Measure the busiest workflows.** Add privacy-conscious product analytics for
   intake, outcomes, medical records, search, and reporting. Track completion time,
   validation failures, and abandoned forms before changing navigation.
2. **Create a design system.** Move the tokens in `asm.css` into a documented set
   of colors, spacing, type, focus, status, and component rules. Require accessible
   names, keyboard operation, and WCAG 2.2 AA contrast for every component.
3. **Replace table-based forms incrementally.** Introduce reusable grid-based form,
   field, validation-summary, toolbar, empty-state, and confirmation components.
   Migrate one high-traffic workflow at a time rather than rewriting the product.
4. **Consolidate responsive experiences.** Retire the separate mobile interface as
   desktop workflows become responsive. Start with global navigation, search,
   intake, animal details, and daily task lists.
5. **Modernize the JavaScript toolchain.** Upgrade Babel and linting, add formatting,
   unit tests, DOM accessibility tests, and browser smoke tests. Split the global
   rollup bundle by route and publish source maps for production diagnosis.
6. **Modernize Python safely.** Raise the supported Python baseline, add dependency
   lock files, type-check core modules, and place database and business rules behind
   service boundaries. Keep schema migrations backward compatible and observable.
7. **Improve operational confidence.** Add CI for lint, unit, integration,
   accessibility, and migration tests; automated dependency updates; structured
   logs; health/readiness endpoints; error monitoring; and documented restore tests.
8. **Simplify configuration.** Validate configuration on startup, support secrets
   through environment variables or a secret store, group settings by concern, and
   provide actionable errors instead of silent fallbacks.

## Suggested delivery sequence

- **Now:** shared tokens, controls, focus states, responsive login, and navigation.
- **Next:** component catalogue and automated visual/accessibility smoke tests.
- **Then:** migrate the five highest-volume workflows and unify mobile/desktop.
- **Later:** module boundaries, route-level bundles, dependency upgrades, and API
  versioning informed by measured bottlenecks rather than a big-bang rewrite.

## Success measures

- Median time and error rate for intake, outcome, and medical-entry tasks.
- Keyboard-only completion and zero critical automated accessibility violations.
- Mobile task completion rate and reduction in horizontal overflow defects.
- Initial JavaScript payload, interaction latency, and server response percentiles.
- Deployment frequency, rollback rate, mean time to recovery, and restore-test age.

---
description: Route LapisMD fixes to the owning package, release through npm ranges, and validate consumers
alwaysApply: true
---

# LapisMD local workspace guidance

This directory contains sibling repositories that are developed together.
Published packages are consumed through normal npm semver ranges. Local source
remains authoritative for diagnosing and fixing defects, but publishable
manifests and lockfiles should resolve released packages from the registry.

## Required instruction layering

This file may be loaded by local editor or agent configuration. When working
inside one of the repositories below:

1. Read the tracked `AGENTS.md` at that repository root before inspecting or
   changing code. Codex selects only `AGENTS.override.md` automatically at this
   level, so this explicit read is mandatory.
2. Apply both files. The tracked guide supplies the repository-specific
   architecture, specification, testing, visual-baseline, and commit rules.
3. Treat the source-ownership rule in this file as a workspace boundary that
   consumer convenience must not weaken. Otherwise, follow the stricter or more
   specific repository rule and report any real conflict.

Do not edit or commit local loader/editor configuration unless the user
explicitly asks for that. Change this shared file only when the user explicitly
asks to update the local workspace guidance.

## Specification search

When changing a repository that depends on `@lapismd/spec-validator`, update it
to the latest Deno-free release before spec checks. Follow
`~/.agents/skills/spec-validator/SKILL.md` and that repository's
`pnpm spec:search` task before scanning `spec/src`. Use `--semantic` for
conceptual queries and `rg` only when QMD is unavailable. Run
`spec-validator doctor` and a QMD `pnpm spec:search` check. Do not commit this
parent file into a child repository.

## Package ownership and refresh map

| Source repository              | Owned packages                                                                                                                                                                                 | Current consumers                                                                                   | Required refresh                                                                                                                                                                                                                                                     |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `storybook-addon-visual-delta` | `@lapismd/storybook-addon-visual-delta`                                                                                                                                                        | Design Core, Mira, and Lapis                                                                        | Run `pnpm build:node`, the relevant source checks, and acceptance in affected consumers.                                                                                                                                                                             |
| `design-core`                  | `@lapismd/design-core`                                                                                                                                                                         | Lapis                                                                                               | Design Core exports its main package from `src`, so run its relevant checks and restart/revalidate Lapis; there is no main-package build step.                                                                                                                       |
| `mira-mde`                     | `@lapismd/mira`, `@lapismd/mira-editor`, `@lapismd/mira-plugin-ai`, `@lapismd/mira-plugin-mermaid`, `@lapismd/mira-react`, and `@lapismd/mira-vanilla`; private Solid/Vue adapters are planned | Design Core, Lapis, and first-party plugins                                                         | Run root `pnpm build`; these package exports resolve through `dist`. Then validate Lapis.                                                                                                                                                                            |
| `lapis-notes`                  | `@lapis-notes/api`, `@lapis-notes/ui`, `@lapis-notes/workspace`, and `@lapis-notes/markdown`                                                                                                   | Lapis applications and catalog                                                                      | Run root `pnpm build` for internal `dist` consumers, followed by the relevant application/catalog checks.                                                                                                                                                            |
| `lapis-plugin-cv-roles`        | `@lapis-notes/lapis-plugin-cv-roles`                                                                                                                                                           | Lapis desktop, web, and real-App catalog                                                            | Run `pnpm build` plus the standalone spec, check, test, publint, Storybook interaction/axe, and static-build lanes. Then restart and validate Lapis against the rebuilt public `dist` exports.                                                                       |
| `ai-host`                      | `@lapismd/ai-host`                                                                                                                                                                             | Lapis desktop, web, Storybook attach, and smoke scripts                                             | Run `pnpm build`, `pnpm spec:check`, `pnpm check`, and `pnpm test`. Then restart and validate Lapis against the public exports.                                                                                                                                      |
| `terminal-host`                | `@lapismd/terminal-host`                                                                                                                                                                       | Lapis desktop, web, and local `lapis-terminal-host serve`                                           | Run `pnpm build`, `pnpm spec:check`, `pnpm check`, and `pnpm test`. Then restart and validate Lapis against the public exports.                                                                                                                                      |
| `lapis-plugin-terminal`        | `@lapis-notes/lapis-plugin-terminal`                                                                                                                                                           | Lapis desktop and web                                                                               | Run `pnpm build` plus the standalone spec, check, test, and publint lanes. Then restart and validate Lapis against the rebuilt public `dist` exports.                                                                                                                |
| `lapis-plugin-tasks`           | `@lapis-notes/lapis-plugin-tasks`                                                                                                                                                              | Lapis desktop, web, and real-App catalog                                                            | Run `pnpm build` plus the standalone spec, check, test, publint, Storybook interaction/axe, and static-build lanes. Then restart and validate Lapis against the rebuilt public `dist` exports. Hosts load it for indexing and queries; no Tasks workspace views yet. |
| `lapis-plugin-docs`            | `@lapis-notes/lapis-plugin-docs`                                                                                                                                                               | Lapis desktop, web, and real-App catalog                                                            | Run `pnpm build` plus the standalone spec, check, test, publint, Storybook interaction/axe, and static-build lanes. Then restart and validate Lapis against the rebuilt public `dist` exports.                                                                       |
| `spec-validator`               | `@lapismd/spec-validator`                                                                                                                                                                      | Visual Delta, Mira, Design Core, AI Host, Terminal Host, Lapis, and first-party plugin repositories | Run `pnpm build:node`, then `pnpm spec:check`.                                                                                                                                                                                                                       |
| `jj-acp`                         | `@lapismd/jj-acp` (private; the `jj-acp` executable plus the `jj-acp-protocol`, `jj-acp-agent`, `jj-acp-runner`, `jj-acp-control`, `jj-acp-cli`, and `jj-acp-testkit` crates) | jj-store (planned agent runners)                                              | Run `pnpm build`, `pnpm spec:check`, `pnpm check`, and `pnpm test`. Then restart and validate the consumer against the rebuilt `jj-acp` binary.                                                                                                                    |

Use the import path, package manifest, and public contract to identify ownership.
For a new sibling repository, add its ownership/build entry here.

## Source-first fixes

- A defect in a component, package API, generated output, or development tool
  must be reproduced and fixed in its owning repository. A request to fix the
  consuming application authorizes the corresponding source-repository change.
- Add regression evidence in the source repository. Run its focused checks and
  required build, then widen according to the test-scope ladder below before
  validating the original scenario in every affected consumer.
- If a consumer needs a missing public extension point, add the generic contract
  upstream first, then make only the smallest consumer integration change.
- Keep consumer-owned routing, persistence, vault/domain state, application
  configuration, and adapters in the consumer. Those are integration concerns,
  not reasons to move application policy into a shared package.
- Do not copy an implementation into a consumer, edit `node_modules`, add a
  package patch, Vite alias, type shim, wrapper component, or CSS override whose
  purpose is to conceal an upstream defect. Do not weaken tests, diagnostics,
  visual thresholds, or baselines to make a consumer pass.
- Published LapisMD packages should be referenced by npm semver ranges in
  package manifests and lockfiles. If a dependency defect requires a source
  fix, make that fix in the owning repository first, then update consumers to a
  released registry version or an explicitly documented temporary validation
  setup.
- Restart a long-running Storybook/Vite process when package output, manager or
  preset code, exports, or startup configuration changed and hot reload cannot
  reliably invalidate it.

## Test scope and escalation

- Testing MUST start at the narrowest failing boundary. Record the exact
  command, test or story name, and failure count before editing; rerun that
  exact target after the change. A wider passing command is not a substitute
  for proving the original regression.
- Select tests from the behavior's complete impact surface, not only from the
  files changed. Follow imports, public exports, registrations, shared state,
  lifecycle hooks, fixtures, and story helpers to identify every directly
  affected package, host, story family, and consumer.
- A documentation-only policy change runs its formatter and any checker that
  consumes that document. It does not require product test suites unless it
  changes executable examples, generated configuration, or commands used by
  automation.
- Use this escalation ladder:
  1. A private leaf change runs its exact regression plus the owning package's
     check, test, and required build lanes.
  2. A shared component, helper, fixture, store, lifecycle boundary, stylesheet
     contract, test utility, or Storybook configuration used by two or more
     tests, stories, packages, surfaces, or hosts runs all directly affected
     tests and stories, then the owning repository's full check, test, build,
     and Storybook interaction/accessibility lanes.
  3. A published contract or cross-repository change additionally rebuilds or
     packs the source package and runs focused acceptance in every affected
     consumer. If it feeds multiple consumer surfaces, run each consumer's
     full relevant interaction lane as well.
- Treat test-only changes as production-risk changes when they modify shared
  setup, fixtures, assertions, page objects, browser helpers, timing, sharding,
  or global App/workspace boot. Prove the exact repaired test first, then run
  the complete suite that consumes the changed test infrastructure.
- Browser and lifecycle fixes MUST include at least one cold run with a fresh
  Storybook/Vite process or freshly built package output. A warm targeted pass
  alone does not prove startup, teardown, import, or registration behavior.
- Keep a running before/after count for every functional, interaction, and
  accessibility failure found. Do not push or release a broad/shared change
  with unexplained failures in its required lanes. A demonstrably unrelated
  pre-existing failure must be reproduced, assigned to its owner, and reported
  separately; it is non-blocking only with explicit user acceptance.
- Visual review remains a separate, non-blocking lane unless the user makes it
  a gate. Keep changed stories `visual-pending`, do not update baselines without
  approval, and never use visual deferral to waive functional, interaction, or
  accessibility failures.
- Never loosen an assertion merely because a wider suite exposed more failures.
  Confirm the intended contract, decide whether the defect belongs to product
  code or test infrastructure, and preserve or strengthen regression evidence.

## Application ownership across LapisMD

- First-party Lapis runtime and Storybook code must receive `App` explicitly,
  derive it from an owning workspace or leaf, or read it from the API component
  context. An explicit or owned App always wins over compatibility state.
- Do not read or assign `globalThis.app` in first-party implementations. The
  API compatibility bridge, dedicated fallback tests, and packaged legacy
  smoke acceptance are the only exceptions.
- Hosts that support legacy plugins must install the public disposable
  compatibility lease before plugin loading and release it after all owned
  plugin, workspace, metadata, service, and vault teardown. Constructing an
  App must not mutate global state.
- Lapis and every separately versioned first-party plugin must keep a
  fail-closed source audit for this boundary and wire it into both normal check
  and canonical specification-check lanes. Run that audit whenever App
  ownership, host lifecycle, or app-backed stories change.
- Fix an ownership violation in the package that owns the code. Do not add a
  consumer wrapper, ambient assignment, or allowlist to conceal it.

## Cross-repository workflow

1. Run `jj --no-pager st` in the consumer and every source repository that may
   change. Preserve unrelated work.
2. Read the owning repository's tracked `AGENTS.md` and any required canonical
   specification before editing.
3. Reproduce the issue at the narrowest source boundary and add a regression
   test or governed Storybook scenario there.
4. Implement and validate the source fix, then run the refresh command from the
   table above.
5. Re-run the consumer reproduction and its focused acceptance checks, then
   complete every wider lane required by the test-scope ladder. Keep source
   correctness and consumer integration evidence distinct.
6. Commit code changes separately in each repository with Jujutsu, following
   that repository's commit policy. Never include this local guidance or local
   loader/editor configuration in a child-repository commit.

## Standing commit request

This is a standing request for every repository and package under this
workspace root. After each verified slice, commit in the owning repository
without waiting for the user to ask. Leave unrelated work, secrets, local
loader/editor configuration, and this shared file uncommitted.

If the owning repository has overlapping uncommitted work that prevents a safe
change, report the conflict and stop. Do not substitute a consumer workaround.

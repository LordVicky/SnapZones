# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- Create, read, update, label, comment on, and close issues using `gh issue`.
- Infer the repository from the configured Git remote.
- When a skill says “publish to the issue tracker,” create a GitHub issue.
- When a skill says “fetch the relevant ticket,” use `gh issue view <number> --comments`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding

Use a `wayfinder:map` issue with linked child issues. Prefer GitHub sub-issues and native issue dependencies, falling back to task lists and `Blocked by:` references where unavailable.

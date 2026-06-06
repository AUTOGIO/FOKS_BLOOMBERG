# FOKS Terminal Agent Instructions

## Scope

This file applies to the repository at:

```text
/Users/giovannini_nuovo/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG
```

FOKS Terminal is an Apple-native, local-first macOS operational command center for project visibility, system diagnostics, launchd inspection, logs, daily reporting, and advisory local AI analysis.

## Operating Mode

- Execute directly and keep changes production-oriented.
- Prefer simple, deterministic Swift, Bash, and local macOS APIs.
- Preserve existing workflows and minimize moving parts.
- Avoid speculative infrastructure, orchestration, wrappers, cloud dependencies, and unnecessary frameworks.
- If scope starts drifting, reduce to the smallest shippable improvement.

Default priority:

```text
Execution > Design
Simplicity > Completeness
Shipping > Perfection
Stability > Novelty
Determinism > Cleverness
```

## Safety Model

The app is read-only by default.

Do not add these unless the user explicitly expands scope:

- cloud telemetry
- autonomous fixes
- destructive maintenance
- credential storage
- background orchestration
- hidden execution
- shell-snippet execution
- write/delete/reset/kill/unload/bootstrap buttons

The AI layer is advisory only. It may analyze real diagnostic bundles and suggest next steps, but it must not become a source of truth or execute fixes.

## Data Integrity

REAL DATA ONLY. No fake metrics, seeded demo states, synthetic logs, or plausible fallback values.

Required behavior:

- hardware and OS facts must come from live `sysctl` and `sw_vers`
- project inventory must come from `config/projects.json`
- missing or invalid project config must render as empty or unavailable, not fallback projects
- failed metric reads must render as `unavailable`, not `0%`
- missing MetricKit payloads must render as waiting or empty state, not synthetic performance data
- logs must come from real allowlisted local log paths
- health scores must come from the current local snapshot only

Preferred runtime signals:

```text
memory pressure: memory_pressure, with vm_stat fallback when clearly labeled
disk: df -k /
processes: /bin/ps
launchd: /bin/launchctl
git: /usr/bin/git
local AI: http://127.0.0.1:11434
```

## Architecture

Preserve the repo layering:

```text
Core models and parsers
-> explicit async command runner
-> system/project/log readers
-> dashboard snapshot and scoring
-> incident aggregation
-> action center and fix queue
-> daily ops report builder
-> MetricKit telemetry collector
-> local Ollama advisor
-> SwiftUI command center
```

Conceptual product layers:

```text
Core Scripts
-> Interfaces
-> Triggers
-> Intelligence
-> Monitoring
```

Do not merge responsibilities incorrectly. Manual success must exist before automation, and automation must exist before orchestration.

## Command Execution Rules

Use explicit binaries with explicit arguments.

`CommandRunner` must keep rejecting:

- relative executables
- `/bin/sh`
- `/bin/bash`
- `/bin/zsh`
- `/usr/bin/env`
- free-form shell snippets

Run Check buttons must stay read-only and predeclared. Manual command cards may show copyable commands, but they must not run destructive actions from inside the app.

## AI Rules

The built-in AI integration should remain local-first through Ollama on loopback:

```text
http://127.0.0.1:11434/api/generate
```

Do not store API keys or send diagnostic bundles to cloud providers unless the user explicitly requests a cloud-backed feature.

For hybrid workflows, use this pattern:

```text
gather real local log
-> save audit artifact
-> send log to AI for analysis
-> receive suggestions
-> user reviews
-> separate explicit confirmation before any mutation
```

AI can classify, summarize, prioritize, and recommend. It must not silently move, delete, repair, or rewrite files.

## Implementation Style

- Prefer SwiftPM and native macOS frameworks.
- Keep changes small and readable.
- Follow existing file boundaries under `Sources/FOKSTerminalCore` and `Sources/FOKSTerminalApp`.
- Add abstractions only when they remove real duplication or match an existing pattern.
- Use typed models and parsers instead of ad hoc string handling when practical.
- Prefer explicit errors and unavailable states over silent fallback behavior.
- Do not introduce Docker, Kubernetes, distributed services, or SaaS dependencies.

## Validation

Before claiming the repo is healthy, run:

```bash
cd /Users/giovannini_nuovo/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG
./scripts/validate.sh
```

Expected successful output:

```text
PASS swift build
PASS swift test
```

To build the local app bundle:

```bash
cd /Users/giovannini_nuovo/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG
./scripts/build_app.sh
open /Users/giovannini_nuovo/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG/dist/FOKSTerminal.app
```

## Documentation

Keep these files aligned when behavior changes:

```text
README.md
docs/NEXT_GENERATION_ARCHITECTURE.md
docs/FOKSTerminal_feature_audit.json
```

For comprehensive audits, separate observed evidence from status labels such as:

```text
Working
Partial
Missing
```

## Stop Condition

A task is complete when:

- the requested implementation or artifact exists
- behavior matches the safety model
- real-data handling is preserved
- validation has run or the reason it could not run is stated
- the final response identifies changed files and verification performed

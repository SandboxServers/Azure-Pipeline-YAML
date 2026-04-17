# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is the shared Azure Pipelines YAML template library for the organization. Consumer repositories `extends` from templates here via the `@pipelinePatterns` resource reference. This repo owns reusable contracts and implementation; consumer repos own their triggers, queue-time parameters, and variable files.

## Repository Structure

```text
Templates/
  <Family>/
    Pipeline/Pipeline.yml     # top-level extends entry point
    Stages/*.yml               # stage-level orchestration
    Jobs/*.yml                 # job-level orchestration
    README.md
  Standalone/
    Steps/                     # shared step wrappers (default location for reusable steps)
    Jobs/                      # generic jobs reusable across families
    Stages/                    # shared stage capabilities (e.g. Security.yml)
```

Current template families: `NPM-GitHub-Release`, `Container-Build`, `Dhadgar.CI`, `SWA+Functions+SQL`.

`Templates/Standalone/Steps` subdirectories: `Artifacts/`, `Bicep/`, `Cache/`, `DotNet/`, `GitHub/`, `Helm/`, `Node/`, `Npm/` — plus standalone step files for Azure Functions, SQL Dacpac, Static Web App, and VSBuild-with-NPM.

## Design Principles

- Prefer first-party Azure DevOps tasks. Fall back to marketplace tasks. Use custom script only when tasks cannot express the behavior.
- Optimize for composition over copy/paste.
- Consumer repos own repo-specific values (service connections, branch names, env lists). This repo owns flow and structure.
- Do not store secrets or hard-code repo-specific paths unless the template explicitly serves one product family.
- Prefer templates generic enough to reuse but not so abstract they become hard to read.

## Built-In Task Policy

- Use task-native inputs before shell arguments.
- Use `Npm@1`, `UseNode@1`, `UseDotNet@2`, `PublishPipelineArtifact@1`, `DownloadPipelineArtifact@2`, `GitHubRelease@1`, etc. directly where they fit.
- If a task supports a built-in command (`ci`, `install`, `publish`, `build`, `test`), use that mode before `command: custom`.
- Do not write PowerShell/Bash wrappers around a task solely to pass through inputs it already supports.

Custom script is appropriate for: deriving metadata from files, generating manifests, orchestrating CLI operations Azure DevOps has no task for, artifact post-processing.

## Ownership Boundaries

**This repo owns:** reusable `extends` templates, shared stage/job/step composition, parameter contracts, reusable task wrappers.

**Consumer repos own:** `trigger`, `pr`, queue-time UX; repo-specific variable templates (`global.yml`, `build.yml`, `dev.yml`, `prod.yml`); service connection names, environment lists, product-specific defaults.

## Variable Strategy

- `global.yml` — settings shared across all stages
- `build.yml` — build/package behavior
- `<env>.yml` — environment-specific release/deployment settings
- Prefer explicit path parameters: `globalVariableTemplatePath`, `buildVariableTemplatePath`, `environmentVariableTemplateDirectory`
- Do not centralize consumer-specific values here; do not put secrets in shared template defaults

## Parameters and Expressions

**Parameter rules:**
- `parameters:` block at the top of every template using `- name:` list form
- Every parameter has an explicit `type` and sensible `default`
- Use `displayName` when it adds queue-time UX value

**Collection types:**
- `stepList` under `steps:`, `jobList` under `jobs:`, `stageList` under `stages:`
- `stringList` only in root consumer pipelines (queue-time multi-select UX)
- Shared templates must use `object` instead of `stringList`

**Expression rules:**
- Template expressions (`${{ if }}`) for structural decisions; runtime `condition:` for execution decisions
- `${{ if }}` / `${{ elseif }}` / `${{ else }}` / `${{ end }}` must occupy the **entire** YAML value — never embed inside a quoted string
  - ✅ `isDraft: ${{ if eq(parameters.releaseType, 'draft') }}true${{ else }}false${{ end }}`
  - ❌ `isDraft: "${{ if eq(parameters.releaseType, 'draft') }}'true'${{ else }}'false'${{ end }}"`

**Hook rules:** extension hooks use `pre*Steps` / `post*Steps`; document every hook in the family `README.md`.

## Naming Conventions

- `Pipeline/Pipeline.yml` — top-level family entry point
- `Stages/<Action>.yml`, `Jobs/<Action>.yml`, `Templates/Standalone/Steps/<Area>/<Action>.yml`
- Parameter names: descriptive camelCase (`buildVariableTemplatePath`, `gitHubConnection`, `workingDirectory`)
- Stage/job identifiers: stable, machine-friendly; `displayName`: human-friendly
- For environment fan-out, include the environment name in stage/job identifiers

## YAML Style

- Two-space indentation; explicit `- name:` list form under `parameters:`
- Quote strings containing Azure expressions, special characters, or values that could be misread
- Explicit defaults rather than relying on task defaults when behavior matters
- One responsibility per template; keep step wrappers small and composable
- Add file header comments for non-obvious families; add `# why` comments for conditions; do not narrate obvious YAML
- Consumer-facing root pipelines: heavily documented; shared step wrappers: lightly documented

## Standalone Library Rules

- If two template families need the same step behavior, it belongs in `Templates/Standalone/Steps`
- If the shared behavior is a single task with a stable contract, create a thin wrapper template
- `Templates/Standalone/Stages/Security.yml` — reusable security scanning stage (npm audit, Semgrep, GitLeaks, SARIF publishing)

## Error Checking

After editing any `.yml` file in `Templates/`, always call the available error-checking tool on the modified file before considering the task done. Treat any Azure Pipelines LSP errors as blocking.

## Parameter Threading Rule

New parameters added to a job template must be threaded up through the full chain:
`Jobs/<X>.yml` → `Stages/Build.yml` → `Pipeline/Pipeline.yml`

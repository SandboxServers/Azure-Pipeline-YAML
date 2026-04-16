# AGENTS.md

This repository is the shared Azure Pipelines template library for our projects.

Its job is to provide reusable pipeline building blocks that can be composed by consumer repositories without duplicating stage, job, step, or scripting logic. Consumer repositories own their triggers, queue-time parameters, and repo-specific variable files. This repository owns the reusable pipeline contracts and implementation.

## Purpose

Use this repo to:

- publish reusable pipeline families under `Templates/<Template-Name>`
- publish generic cross-cutting building blocks under `Templates/Standalone`
- centralize pipeline logic that would otherwise be copied between repos
- keep pipeline behavior consistent across projects

Do not use this repo to:

- store application-specific secrets
- hard-code repo-specific paths, service connections, or branch names unless the template is explicitly for one product family
- bury business logic in large inline scripts when a first-party or reputable marketplace task exists

## Repository Structure

The preferred structure for a reusable pipeline family is:

```text
Templates/
  <Template-Family>/
    Pipeline/
      Pipeline.yml
    Stages/
      *.yml
    Jobs/
      *.yml
    README.md
```

Reusable primitives that may be shared across many families belong in:

```text
Templates/
  Standalone/
    Steps/
    Jobs/
    Stages/
```

Structure rules:

- `Pipeline/` defines the top-level shared contract for a template family.
- `Stages/` composes jobs and stage-level orchestration.
- `Jobs/` composes steps and job-level orchestration.
- `Steps/` inside a feature template should be avoided when the logic can live in `Templates/Standalone/Steps`.
- `Templates/Standalone/Steps` is the default home for reusable step wrappers.
- `Templates/Standalone/Jobs` is for reusable jobs that are generic enough to span multiple families.
- `Templates/Standalone/Stages` is for reusable stage-level capabilities such as security scanning.
- If a feature family does not need local step files, leave that folder out rather than duplicating wrappers.

## Design Principles

- Prefer first-party Azure DevOps tasks first.
- If a first-party task does not fit, prefer a reputable marketplace task.
- Use custom script only when tasks cannot express the required behavior.
- Wrap first-party tasks in shared step templates when doing so creates a reusable contract.
- Keep custom scripts narrow, well-scoped, and easy to replace later.
- Optimize for composition over copy/paste.
- Prefer templates that are generic enough to reuse, but not so abstract that they become hard to read.
- The consumer repo should own repo-specific values; the shared template should own flow and structure.

## Built-In Task Policy

When implementing pipeline behavior:

- Use task-native inputs before falling back to shell arguments.
- Use `Npm@1`, `UseNode@1`, `UseDotNet@2`, `PublishPipelineArtifact@1`, `DownloadPipelineArtifact@2`, `GitHubRelease@1`, and similar tasks directly where they fit.
- If a task supports a built-in command such as `ci`, `install`, `publish`, `build`, or `test`, use that mode before using a custom script.
- Only use `command: custom` or script-based execution when the built-in task cannot model the required operation.
- Do not write PowerShell or Bash wrappers around a task solely to pass through inputs the task already supports.

Custom script is appropriate for cases like:

- deriving metadata from files and exposing it as pipeline variables
- generating manifest files or release-note files
- orchestrating CLI operations that Azure DevOps does not provide a suitable task for
- handling artifact post-processing that is too specific for a built-in task

## Ownership Boundaries

Consumer repositories should own:

- `trigger`, `pr`, and queue-time UX in the root `azure-pipelines.yml`
- repo-specific variable templates such as `global.yml`, `build.yml`, `dev.yml`, `prod.yml`
- service connection names, repository names, environment lists, and product-specific defaults

This repository should own:

- reusable `extends` templates
- shared stage/job/step composition
- parameter contracts for template families
- reusable wrapper steps around Azure DevOps tasks

## Variable Strategy

Shared templates should load variables from the consumer repo with `@self` wherever practical.

Preferred split:

- `global.yml` for settings shared across all stages
- `build.yml` for build/package behavior
- `<environment>.yml` such as `dev.yml`, `staging.yml`, `prod.yml` for environment-specific release or deployment settings

Rules:

- Do not centralize consumer-specific values inside this repo.
- Do not use a single catch-all variable file when the settings naturally split by lifecycle or environment.
- Prefer explicit template path parameters such as `globalVariableTemplatePath`, `buildVariableTemplatePath`, and `environmentVariableTemplateDirectory`.
- Keep variable names stable and descriptive.
- Do not put secrets in shared template defaults.

## Parameters And Expressions

Parameter rules:

- Put `parameters:` at the top of every template.
- Give every parameter an explicit type.
- Give every optional parameter a sensible default.
- Use `displayName` only when it adds value to queue-time UX or readability.
- Prefer typed parameters over magic string variables when the shape matters.

Expression rules:

- Use template expressions for structural decisions.
- Use runtime `condition:` for execution decisions.
- Keep condition logic readable even if it is a little longer.
- Prefer one well-named parameter over repeated complex expressions.

Collection rules:

- Use `stepList` for step injection under `steps:`.
- Use `jobList` only under `jobs:`.
- Use `stageList` only under `stages:`.
- Root pipelines may use `stringList` for queue-time multi-select UX.
- Shared templates should use `object` instead of `stringList`, since `stringList` is not available in templates.

Hook rules:

- Extension hooks should usually be `pre*Steps` and `post*Steps`.
- Document every hook in the family `README.md` and in consumer examples.
- In hook examples, prefer calling shared step templates from `Templates/Standalone` instead of inlining scripts.

## Naming Conventions

Use consistent names for files and parameters.

Preferred patterns:

- `Pipeline/Pipeline.yml` for the top-level family entry point
- `Stages/<Action>.yml`
- `Jobs/<Action>.yml`
- `Templates/Standalone/Steps/<Area>/<Action>.yml`

Parameter naming:

- Use descriptive camelCase names such as `buildVariableTemplatePath`, `environmentVariableTemplateDirectory`, `gitHubConnection`, `workingDirectory`
- Avoid abbreviations unless they are common Azure terms such as `acr`, `sdk`, or `vmImage`
- Use names that reflect behavior, not implementation details

Stage/job naming:

- Keep `stage:` and `job:` identifiers stable and machine-friendly
- Keep `displayName:` values human-friendly and demo-friendly
- For environment fan-out, include the environment name in the stage or job identifier

## YAML Style

The repo contains some older style variation. New and updated work should follow these conventions:

- Prefer the explicit list form under `parameters:` using `- name:`
- Keep indentation consistent at two spaces
- Quote strings when they contain Azure expressions, special characters, or values that could be misread by YAML
- Keep defaults explicit instead of relying on task defaults when those defaults are important to behavior
- Keep one responsibility per template whenever possible
- Keep wrappers small and composable

Use comments intentionally:

- Add a file header comment when the template family or stage is non-obvious
- Add short comments that explain why a branch or condition exists
- Do not narrate obvious YAML
- Consumer-facing root pipelines should be heavily documented
- Shared step wrappers should be lightly documented and stay compact

## Standalone Library Rules

`Templates/Standalone` is the shared library for this repo.

Rules:

- If two template families need the same step behavior, it belongs in `Templates/Standalone/Steps`
- If the shared behavior is a single task with a stable contract, create a thin wrapper template
- If the behavior is still too product-specific, keep it in the feature family until a second real consumer exists
- Standalone wrappers should expose reusable parameters, not consumer-specific assumptions
- Avoid adding feature-specific defaults to Standalone templates

## Documentation Expectations

Every reusable template family should have a `README.md` that includes:

- what the template does
- a minimal consumer example
- required resources aliases such as `@pipelinePatterns`
- required consumer-owned variable files
- parameter documentation
- hook documentation
- notable assumptions and limitations

When a contract changes:

- update the family `README.md`
- update consumer examples if this repo contains them
- update any comments in root consumer pipelines that demonstrate usage

## Validation Expectations

Before finishing a change:

- read back the edited YAML for correctness
- run `git diff --check`
- sanity-check relative template paths
- verify parameter names line up across pipeline, stage, job, and step templates
- verify `@self` references point to consumer-owned files, not this repo
- state clearly if Azure DevOps validation or a real pipeline run was not performed

If a change affects task inputs or task behavior:

- confirm the current task contract against Microsoft Learn
- prefer current first-party docs over memory

## Demo Quality Standard

This repo is meant to be shown, reused, and trusted.

Showroom-quality templates should feel:

- obvious to adopt
- well-documented
- low-duplication
- strongly typed
- opinionated in the right places
- flexible without becoming vague

If a future contributor has to ask “why is this custom script here?” the answer should be easy to find in the template or its README.

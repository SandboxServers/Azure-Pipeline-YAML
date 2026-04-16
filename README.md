# Azure-Pipeline-YAML

Shared Azure Pipelines template library for Sandbox Servers projects.

This repo exists so application repositories can consume consistent, reusable pipeline patterns instead of re-implementing stages, jobs, tasks, and helper scripts over and over. Consumer repos keep ownership of triggers, repo-specific variables, service connections, and environment choices. This repo provides the reusable pipeline contracts and implementation.

## What Lives Here

This repository contains two kinds of pipeline assets:

- template families under `Templates/<Family>` for opinionated end-to-end pipeline patterns
- shared primitives under `Templates/Standalone` for reusable steps, jobs, and stages

Current template families:

- `Templates/NPM-GitHub-Release`
  Builds Node/NPM apps, packages them with `npm pack`, publishes artifacts, and creates or previews GitHub releases.
- `Templates/Container-Build`
  Reusable container build and cleanup flow for building and publishing Docker images.
- `Templates/Dhadgar.CI`
  Meridian Console-oriented CI/CD composition for build, package, infrastructure, and deployment workflows.
- `Templates/SWA+Functions+SQL`
  Static Web App, Functions, and SQL deployment pattern with environment fan-out.
- `Templates/Standalone`
  Shared library of reusable step, job, and stage templates used across families.

## Design Goals

- keep shared pipeline behavior in one place
- prefer composition over copy/paste
- prefer first-party Azure DevOps tasks and reputable marketplace tasks over custom scripts
- keep consumer repositories in control of their own variables and release settings
- make template contracts explicit, typed, and documented

The operating rules for contributors live in [AGENTS.md](./AGENTS.md).

## Repository Layout

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

  Standalone/
    Steps/
    Jobs/
    Stages/

scripts/
  *.ps1
```

How to read that structure:

- `Pipeline/` is the top-level entry point a consumer repo extends.
- `Stages/` composes jobs into larger workflow units.
- `Jobs/` composes steps into a reusable unit of work.
- `Standalone/Steps` contains shared task wrappers and narrow helper logic.
- `Standalone/Jobs` and `Standalone/Stages` contain larger reusable units when multiple families need the same orchestration.

## How Consumer Repos Use This

The normal consumption model is:

1. add this repo as a template resource
2. keep repo-specific variables in the consumer repo
3. extend one of the shared pipeline families

Example:

```yaml
resources:
  repositories:
    - repository: pipelinePatterns
      type: github
      endpoint: github.com_SandboxServers
      name: SandboxServers/Azure-Pipeline-YAML
      ref: refs/heads/main

extends:
  template: Templates/NPM-GitHub-Release/Pipeline/Pipeline.yml@pipelinePatterns
  parameters:
    globalVariableTemplatePath: '/pipeline/variables/global.yml'
    buildVariableTemplatePath: '/pipeline/variables/build.yml'
    environmentVariableTemplateDirectory: '/pipeline/variables'
    vmImage: '$(vmImage)'
    environments: ${{ parameters.environments }}
```

In this model:

- the consumer repo owns `trigger`, `pr`, root parameters, and variable files
- this repo owns the reusable stage/job/step structure
- consumer variables are typically loaded from `@self`

## Variable Ownership Pattern

Shared templates in this repo should generally read repo-specific variables from the consuming repository rather than hard-coding values here.

Preferred split in consumer repos:

- `pipeline/variables/global.yml`
- `pipeline/variables/build.yml`
- `pipeline/variables/dev.yml`
- `pipeline/variables/staging.yml`
- `pipeline/variables/prod.yml`

That pattern keeps:

- shared settings in `global.yml`
- build/package behavior in `build.yml`
- environment-specific release or deployment behavior in `<environment>.yml`

## Built-In Task First

The default implementation rule in this repo is simple:

- use first-party Azure DevOps tasks when they support the behavior we need
- use a reputable marketplace task when Azure provides no good first-party option
- use custom PowerShell or Bash only when task-based configuration cannot express the behavior

Examples already in the repo:

- `UseNode@1` via `Templates/Standalone/Steps/Node/UseNode.yml`
- `Npm@1` via `Templates/Standalone/Steps/Npm/Run.yml`
- `PublishPipelineArtifact@1` and `DownloadPipelineArtifact@2`
- `GitHubRelease@1` via `Templates/Standalone/Steps/GitHub/CreateRelease.yml`

Custom script remains appropriate for things like:

- deriving package metadata from `package.json`
- creating release note files or manifest files
- performing CLI flows that do not have a good task equivalent

## Standalone First Reuse

If logic can be written once and reused across families, it should usually live in `Templates/Standalone`.

Rules of thumb:

- if two families need the same step behavior, move it to `Templates/Standalone/Steps`
- if a wrapper is mostly a typed façade over a built-in task, that is a good use of `Standalone`
- if the logic is still very product-specific, keep it in the feature family until a second real consumer appears

This is why some family folders intentionally omit a local `Steps` folder and compose shared standalone steps instead.

## Template Authoring Conventions

New and updated templates should follow these conventions:

- put `parameters:` first
- give parameters explicit types and sensible defaults
- prefer `- name:` parameter syntax
- use template expressions for structure and runtime `condition:` for execution gating
- use `stepList` hook points for step injection where extension is expected
- use `object` parameters inside templates when a root pipeline might expose a `stringList`
- keep stage and job identifiers stable and machine-friendly
- keep `displayName` values easy for humans to scan in Azure DevOps

For consumer-facing root pipelines, comment heavily and document every supported parameter, including optional ones. For shared wrappers, keep comments lighter and focused on the non-obvious parts.

## Template Families

### NPM-GitHub-Release

Reusable Node/NPM release pipeline with:

- Node setup
- npm restore/build/test
- optional npm cache
- package creation with `npm pack`
- artifact publishing
- GitHub release preview or publish

Start with [Templates/NPM-GitHub-Release/README.md](./Templates/NPM-GitHub-Release/README.md).

### Container-Build

Reusable container build pattern for Docker-based services, including image build and optional cleanup behavior.

Start with [Templates/Container-Build/Pipeline/Pipeline.yml](./Templates/Container-Build/Pipeline/Pipeline.yml).

### Dhadgar.CI

Larger opinionated CI/CD pattern for Meridian Console workloads, including build, packaging, container publishing, infrastructure, and deployment concerns.

Architecture notes live in [Templates/Dhadgar.CI/CONTAINER-BUILD-ARCHITECTURE.md](./Templates/Dhadgar.CI/CONTAINER-BUILD-ARCHITECTURE.md).

### SWA+Functions+SQL

Environment-aware deployment pattern for Static Web Apps, Azure Functions, and SQL assets.

This family already follows the “use shared standalone steps where possible” direction and leaves `Templates/SWA+Functions+SQL/Steps` intentionally empty.

## Validation And Change Hygiene

When changing templates in this repo:

- read back the YAML after editing it
- run `git diff --check`
- sanity-check relative template paths and parameter names
- update the relevant family `README.md` when a contract changes
- call out clearly if a change was not validated in Azure DevOps with a real pipeline run

If you are contributing new patterns or refactoring old ones, read [AGENTS.md](./AGENTS.md) first.

## Contributing

Contributions should make the library:

- more reusable
- more explicit
- better documented
- less dependent on custom script where built-in tasks would do

Good contributions usually:

- extract common logic into `Templates/Standalone`
- reduce repo-specific assumptions
- tighten parameter contracts
- improve consumer documentation
- preserve or improve demo/readability quality

Poor contributions usually:

- copy existing YAML into a new family without extracting shared pieces
- hide behavior in ad hoc scripts
- hard-code values that belong in the consumer repo
- add abstractions that are more clever than useful

## Related Files

- [AGENTS.md](./AGENTS.md)
- [Templates/NPM-GitHub-Release/README.md](./Templates/NPM-GitHub-Release/README.md)
- [Templates/Dhadgar.CI/CONTAINER-BUILD-ARCHITECTURE.md](./Templates/Dhadgar.CI/CONTAINER-BUILD-ARCHITECTURE.md)

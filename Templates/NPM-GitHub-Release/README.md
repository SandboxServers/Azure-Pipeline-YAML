# NPM GitHub Release Template

Reusable Azure Pipelines template for Node/NPM applications that:

- installs Node with `UseNode@1`
- optionally restores npm cache with `Cache@2`
- runs npm commands through the first-party `Npm@1` task
- creates a distributable package with `npm pack`
- publishes pipeline artifacts
- creates or previews a GitHub release with `GitHubRelease@1`

## Consumer Pattern

Repository pipelines keep repo-specific variables in `@self` and extend the shared template:

```yaml
trigger:
  branches:
    include:
      - main
  tags:
    include:
      - v*

pr:
  branches:
    include:
      - main

variables:
  - template: pipeline/variables/global.yml

parameters:
  - name: environments
    type: stringList
    default:
      - dev
    values:
      - dev
      - staging
      - prod

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

## Template Parameters

`Pipeline/Pipeline.yml`

- `globalVariableTemplatePath`: self-repo global variables template path
- `buildVariableTemplatePath`: self-repo build variables template path
- `environmentVariableTemplateDirectory`: self-repo environment variable directory
- `vmImage`: agent image
- `environments`: selected release environments as an object/list
- `buildStageName`: build stage name
- `releaseStageName`: release stage name
- `preBuildSteps`: shared hook point inserted before build/install steps
- `postBuildSteps`: shared hook point inserted after artifact publish
- `preReleaseSteps`: shared hook point inserted before release preview/publish
- `postReleaseSteps`: shared hook point inserted after release preview/publish

## Required Self Variables

Recommended self variable files:

- `/pipeline/variables/global.yml`
- `/pipeline/variables/build.yml`
- `/pipeline/variables/dev.yml`
- `/pipeline/variables/staging.yml`
- `/pipeline/variables/prod.yml`

Core variables:

- `vmImage`
- `nodeVersion`
- `npmWorkingDirectory`
- `packageJsonPath`
- `npmInstallCommand`
- `npmInstallCustomCommand`
- `npmBuildCommand`
- `npmTestCommand`
- `packageArtifactName`
- `githubServiceConnection`
- `githubRepositoryName`

Useful optional variables:

- `npmPackArgs`
- `enableNpmCache`
- `npmCacheDirectory`
- `npmCacheKeyFile`
- `gitHubReleaseDryRun`
- `gitHubReleaseDraft`
- `gitHubReleasePreRelease`
- `gitHubReleaseMakeLatest`
- `gitHubReleaseAddChangeLog`
- `gitHubReleaseChangeLogType`
- `gitHubReleaseChangeLogLabels`
- `releaseTitleFormat`
- `releaseTagFormat`

## Demo Mode

Set in the relevant environment variable file:

```yaml
- name: gitHubReleaseDryRun
  value: 'true'
```

This still runs the release stage, downloads the packaged artifact, and prints a release preview without creating a GitHub release.

## Workspaces

For workspace or other advanced npm scenarios, prefer built-in task modes first:

- use `npmInstallCommand: ci` or `npmInstallCommand: install` for standard dependency restore
- use `npmInstallCommand: custom` plus `npmInstallCustomCommand` only when native `Npm@1` inputs are not enough
- use `npmBuildCommand` / `npmTestCommand` as full custom npm commands, for example `run build --workspace packages/my-package`

Example:

```yaml
- name: npmWorkingDirectory
  value: .
- name: npmInstallCommand
  value: custom
- name: npmInstallCustomCommand
  value: ci --workspace packages/my-package
- name: npmBuildCommand
  value: run build --workspace packages/my-package
```

## Environment Variables

Environment-specific release behavior comes from files named after the selected
environment, for example:

- `/pipeline/variables/dev.yml`
- `/pipeline/variables/staging.yml`
- `/pipeline/variables/prod.yml`

These files can override release title/tag formats, draft status, prerelease
status, and other release behavior per environment.

## Shared Standalone Steps Used

- `Templates/Standalone/Steps/Node/UseNode.yml`
- `Templates/Standalone/Steps/Cache/Restore.yml`
- `Templates/Standalone/Steps/Npm/Run.yml`
- `Templates/Standalone/Steps/Npm/ResolvePackageMetadata.yml`
- `Templates/Standalone/Steps/Npm/Pack.yml`
- `Templates/Standalone/Steps/Artifacts/PublishPipelineArtifact.yml`
- `Templates/Standalone/Steps/Artifacts/DownloadPipelineArtifact.yml`
- `Templates/Standalone/Steps/GitHub/CreateRelease.yml`
- `Templates/Standalone/Steps/GitHub/PreviewRelease.yml`

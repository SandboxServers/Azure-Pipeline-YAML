## Azure Pipelines YAML Authoring

This repository is a shared Azure Pipelines YAML template library. Every `.yml` file under `Templates/` is an Azure Pipelines template consumed via `extends` or `template` references from other repos.

### Error checking
After editing any `.yml` file in this repo, always call `get_errors` on the modified file before considering the task complete. The Azure Pipelines LSP (`ms-azure-devops.azure-pipelines`) is active on all files in `Templates/` via `files.associations`. Treat any LSP errors as blocking.

### Template conventions
- `${{ if }}` / `${{ elseif }}` / `${{ else }}` / `${{ end }}` expressions must occupy the **entire** YAML value — never embed them inside a quoted string (e.g. `isDraft: ${{ if ... }}true${{ else }}false${{ end }}`, not `isDraft: "${{ if ... }}'true'${{ end }}"`)
- All jobs that have ordering requirements must declare `dependsOn` explicitly
- New parameters added to a job template must be threaded up through the full chain: Job template → Stage template (Stages/Build.yml) → Pipeline template (Pipeline/Pipeline.yml)
- Consumer pipelines `extends` from `Templates/NPM-GitHub-Release/Pipeline/Pipeline.yml@pipelinePatterns`
- `stringList` parameters are only valid at the root consumer pipeline level; the shared template receives them as `object`

# Security Stage Artifacts

The Security stage produces **SARIF (Static Analysis Results Interchange Format)** files that contain security findings from each scanner. These artifacts are automatically processed and posted to GitHub PRs.

## What Are SARIF Files?

SARIF is a standard JSON format for static analysis tool output. Each scanner produces a `.sarif` file containing:
- **Rule violations** (e.g., SQL injection vulnerability)
- **Severity levels** (Critical, High, Medium, Low)
- **File locations** and line numbers
- **Remediation guidance**

## Artifacts Published by Security Stage

| Artifact Name | Scanner | Contents | Purpose |
|---------------|---------|----------|---------|
| `security-sast-semgrep` | Semgrep (SAST) | Code vulnerabilities (SQL injection, XSS, etc.) | Posted to PR as "🔍 Semgrep (SAST)" comment |
| `security-sca-owasp` | OWASP Dependency-Check (SCA) | Vulnerable dependencies (NuGet packages) | Posted to PR as "📦 OWASP Dependency-Check (SCA)" comment |
| `security-container-*` (13 artifacts) | Trivy (Container) | Vulnerabilities in container images | Posted to PR as "🐳 Trivy (Container)" comment |
| `security-iac-checkov` | Checkov (IaC) | Infrastructure misconfigurations (Dockerfile, YAML) | Posted to PR as "🏗️ Checkov (IaC)" comment |
| `security-secrets-gitleaks` | GitLeaks (Secrets) | Exposed secrets (API keys, passwords) | Posted to PR as "🔑 GitLeaks (Secrets)" comment |
| `sbom-container-*` (13 artifacts) | Syft (SBOM) | Software Bill of Materials (package inventory) | For compliance/auditing, not posted to PR |

## What Happens to These Artifacts?

### 1. PostToGitHubPR Job (Automatic)

The `PostToGitHubPR` job (last job in Security stage) automatically:

1. **Downloads all SARIF artifacts** from the Security stage
2. **Parses findings** using [`scripts/Post-SecurityFindings.ps1`](../../../c:/Users/Steve/source/projects/Azure-Pipeline-YAML/scripts/Post-SecurityFindings.ps1)
3. **Posts formatted comments** to the GitHub PR (one comment per scanner)
4. **Updates existing comments** if re-running (idempotent)

**Condition**: Only runs on PR builds (`Build.Reason == 'PullRequest'`)

**Example PR Comment** (Semgrep findings):

```markdown
## 🛡️ Security Scan Results: Semgrep (SAST)

🔍 **Semgrep (SAST)**: Found **12** issue(s)

🔴 3 Critical | 🟠 5 High | 🟡 4 Medium

<details>
<summary>🔴 <strong>Critical Severity (3)</strong></summary>

**sql-injection**: Potential SQL injection vulnerability detected
- Location: `src/Dhadgar.Billing/BillingService.cs (Line 42)`

...
</details>

---
📊 [View full scan results in Azure Pipelines](https://dev.azure.com/...)
```

### 2. Azure DevOps Artifacts (Manual Review)

All artifacts are also available in the Azure Pipelines UI:

1. Go to your pipeline run
2. Click **Artifacts** tab
3. Download any artifact to review locally

**When to manually review:**
- Debugging scanner issues
- Auditing false positives
- Compliance documentation
- Investigating specific vulnerabilities

### 3. SBOM Artifacts (Compliance)

The `sbom-container-*` artifacts are **not** posted to PRs but are kept for:
- **Supply chain transparency**: Know exactly what's in your images
- **Compliance audits**: SOC 2, ISO 27001 evidence
- **License tracking**: Identify GPL/LGPL dependencies
- **Incident response**: Quickly identify affected systems if a CVE is announced

## Scanner Behavior (Non-Blocking)

All scanners are configured to **not fail the pipeline** when they find issues:

| Scanner | Behavior | Reason |
|---------|----------|--------|
| **Semgrep** | `continueOnError: true` | Findings reported in PR, dev decides priority |
| **OWASP Dependency-Check** | `continueOnError: true` | Vulnerable deps may be accepted risk |
| **Trivy** | `--exit-code 0` | Container vulns common in base images |
| **Checkov** | `--soft-fail` | IaC policies may be intentionally violated |
| **GitLeaks** | `--exit-code 0` | False positives common (e.g., example code) |
| **Syft** | SBOM generation, never fails | Inventory tool, not a vulnerability scanner |

**Exception**: You can configure `failOnCritical: true` in pipeline parameters to block PRs with critical vulnerabilities.

## Reducing False Positives

### GitLeaks (Secrets)

The pipeline found 12 "secrets" in your docs:

```
Finding:     curl -u dhadgar:dhadgar http://localhost:15...
File:        docs/DEVELOPMENT_SETUP.md
Line:        284
```

**These are false positives** (development credentials in docs). To suppress:

Create `.gitleaksignore` in repo root:

```
# Development credentials in documentation
docs/DEVELOPMENT_SETUP.md:284:curl-auth-user
docs/SPIRIT_OF_THE_DIFF_SETUP.md:141:private-key
```

### Checkov (IaC)

Checkov failed on agent Dockerfile:

```
CKV_DOCKER_3: Ensure that a user for the container has been created
CKV_DOCKER_2: Ensure that HEALTHCHECK instructions have been added
```

**These are acceptable for Azure DevOps agents** (runs as `azp` user, health managed by Azure Pipelines).

To suppress, add comment to Dockerfile:

```dockerfile
# checkov:skip=CKV_DOCKER_3:Agent runs as azp user (line 85)
# checkov:skip=CKV_DOCKER_2:Health managed by Azure Pipelines
FROM ubuntu:24.04
```

## Artifact Retention

Azure DevOps retains artifacts based on your retention policy:

- **Default**: 30 days for successful runs, 365 days for failed runs
- **Customize**: Project Settings → Pipelines → Retention
- **Cost**: ~$0.01/GB/month for artifact storage

**Recommendation**: Keep artifacts for 90 days for security auditing.

## Viewing SARIF Files Locally

### VS Code (Recommended)

Install the **SARIF Viewer** extension:

1. Install: [SARIF Viewer - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=MS-SarifVSCode.sarif-viewer)
2. Open any `.sarif` file
3. View findings in a rich UI with jump-to-source

### PowerShell (Quick Inspection)

```powershell
# Download artifact from Azure Pipelines
$sarif = Get-Content "semgrep.sarif" | ConvertFrom-Json

# Count findings by severity
$sarif.runs.results | Group-Object level | Select Name, Count

# List all rule IDs
$sarif.runs.results.ruleId | Sort-Object -Unique
```

### Command Line (JSON Query)

```bash
# Using jq (Linux/macOS)
jq '.runs[].results[] | {rule: .ruleId, severity: .level, file: .locations[0].physicalLocation.artifactLocation.uri}' semgrep.sarif
```

## Integration with GitHub Advanced Security (Optional)

If you have **GitHub Advanced Security** (GHAS) enabled, you can upload SARIF files to GitHub's code scanning:

```yaml
- task: GithubAdvancedSecurityPublishSarif@0
  inputs:
    sarifFilePath: '$(Pipeline.Workspace)/security-artifacts/semgrep.sarif'
    github_token: $(GITHUB_PAT)
```

This enables:
- **Security tab** in GitHub repo with all findings
- **Pull request checks** that block merge
- **Code annotations** directly in PR diff
- **Dependency graph** integration

## Troubleshooting

### "No artifacts found"

**Cause**: Scanner failed before producing SARIF file.

**Fix**: Check scanner job logs for errors. Common issues:
- Semgrep: Missing config or metrics disabled
- OWASP: Database connection failure (add `--data` flag)
- Trivy: Wrong image name (ensure docker load succeeded)

### "Duplicate PR comments"

**Cause**: Comment markers missing or changed.

**Fix**: The script uses hidden HTML comments to identify existing comments:

```html
<!-- security-scan-semgrep -->
```

If you manually edited/deleted a comment, the script will create a new one. Delete all security comments and re-run the pipeline.

### "SARIF file is empty"

**Cause**: Scanner found no issues (good!) or crashed.

**Fix**: Check `$LASTEXITCODE` in scanner job logs:
- `0` = No findings (empty SARIF is expected)
- `1` = Findings reported (SARIF should have content)
- `2` = Scanner error (check stderr output)

### "OWASP Dependency-Check slow on first run"

**Cause**: The NVD database needs to be downloaded on first run (~200MB).

**Expected behavior**:
- First run: 5-15 minutes (database download)
- Subsequent runs: 2-5 minutes (incremental updates)

**Note**: The database is stored in `$(Agent.TempDirectory)/dependency-check-data` which is ephemeral. If you want persistence across pipeline runs:

1. Create a persistent volume for the agent:
   ```yaml
   # In agent-swarm.yml
   volumes:
     - dependency-check-data:/azp/_work/_tool/dependency-check-data
   ```

2. Update Security.yml to use the persistent path:
   ```yaml
   $dataDir = "/azp/_work/_tool/dependency-check-data"
   ```

This trades disk space (~500MB) for faster subsequent scans.

## Related Documentation

- [Security Scanner Setup](SECURITY-SCANNER-SETUP.md)
- [PR Comment Automation](SECURITY-PR-COMMENTS.md)
- [Agent Pre-installed Tools](../../../c:/Users/Steve/source/projects/MeridianConsole/deploy/azure-pipelines/AGENT-SECURITY-TOOLS.md)
- [SARIF Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)

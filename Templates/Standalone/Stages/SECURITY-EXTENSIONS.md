# Security Scanner Extensions for Azure DevOps

The Security stage integrates with Azure DevOps marketplace extensions to display SARIF results directly in the pipeline UI.

## Installed Extensions

### 1. **Microsoft Security DevOps**

**Extension**: [Microsoft Security DevOps](https://marketplace.visualstudio.com/items?itemName=ms-securitydevops.microsoft-security-devops-azdevops)

**What it does**:
- Adds a **Security** tab to your repo
- Shows security findings across all builds
- Trending/historical vulnerability analysis
- Integration with Microsoft Defender for Cloud

**How we use it**:
The `PublishToSecurityDevOps` job (Job 8) uploads SARIF files using:
- `DownloadPipelineArtifact@2` - Downloads all SARIF artifacts from scanner jobs
- `PublishBuildArtifacts@1` - Publishes SARIF files to `CodeAnalysisLogs` artifact (extension automatically discovers this)

**Where to view results**:
```
https://dev.azure.com/SandboxServers/MeridianConsole/_git/MeridianConsole?_a=security
```

Or click **Repos** → Your repository → **Security** tab

**Features**:
- ✅ View all findings grouped by severity
- ✅ Filter by scanner (Semgrep, Trivy, etc.)
- ✅ Trend analysis (are vulnerabilities increasing?)
- ✅ Export to CSV
- ✅ Integration with work items (create bug from finding)

### 2. **SARIF SAST Scans Tab**

**Extension**: [SARIF SAST Scans Tab](https://marketplace.visualstudio.com/items?itemName=sariftools.sarif-viewer-build-tab)

**What it does**:
- Adds a **SARIF Results** tab to each pipeline run
- Auto-detects SARIF files in pipeline artifacts
- Displays findings grouped by severity and scanner

**How we use it**:
No configuration needed! The extension automatically discovers SARIF files from published artifacts:
- `security-sast-semgrep`
- `security-sca-owasp`
- `security-container-*` (13 artifacts)
- `security-iac-checkov`
- `security-secrets-gitleaks`

**Where to view results**:
1. Go to your pipeline run
2. Click the **SARIF Results** tab (next to Summary, Tests, etc.)
3. See all findings with drill-down by scanner

**Features**:
- ✅ Per-build security snapshot
- ✅ Filterable by severity/scanner/rule
- ✅ Jump to file location (if repo is checked out)
- ✅ Inline rule descriptions
- ✅ Export findings

## Comparison: Where to View Security Results

| Location | What You See | Best For |
|----------|--------------|----------|
| **GitHub PR Comments** | Formatted markdown with findings from current build | Quick review during PR |
| **SARIF Results Tab** | Detailed findings for current pipeline run | Debugging specific build |
| **Security Tab** (Microsoft Security DevOps) | Historical trends across all builds | Tracking vulnerability debt over time |
| **Artifacts** (manual download) | Raw SARIF JSON files | Compliance evidence, offline analysis |

## Pipeline Integration

The Security stage automatically publishes results to both extensions:

```yaml
stages:
  - template: Templates/Standalone/Stages/Security.yml
    parameters:
      runSecurityScans: true
      # ... other params
```

**Jobs that enable extensions:**

1. **Scanners** (Jobs 1-6) → Publish SARIF artifacts
   - `PublishPipelineArtifact@1` with `artifactName: 'security-*'`
   - These artifacts are auto-detected by **SARIF SAST Scans Tab**

2. **PostToGitHubPR** (Job 7) → GitHub PR comments
   - Downloads all SARIF artifacts
   - Posts formatted comments to PR

3. **PublishToSecurityDevOps** (Job 8) → Microsoft Security DevOps
   - Downloads all SARIF artifacts
   - Publishes to `CodeAnalysisLogs` artifact using `PublishBuildArtifacts@1`
   - Extension automatically discovers and populates Security tab

## Viewing Results After Pipeline Run

### Option 1: SARIF Results Tab (Per-Build View)

1. Navigate to your pipeline run:
   ```
   https://dev.azure.com/SandboxServers/MeridianConsole/_build/results?buildId=<BUILD_ID>
   ```

2. Click **SARIF Results** tab

3. You'll see findings grouped like:
   ```
   🔍 Semgrep (SAST): 12 findings
   ├─ 🔴 Critical (3)
   ├─ 🟠 High (5)
   └─ 🟡 Medium (4)

   📦 OWASP Dependency-Check (SCA): 8 findings
   ├─ 🔴 Critical (2)
   └─ 🟠 High (6)

   🐳 Trivy (Container): 45 findings across 13 images
   ...
   ```

4. Click any finding to see:
   - Full description
   - File path and line number
   - Remediation guidance
   - Rule references

### Option 2: Security Tab (Historical View)

1. Navigate to your repository:
   ```
   https://dev.azure.com/SandboxServers/MeridianConsole/_git/MeridianConsole
   ```

2. Click **Security** (if tab not visible, refresh page after first scan completes)

3. You'll see:
   - **Vulnerability Summary**: Total count by severity
   - **Trend Chart**: Vulnerabilities over time
   - **By Scanner**: Breakdown per tool (Semgrep, Trivy, etc.)
   - **By Category**: SAST, SCA, Container, IaC, Secrets

4. Click any vulnerability to:
   - See all instances across branches
   - Create work item
   - Mark as false positive
   - View fix recommendations

### Option 3: GitHub PR Comments (PR-Only View)

If the build was triggered by a PR, check the PR for comments from `spirit-of-the-diff[bot]`:

```markdown
## 🛡️ Security Scan Results: Semgrep (SAST)

🔍 **Semgrep (SAST)**: Found **12** issue(s)
...
```

## Extension Configuration

### Microsoft Security DevOps Settings

The extension automatically discovers SARIF files published to the `CodeAnalysisLogs` artifact. No additional configuration is required.

**Current pipeline behavior**:
- All scanners use `continueOnError: true` - findings are reported but don't block the build
- SARIF files are automatically processed and displayed in the Security tab
- Findings appear within minutes of pipeline completion

### SARIF SAST Scans Tab Settings

No configuration needed - works automatically!

**Customization** (optional):
1. Go to pipeline → **SARIF Results** tab
2. Click **⚙️ Settings** (top right)
3. Configure:
   - Default grouping (by severity/scanner/file)
   - Display options (show/hide rule details)
   - Export format preferences

## Troubleshooting

### "SARIF Results tab is empty"

**Cause**: No SARIF artifacts published or wrong artifact names.

**Fix**:
1. Go to pipeline run → **Artifacts** tab
2. Verify artifacts exist: `security-sast-semgrep`, `security-sca-owasp`, etc.
3. Download one and verify it's valid JSON:
   ```powershell
   Get-Content semgrep.sarif | ConvertFrom-Json
   ```

**Expected SARIF structure**:
```json
{
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": { "driver": { "name": "Semgrep" } },
      "results": [...]
    }
  ]
}
```

### "Security tab not visible"

**Cause**: Extension not enabled or first scan hasn't completed.

**Fix**:
1. Verify extension is installed: **Organization Settings** → **Extensions** → Search "Microsoft Security DevOps"
2. Wait for `PublishToSecurityDevOps` job to complete (Job 8)
3. Refresh the repository page
4. Check logs for `PublishBuildArtifacts@1` task errors

**Common error**: "No files found"
- The `DownloadPipelineArtifact@2` task failed
- Check that scanners completed and published artifacts
- Verify the `CodeAnalysisLogs` artifact exists in the Artifacts tab

### "Duplicate findings in Security tab"

**Cause**: Same vulnerability reported by multiple scanners (e.g., Semgrep + OWASP both find SQL injection).

**Expected behavior**: Microsoft Security DevOps deduplicates by file+line+rule. If you see duplicates:
- Different scanners may use different rule IDs
- Findings may be in different file locations

**Fix**: Mark duplicates as "False Positive" or "Won't Fix" in Security tab.

### "CodeAnalysisLogs artifact is empty or missing"

**Cause**: Scanner jobs failed to produce SARIF files or `DownloadPipelineArtifact@2` couldn't find them.

**Fix**:
1. Check that individual scanner jobs completed successfully and published artifacts:
   - `security-sast-semgrep`
   - `security-sca-owasp`
   - `security-container-*` (13 artifacts)
   - `security-iac-checkov`
   - `security-secrets-gitleaks`

2. Verify the `DownloadPipelineArtifact@2` task in Job 8 found files:
   - Check logs for "Downloaded X artifact(s)"
   - Look for warnings about missing artifacts

3. The `PublishBuildArtifacts@1` task has `continueOnError: true` - check if it logged any warnings

## Cost Considerations

### Microsoft Security DevOps Extension

**Free tier**:
- Unlimited scans
- Security tab access
- Trend analysis

**Paid tier** (Microsoft Defender for Cloud integration):
- ~$15/month per repository
- Not required for basic functionality

### SARIF SAST Scans Tab Extension

**Completely free** - no limits, no paid tiers.

### Artifact Storage

SARIF files consume artifact storage:
- Average size: 50KB - 5MB per scanner per build
- **Cost**: ~$0.01/GB/month
- **Example**: 100 builds/month × 5 scanners × 1MB = 500MB = $0.005/month

Negligible cost.

## Advanced: Custom SARIF Viewers

If you want a custom dashboard, you can query artifacts via REST API:

```powershell
# Get SARIF artifacts for a build
$buildId = 123
$org = "SandboxServers"
$project = "MeridianConsole"

$artifacts = Invoke-RestMethod `
  -Uri "https://dev.azure.com/$org/$project/_apis/build/builds/$buildId/artifacts?api-version=7.0" `
  -Headers @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }

# Download SARIF file
$sarifUrl = $artifacts.value | Where-Object { $_.name -eq "security-sast-semgrep" } | Select -ExpandProperty resource.downloadUrl
Invoke-RestMethod -Uri $sarifUrl -OutFile "semgrep.sarif"

# Parse findings
$sarif = Get-Content "semgrep.sarif" | ConvertFrom-Json
$findings = $sarif.runs.results
```

## Related Documentation

- [Security Scanner Setup](SECURITY-SCANNER-SETUP.md)
- [Security Artifacts Guide](SECURITY-ARTIFACTS.md)
- [PR Comment Automation](SECURITY-PR-COMMENTS.md)
- [Microsoft Security DevOps Docs](https://learn.microsoft.com/en-us/azure/defender-for-cloud/azure-devops-extension)
- [SARIF Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)

# Security Scanner PR Comments Setup

This guide explains how to configure the Security stage to automatically post scan results to GitHub Pull Requests.

## What It Does

When the Security stage runs on a PR build, it will:

1. Run all enabled scanners (SAST, SCA, Container, IaC, Secrets)
2. Collect SARIF findings from each scanner
3. Post formatted comments to the GitHub PR - one comment per scanner type
4. **Update existing comments** instead of creating duplicates (idempotent)
5. Display findings grouped by severity with collapsible sections

## Example PR Comment

```markdown
## 🛡️ Security Scan Results: Semgrep (SAST)

🔍 **Semgrep (SAST)**: Found **12** issue(s)

🔴 3 Critical | 🟠 5 High | 🟡 4 Medium

<details>
<summary>🔴 <strong>Critical Severity (3)</strong></summary>

**sql-injection**: Potential SQL injection vulnerability detected
- Location: `src/Dhadgar.Billing/BillingService.cs (Line 42)`

**command-injection**: Command injection risk in shell execution
- Location: `src/Dhadgar.Servers/ServerManager.cs (Line 128)`

</details>

---
📊 [View full scan results in Azure Pipelines](https://dev.azure.com/...)
```

## Setup Instructions

### 1. Create GitHub Personal Access Token (PAT)

The pipeline needs a GitHub PAT with `repo` scope to post comments.

**Steps:**

1. Go to: https://github.com/settings/tokens/new
2. **Note**: `Azure Pipelines Security Scanner`
3. **Expiration**: Choose appropriate expiration (90 days recommended, renewable)
4. **Scopes**: Check `repo` (full repo access)
   - This includes: `repo:status`, `repo_deployment`, `public_repo`, `repo:invite`
   - Required for: Creating/updating PR comments
5. Click **Generate token**
6. **Copy the token immediately** (you won't see it again!)

### 2. Add Token to Azure DevOps

#### Option A: Variable Group (Recommended - Reusable)

1. Go to: Azure DevOps → Pipelines → Library → Variable Groups
2. Find your existing `security-scanning` variable group (or create if needed)
3. Click **+ Add**
   - Name: `GITHUB_PAT`
   - Value: `<paste your GitHub PAT>`
   - Click the **lock icon** to mark as secret
4. Click **Save**
5. Go to **Pipeline permissions** tab
6. Click **+** and authorize the "Meridian Console" pipeline (or whichever pipeline uses this template)

#### Option B: Pipeline Variable (Quick - Single pipeline)

1. Go to: Azure DevOps → Pipelines → Select your pipeline
2. Click **Edit** → **Variables** (top right)
3. Click **+ New variable**
   - Name: `GITHUB_PAT`
   - Value: `<paste your GitHub PAT>`
   - Check **Keep this value secret**
4. Click **OK** → **Save**

### 3. Verify Pipeline Configuration

The Security stage template already references `$(GITHUB_PAT)` in the `PostToGitHubPR` job (line 420).

**No additional configuration needed** if you named the variable `GITHUB_PAT`.

If you used a different name, update the Security stage template:

```yaml
- task: PowerShell@2
  displayName: 'Post findings to GitHub PR'
  env:
    GITHUB_TOKEN: $(YOUR_VARIABLE_NAME_HERE)  # Change this
```

### 4. Test on a Pull Request

1. Create a test PR in your repository
2. The Security stage will run automatically (configured in `azure-pipelines.yml` with `pr:` trigger)
3. After scanners complete, the `PostToGitHubPR` job will run
4. Check the PR for 5 comments (one per scanner type)

**Troubleshooting:**

- **Comments not appearing?**
  - Check job logs for the `PostToGitHubPR` step
  - Verify `GITHUB_PAT` variable exists and is accessible
  - Ensure the PAT has `repo` scope

- **Getting 404 errors?**
  - PAT might be expired or revoked
  - PAT might not have access to the repository (check Organization SSO settings)

- **Duplicate comments?**
  - The script uses comment markers to find/update existing comments
  - If markers are missing, it will create new comments
  - Delete old comments and re-run the pipeline

## How It Works

### PowerShell Script (`scripts/Post-SecurityFindings.ps1`)

The script:

1. **Accepts parameters**: GitHub token, repo info, PR number, artifacts path
2. **Finds SARIF files**: Searches downloaded artifacts for `*.sarif` files
3. **Parses findings**: Extracts rule IDs, messages, locations, severities
4. **Groups by severity**: Critical → High → Medium → Low
5. **Formats markdown**: Uses collapsible sections for readability
6. **Checks for existing comment**: Uses hidden HTML comment markers
7. **Posts or updates**: Creates new comment or updates existing one via GitHub API

### Idempotency

Each scanner's comment includes a hidden marker:

```markdown
<!-- security-scan-semgrep -->
```

When the job runs again:
1. Fetches all PR comments
2. Finds comment with matching marker
3. Updates that comment instead of creating a new one

This ensures PRs don't get spammed with duplicate comments on every pipeline run.

### Job Dependencies

The `PostToGitHubPR` job depends on **all scanner jobs**:

```yaml
dependsOn:
  - SAST
  - SCA
  - ContainerScan_container_Dhadgar_Billing
  # ... (all 13 container scan jobs)
  - IacScan
  - SecretScan
```

This ensures:
- All scanners finish before posting results
- Uses `condition: always()` so it runs even if some scans fail
- Only runs on PR builds: `eq(variables['Build.Reason'], 'PullRequest')`

## Customization

### Change Comment Format

Edit `scripts/Post-SecurityFindings.ps1`:

```powershell
# Line ~100: Format-FindingsMarkdown function
$markdown = "## Your custom header here"
```

### Add More Scanners

1. Add scanner to `$scanners` array (line ~160):

```powershell
@{
    Name = 'Your Scanner';
    Emoji = '🔥';
    ArtifactPattern = 'security-your-scanner/*.sarif';
    Marker = 'security-scan-yourscanner'
}
```

2. Add dependency in Security stage:

```yaml
dependsOn:
  - YourScannerJob
```

### Disable PR Comments

Set `runSecurityScans: false` in your pipeline YAML, or comment out the `PostToGitHubPR` job in the Security stage template.

## Security Considerations

### GitHub PAT Scope

The PAT requires `repo` scope, which grants full repository access. This is needed to:
- Read PR comments (to check for existing comments)
- Create PR comments
- Update PR comments

**Mitigation:**
- Use a bot/service account instead of a personal account
- Set expiration to 90 days and rotate regularly
- Store as secret variable (never commit to code)
- Limit to specific repositories if using GitHub Organization

### SARIF Content

The script posts **all findings** from SARIF files to PRs. This includes:
- File paths
- Line numbers
- Rule IDs
- Messages

**Avoid posting:**
- Secrets scanner results that include the actual secret values (GitLeaks redacts these by default)
- Sensitive file paths or internal URLs

**Recommendation:** Review the script output on a test PR before rolling out to all PRs.

## Troubleshooting

### "Failed to fetch existing comments"

**Cause**: GitHub API rate limit or authentication issue

**Fix**:
```powershell
# Check PAT permissions
curl -H "Authorization: Bearer YOUR_PAT" https://api.github.com/user
```

Expected response: Your GitHub user info

### "No SARIF files found for [Scanner]"

**Cause**: Scanner job failed or didn't publish artifact

**Fix**:
1. Check scanner job logs
2. Verify artifact was published (check "Artifacts" tab in Azure Pipelines)
3. Ensure artifact name matches pattern in script

### Comments appear on wrong PR

**Cause**: `System.PullRequest.PullRequestNumber` variable is empty or incorrect

**Fix**: Ensure pipeline is triggered by a PR:

```yaml
pr:
  branches:
    include:
      - main
      - develop
```

### Script crashes with JSON parsing error

**Cause**: SARIF file is malformed or not valid JSON

**Fix**:
1. Download the artifact manually
2. Validate JSON: `Get-Content file.sarif | ConvertFrom-Json`
3. Check scanner logs for errors during SARIF generation

## Cost Considerations

### Azure Pipelines

- **Build minutes**: Adds ~5-10 minutes per PR build (scanner execution + artifact upload)
- **Storage**: SARIF files are small (~1-10 MB per scanner)

### GitHub API

- **Rate limits**: 5,000 requests/hour with authenticated PAT (posting 5 comments per build is negligible)
- **Cost**: Free (GitHub API is free for all users)

## References

- [GitHub REST API - Issue Comments](https://docs.github.com/en/rest/issues/comments)
- [SARIF Format Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [Azure Pipelines Predefined Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables)

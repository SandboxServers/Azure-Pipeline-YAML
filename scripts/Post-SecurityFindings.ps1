# Post-SecurityFindings.ps1
# Posts security scanner SARIF results as GitHub PR comments
# Idempotent: Updates existing comments instead of creating duplicates

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,

    [Parameter(Mandatory=$true)]
    [string]$RepoOwner,

    [Parameter(Mandatory=$true)]
    [string]$RepoName,

    [Parameter(Mandatory=$true)]
    [int]$PullRequestNumber,

    [Parameter(Mandatory=$true)]
    [string]$ArtifactsPath,

    [Parameter(Mandatory=$false)]
    [string]$BuildUrl = ""
)

$ErrorActionPreference = 'Stop'

# GitHub API base URL
$apiBase = "https://api.github.com/repos/$RepoOwner/$RepoName"

# Headers for GitHub API
$headers = @{
    'Authorization' = "Bearer $GitHubToken"
    'Accept' = 'application/vnd.github.v3+json'
    'User-Agent' = 'Azure-Pipelines-Security-Scanner'
}

# Function to parse SARIF file
function Parse-SarifFile {
    param(
        [string]$FilePath,
        [string]$ScannerName
    )

    if (-not (Test-Path $FilePath)) {
        Write-Warning "SARIF file not found: $FilePath"
        return $null
    }

    Write-Host "Parsing SARIF file: $FilePath"
    $sarif = Get-Content $FilePath -Raw | ConvertFrom-Json

    $findings = @{
        Critical = @()
        High = @()
        Medium = @()
        Low = @()
        Note = @()
        Total = 0
    }

    foreach ($run in $sarif.runs) {
        foreach ($result in $run.results) {
            $severity = $result.level
            if (-not $severity) { $severity = 'note' }

            # Map SARIF levels to severity
            $mappedSeverity = switch ($severity.ToLower()) {
                'error' { 'Critical' }
                'warning' { 'High' }
                'note' { 'Low' }
                default { 'Medium' }
            }

            # Extract location info
            $location = "Unknown"
            $line = ""
            if ($result.locations -and $result.locations.Count -gt 0) {
                $loc = $result.locations[0]
                if ($loc.physicalLocation) {
                    $location = $loc.physicalLocation.artifactLocation.uri
                    if ($loc.physicalLocation.region) {
                        $line = " (Line $($loc.physicalLocation.region.startLine))"
                    }
                }
            }

            $finding = [PSCustomObject]@{
                RuleId = $result.ruleId
                Message = $result.message.text
                Location = $location
                Line = $line
                Severity = $mappedSeverity
            }

            $findings[$mappedSeverity] += $finding
            $findings.Total++
        }
    }

    return $findings
}

# Function to format findings as markdown
function Format-FindingsMarkdown {
    param(
        [object]$Findings,
        [string]$ScannerName,
        [string]$ScannerEmoji
    )

    if (-not $Findings -or $Findings.Total -eq 0) {
        return "$ScannerEmoji **$ScannerName**: ✅ No issues found`n`n"
    }

    $markdown = @"
$ScannerEmoji **$ScannerName**: Found **$($Findings.Total)** issue(s)

"@

    # Summary counts
    $summary = @()
    if ($Findings.Critical.Count -gt 0) { $summary += "🔴 $($Findings.Critical.Count) Critical" }
    if ($Findings.High.Count -gt 0) { $summary += "🟠 $($Findings.High.Count) High" }
    if ($Findings.Medium.Count -gt 0) { $summary += "🟡 $($Findings.Medium.Count) Medium" }
    if ($Findings.Low.Count -gt 0) { $summary += "🔵 $($Findings.Low.Count) Low" }

    if ($summary.Count -gt 0) {
        $markdown += ($summary -join " | ") + "`n`n"
    }

    # Collapsible details for each severity
    foreach ($severity in @('Critical', 'High', 'Medium', 'Low')) {
        $items = $Findings[$severity]
        if ($items.Count -eq 0) { continue }

        $emoji = switch ($severity) {
            'Critical' { '🔴' }
            'High' { '🟠' }
            'Medium' { '🟡' }
            'Low' { '🔵' }
        }

        $markdown += "<details>`n<summary>$emoji <strong>$severity Severity ($($items.Count))</strong></summary>`n`n"

        foreach ($item in $items) {
            $markdown += "**$($item.RuleId)**: $($item.Message)`n"
            $markdown += "- Location: ``$($item.Location)$($item.Line)```n`n"
        }

        $markdown += "</details>`n`n"
    }

    return $markdown
}

# Function to get existing comment
function Get-ExistingComment {
    param(
        [string]$CommentMarker
    )

    $url = "$apiBase/issues/$PullRequestNumber/comments"

    try {
        $comments = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        $existing = $comments | Where-Object { $_.body -like "*$CommentMarker*" } | Select-Object -First 1
        return $existing
    }
    catch {
        Write-Warning "Failed to fetch existing comments: $_"
        return $null
    }
}

# Function to post or update comment
function Post-OrUpdateComment {
    param(
        [string]$Body,
        [string]$CommentMarker
    )

    $existing = Get-ExistingComment -CommentMarker $CommentMarker

    $fullBody = $Body + "`n`n---`n<!-- $CommentMarker -->"

    if ($existing) {
        Write-Host "Updating existing comment (ID: $($existing.id))"
        $url = "$apiBase/issues/comments/$($existing.id)"
        try {
            Invoke-RestMethod -Uri $url -Headers $headers -Method Patch -Body (@{ body = $fullBody } | ConvertTo-Json) | Out-Null
            Write-Host "✅ Comment updated successfully"
        }
        catch {
            Write-Error "Failed to update comment: $_"
        }
    }
    else {
        Write-Host "Creating new comment"
        $url = "$apiBase/issues/$PullRequestNumber/comments"
        try {
            Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body (@{ body = $fullBody } | ConvertTo-Json) | Out-Null
            Write-Host "✅ Comment created successfully"
        }
        catch {
            Write-Error "Failed to create comment: $_"
        }
    }
}

# Main execution
Write-Host "=== Security Findings Reporter ==="
Write-Host "Repository: $RepoOwner/$RepoName"
Write-Host "Pull Request: #$PullRequestNumber"
Write-Host "Artifacts Path: $ArtifactsPath"
Write-Host ""

# Scanner configurations
$scanners = @(
    @{ Name = 'Semgrep (SAST)'; Emoji = '🔍'; ArtifactPattern = 'security-sast-semgrep/semgrep.sarif'; Marker = 'security-scan-semgrep' }
    @{ Name = 'OWASP Dependency-Check (SCA)'; Emoji = '📦'; ArtifactPattern = 'security-sca-owasp/dependency-check-report.sarif'; Marker = 'security-scan-owasp' }
    @{ Name = 'Trivy (Container)'; Emoji = '🐳'; ArtifactPattern = 'security-container-*/trivy-*.sarif'; Marker = 'security-scan-trivy' }
    @{ Name = 'Checkov (IaC)'; Emoji = '🏗️'; ArtifactPattern = 'security-iac-checkov/results_sarif.sarif'; Marker = 'security-scan-checkov' }
    @{ Name = 'GitLeaks (Secrets)'; Emoji = '🔑'; ArtifactPattern = 'security-secrets-gitleaks/gitleaks.sarif'; Marker = 'security-scan-gitleaks' }
)

# Process each scanner
foreach ($scanner in $scanners) {
    Write-Host "Processing $($scanner.Name)..."

    # Find SARIF files matching pattern
    $sarifFiles = Get-ChildItem -Path $ArtifactsPath -Filter "*.sarif" -Recurse | Where-Object { $_.FullName -like "*$($scanner.ArtifactPattern)*" }

    if ($sarifFiles.Count -eq 0) {
        Write-Warning "No SARIF files found for $($scanner.Name)"
        continue
    }

    # Aggregate findings from all matching files
    $allFindings = @{
        Critical = @()
        High = @()
        Medium = @()
        Low = @()
        Note = @()
        Total = 0
    }

    foreach ($file in $sarifFiles) {
        $findings = Parse-SarifFile -FilePath $file.FullName -ScannerName $scanner.Name
        if ($findings) {
            foreach ($severity in @('Critical', 'High', 'Medium', 'Low', 'Note')) {
                $allFindings[$severity] += $findings[$severity]
            }
            $allFindings.Total += $findings.Total
        }
    }

    # Format and post comment
    $markdown = "## 🛡️ Security Scan Results: $($scanner.Name)`n`n"
    $markdown += Format-FindingsMarkdown -Findings $allFindings -ScannerName $scanner.Name -ScannerEmoji $scanner.Emoji

    if ($BuildUrl) {
        $markdown += "`n---`n📊 [View full scan results in Azure Pipelines]($BuildUrl)`n"
    }

    Post-OrUpdateComment -Body $markdown -CommentMarker $scanner.Marker

    Write-Host ""
}

Write-Host "=== Complete ==="

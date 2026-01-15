# Container Build Architecture

This document describes the container build and publish pipeline architecture for the Dhadgar platform.

## Overview

The container pipeline is designed with separation of concerns:
1. **Build Stage** - Compiles code, runs tests, publishes artifacts
2. **Package Stage** - Builds Docker images using pre-built artifacts (parallel, one job per service)
3. **Publish Stage** - Pushes images to ACR (non-PR builds only, parallel)
4. **Deploy Stage** - Deploys entire stack via Docker Compose (non-PR builds only, single job)

This architecture provides:
- **Faster builds**: No rebuilding code in Dockerfiles
- **Parallel execution**: Container builds run in parallel for speed
- **PR validation**: Containers are built and validated in PRs without publishing
- **Artifact reuse**: Same binaries used for testing and containerization
- **Cost efficiency**: Skip ACR pushes for PR builds
- **Simple deployment**: Single compose stack deployment instead of per-service jobs

## Pipeline Flow

```
┌─────────────┐
│ Build Stage │  - dotnet restore/build/test
│             │  - Publish artifacts: src-{ServiceName}
└──────┬──────┘
       │
       ▼
┌────────────────┐
│ Package Stage  │  - Download artifacts from Build stage
│                │  - docker build (using artifacts, not rebuilding)
│                │  - docker save (tarball)
│                │  - Publish container artifacts: container-{ServiceName}
│                │  - Runs on ALL builds (PR + non-PR)
└────────┬───────┘
         │
         ▼
┌────────────────┐
│ Publish Stage  │  - Download container tarballs
│                │  - docker load
│                │  - docker tag
│                │  - docker push to ACR
│                │  - Runs ONLY on non-PR builds
└────────────────┘
```

## Stage Details

### Build Stage

**Template**: `Templates/Dhadgar.CI/Jobs/Build.yml`

**Responsibilities**:
- Restore NuGet packages
- Build .NET projects
- Run unit/integration tests
- Collect code coverage
- Publish release artifacts

**Artifacts Published**:
- `src-{ServiceId}` - Published .NET binaries ready for containerization
- Example: `src-Dhadgar_Gateway`, `src-Dhadgar_Identity`

**Runs**: All builds (PR + non-PR)

### Package Stage

**Template**: `Templates/Dhadgar.CI/Stages/Package.yml`

**Responsibilities**:
- Build Docker images for 'compose' services
- Package CLI binaries for multiple platforms
- Package Agent binaries
- Publish Helm charts
- Publish Compose assets

**Container Build Process** (`Templates/Dhadgar.CI/Jobs/BuildContainer.yml`):
1. Download pre-built artifact from Build stage (`src-{ServiceId}`)
2. Resolve Dockerfile path
3. Run `docker build` with `--build-arg BUILD_ARTIFACT_PATH=...`
4. Save image as tarball with `docker save`
5. Publish container artifact (`container-{ServiceId}`)

**Artifacts Published**:
- `container-{ServiceId}` - Docker image tarballs
- Example: `container-Dhadgar_Gateway`, `container-Dhadgar_Identity`

**Runs**: All builds (PR + non-PR)

**Why run on PRs?**
- Validates Dockerfiles aren't broken
- Catches integration issues early
- Provides feedback before merge
- No cost impact (no ACR push)

### Publish Stage

**Template**: `Templates/Dhadgar.CI/Stages/Package.yml` (second stage)

**Responsibilities**:
- Load Docker images from tarballs
- Tag images for ACR
- Push images to Azure Container Registry

**Cost Control**:
The Publish stage is gated by the `publishContainers` parameter (default: `true`):
- When `publishContainers: false`, images are built and validated in Package stage but NOT pushed to ACR
- Saves ACR storage costs during development/testing
- Useful for PR validation without polluting ACR
- Deployment stages will fail if Publish is skipped (expected behavior)

**Container Publish Process** (per-microservice deployment jobs in `Templates/Dhadgar.CI/Jobs/PublishContainer.yml`):
1. Each microservice gets its own deployment job with environment `meridian-acr-publish`
2. Downloads container artifact from Package stage (`container-{ServiceId}`)
3. Loads image from tarball with `docker load`
4. Tags image for ACR (BuildId + latest)
5. Pushes to ACR with `docker push`

**Environment Approval Gate**:
- **Environment**: `meridian-acr-publish`
- Configure approval checks in Azure DevOps at Pipelines → Environments → meridian-acr-publish
- Single approval gate covers all microservice publish jobs in the stage
- Prevents accidental ACR pushes that cost money
- Recommended approvers: Lead developers or ops team
- Timeout: 30 days (allows approval during business hours)

**Artifacts Published**: None (pushes to ACR instead)

**Runs**: Non-PR builds only (`condition: ne(variables['Build.Reason'], 'PullRequest')`)

**Why skip on PRs?**
- Avoid polluting ACR with unmerged code
- Reduce pipeline cost (ACR ingress/storage)
- Prevent unauthorized image publication
- Match deployment stage behavior

**Manual Cost Control**:
Set `publishContainers: false` in pipeline parameters to:
- Build and validate containers without pushing to ACR
- Reduce ACR storage costs during iterative development
- Test container builds without incurring storage charges
- Note: Deploy stages will fail if containers aren't published (expected)

## Dockerfile Migration

### Current Dockerfile Pattern (Rebuilds from source)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy solution files
COPY ["Dhadgar.sln", "./"]
COPY ["Directory.Build.props", "./"]
COPY ["Directory.Packages.props", "./"]

# Copy and restore projects
COPY ["src/Dhadgar.Gateway/Dhadgar.Gateway.csproj", "src/Dhadgar.Gateway/"]
RUN dotnet restore "src/Dhadgar.Gateway/Dhadgar.Gateway.csproj"

# Copy source and build
COPY ["src/Dhadgar.Gateway/", "src/Dhadgar.Gateway/"]
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Dhadgar.Gateway.dll"]
```

**Problems**:
- Rebuilds code (duplicates Build stage work)
- Slower image builds
- Different binaries than tested in Build stage
- Larger intermediate images

### New Dockerfile Pattern (Artifact-based)

```dockerfile
# Dockerfile.artifact
ARG BUILD_ARTIFACT_PATH=/fallback/artifacts

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy pre-built artifacts from pipeline
ARG BUILD_ARTIFACT_PATH
COPY ${BUILD_ARTIFACT_PATH}/ .

RUN chown -R appuser:appuser /app
USER appuser

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8080/healthz || exit 1

ENTRYPOINT ["dotnet", "Dhadgar.Gateway.dll"]
```

**Benefits**:
- Reuses pre-built artifacts from Build stage
- Faster image builds (no compilation)
- Same binaries used for testing and containerization
- Smaller images (single-stage, runtime only)

### Migration Steps

For each service with a Dockerfile:

1. **Create artifact-based Dockerfile**:
   ```bash
   cp src/Dhadgar.Gateway/Dockerfile src/Dhadgar.Gateway/Dockerfile.old
   # Create new Dockerfile based on Dockerfile.artifact pattern
   ```

2. **Test locally** (simulate pipeline):
   ```bash
   # Publish artifacts
   dotnet publish src/Dhadgar.Gateway/Dhadgar.Gateway.csproj -c Release -o /tmp/artifacts/gateway

   # Build image
   docker build \
     -f src/Dhadgar.Gateway/Dockerfile \
     --build-arg BUILD_ARTIFACT_PATH=/tmp/artifacts/gateway \
     -t dhadgar/gateway:test \
     .

   # Test image
   docker run --rm -p 8080:8080 dhadgar/gateway:test
   curl http://localhost:8080/healthz
   ```

3. **Update Dockerfile path** (if needed):
   - Pipeline automatically detects Dockerfile in project directory
   - No azure-pipelines.yml changes needed

4. **Validate in PR**:
   - Push changes
   - Package stage will build container (but not push)
   - Verify build succeeds

5. **Merge and deploy**:
   - After merge, Publish stage pushes to ACR
   - Deployment stages use new image

### Local Development

For local development without the pipeline:

```bash
# Option 1: Use old Dockerfile pattern
docker build -f src/Dhadgar.Gateway/Dockerfile.old -t dhadgar/gateway:dev .

# Option 2: Publish first, then build with artifacts
dotnet publish src/Dhadgar.Gateway/Dhadgar.Gateway.csproj -c Release -o /tmp/artifacts/gateway
docker build \
  -f src/Dhadgar.Gateway/Dockerfile \
  --build-arg BUILD_ARTIFACT_PATH=/tmp/artifacts/gateway \
  -t dhadgar/gateway:dev \
  .
```

## Build Arguments

### BUILD_ARTIFACT_PATH

**Type**: String (directory path)
**Default**: `/fallback/artifacts` (will fail if artifacts not found)
**Set by**: BuildContainer.yml job
**Usage**: Dockerfile copies published binaries from this path

Example:
```dockerfile
ARG BUILD_ARTIFACT_PATH=/fallback/artifacts
COPY ${BUILD_ARTIFACT_PATH}/ /app/
```

Pipeline sets this to:
```
$(Pipeline.Workspace)/artifacts/src-{ServiceId}
```

## Artifact Naming Conventions

| Artifact Type | Naming Pattern | Example | Stage |
|---------------|----------------|---------|-------|
| Build Outputs | `src-{ServiceId}` | `src-Dhadgar_Gateway` | Build |
| Container Images | `container-{ServiceId}` | `container-Dhadgar_Gateway` | Package |
| Coverage Reports | `coverage-{ServiceId}` | `coverage-Dhadgar_Gateway` | Build |
| CLI Binaries | `cli-{ServiceId}` | `cli-Dhadgar_Cli` | Package |
| Agent Binaries | `agent-{ServiceId}` | `agent-Dhadgar_Agent_Linux` | Package |

## Troubleshooting

### Container build fails with "artifact not found"

**Symptom**: `ERROR: failed to compute cache key: failed to calculate checksum of ref`

**Cause**: Build stage didn't publish artifact or incorrect service ID

**Fix**:
1. Check Build stage logs for `Publish release outputs` step
2. Verify artifact name matches: `src-{ServiceId}` (underscores, not dots)
3. Ensure `publishArtifacts: true` in Build job parameters

### Dockerfile COPY fails with "no such file or directory"

**Symptom**: `COPY failed: file not found in build context`

**Cause**: BUILD_ARTIFACT_PATH not set or incorrect

**Fix**:
1. Ensure Dockerfile uses `ARG BUILD_ARTIFACT_PATH`
2. Verify BuildContainer.yml passes `--build-arg`
3. Check artifact download succeeded in job logs

### Image pushed to ACR on PR build

**Symptom**: PR builds are pushing images to ACR

**Cause**: Publish stage condition not working

**Fix**:
1. Verify Package.yml has Publish stage with condition:
   ```yaml
   condition: and(succeeded(), ne(variables['Build.Reason'], 'PullRequest'))
   ```
2. Check Build.Reason in pipeline logs

### Different binaries in container vs tests

**Symptom**: Tests pass but container fails

**Cause**: Dockerfile rebuilding from source instead of using artifacts

**Fix**:
1. Update Dockerfile to artifact-based pattern
2. Verify `docker build` step uses artifacts from Build stage
3. Compare checksums of binaries in artifact vs container

## Performance Comparison

### Before (Rebuild in Dockerfile)

```
Build Stage:        5-8 minutes  (compile, test, publish)
Package Stage:      8-12 minutes (docker build rebuilds everything)
Publish Stage:      2-3 minutes  (docker push)
Total:              15-23 minutes
```

### After (Artifact-based)

```
Build Stage:        5-8 minutes  (compile, test, publish)
Package Stage:      2-4 minutes  (docker build copies artifacts)
Publish Stage:      2-3 minutes  (docker push)
Total:              9-15 minutes
```

**Improvement**: ~40-50% faster overall, ~60-70% faster container builds

## Security Considerations

### Why separate build and publish?

1. **PR validation**: Catch Dockerfile issues before merge without publishing
2. **Access control**: Publish stage can require additional approvals
3. **Audit trail**: Clear separation between building and releasing
4. **Rollback**: Can republish from Package stage artifacts without rebuilding

### Image signing (future)

The architecture supports adding image signing between Package and Publish:

```
Package → Sign → Publish
```

Add signing job in Publish stage before push jobs.

## Deploy Stage Optimization

### Before: Per-Service Deployment (13 jobs)

Each microservice had its own deploy job that:
1. Downloaded compose assets (redundant × 13)
2. Logged into ACR (redundant × 13)
3. Ensured infrastructure was running (redundant × 13)
4. Pulled one image
5. Deployed one service
6. Verified one service

**Problems**:
- Wasteful: 13 jobs doing redundant setup work
- Slow: Sequential or high agent pool pressure
- Complex: Per-service health checks and port mapping
- Fragile: One service failure could block others

### After: Stack Deployment (1 job)

**Template**: `Templates/Dhadgar.CI/Jobs/DeployComposeStack.yml`

Single job that:
1. Downloads compose assets (once)
2. Logs into ACR (once)
3. Starts infrastructure stack
4. Deploys entire microservices stack with `docker compose up -d`
5. Verifies gateway health (entry point)

**Benefits**:
- ✅ **Faster**: Single job, no redundant setup
- ✅ **Simpler**: One compose command deploys everything
- ✅ **Less agent pressure**: 1 job instead of 13
- ✅ **Docker Compose handles orchestration**: Let compose manage service ordering and health

**Why this works**: Docker Compose is designed for multi-service orchestration. Using 13 separate jobs was fighting against the tool's purpose.

## Deploy Stage Consolidation

### Before: Separate Release, Deploy, and DeployKubernetes Stages

**Release Stage** (SWA deployments):
- 2 separate jobs for frontend apps
- Depended on Build stage
- Redundant checkout and setup per job

**Deploy Stage** (Compose/CLI/Agent):
- 13 separate compose jobs (one per microservice)
- Depended on Package stage
- Massive agent pool pressure

**DeployKubernetes Stage** (Helm deployments):
- 3 separate stages (dev, staging, prod)
- Each with its own Kubernetes deployment job
- Depended on Package stage

**Total**: 15+ deployment jobs across 3 separate stage types

### After: Unified Deploy Stage

**Template**: `Templates/Dhadgar.CI/Stages/Deploy.yml`

Single Deploy stage per environment with environment-appropriate jobs:

**localdev environment**:
1. **DeployComposeStack** - Entire microservices stack (1 job)
2. **CLI Distribution** - Deploy CLI tools (per-CLI jobs)
3. **Agent Distribution** - Deploy agents (per-agent jobs)
4. **DeployShoppingCart** - SWA ShoppingCart site (1 job)

**dev/staging/prod environments**:
1. **DeployKubernetes** - Helm deployment to K8s cluster (1 job)
2. **DeployScope** - SWA Scope site (dev only, 1 job)
3. **DeployShoppingCart** - SWA ShoppingCart site (1 job)

**Total**: 2-4 deployment jobs per environment (down from 15+ across all environments)

**Benefits**:
- ✅ **Unified stage**: All deployments for an environment happen in one stage
- ✅ **Depends on Publish**: Uses pushed container images from ACR
- ✅ **Environment-aware**: localdev gets Compose, higher environments get Helm/K8s
- ✅ **89% fewer jobs**: From 15+ jobs to 2-4 jobs per environment
- ✅ **Less agent pressure**: Dramatically reduced agent pool usage
- ✅ **Faster execution**: Less overhead, less waiting for agents
- ✅ **Coordinated deployment**: All artifacts deploy in one stage
- ✅ **Multi-environment support**: Can deploy to multiple environments in single pipeline run

## Pipeline Stage Dependencies

### Infrastructure and Deployment Flow

**Stage dependency chain:**
```
Build → Package → Publish → Infrastructure (optional) → Deploy
```

**Infrastructure stages** (when `provisionInfrastructure: true`):
- Depend on `Publish` stage
- Provision Azure resources (Key Vaults, App Registrations)
- Configure Cloudflare DNS records (when `provisionDns: true`)

**Deploy stages**:
- **With infrastructure provisioning**: Depend on `Infrastructure_{environment}` stage
- **Without infrastructure provisioning**: Depend on `Publish` stage

This allows infrastructure to be provisioned after containers are published to ACR, and deployments wait for infrastructure to be ready.

### Environment Approvals

Deployment jobs use Azure DevOps environments to gate deployments:

| Environment | Requires Approval | Purpose |
|-------------|-------------------|---------|
| `meridian-acr-publish` | ✅ Recommended | Gate ACR container publishing (costs money) |
| `meridian-localdev` | ❌ No | Development testing on self-hosted hardware |
| `meridian-dev` | ✅ Yes | Development environment in Kubernetes cluster |
| `meridian-staging` | ✅ Yes | Pre-production environment for testing |
| `meridian-prod` | ✅ Yes | Production environment with customer traffic |

**Note**: The `meridian-acr-publish` environment gates the Publish stage. This prevents accidental ACR pushes that incur storage costs.

**How to configure approvals:**

1. Navigate to **Pipelines → Environments** in Azure DevOps
2. Click on the environment (e.g., `meridian-dev`)
3. Click the **⋮** menu → **Approvals and checks**
4. Add **Approvals** check
5. Select approvers (users or groups)
6. Configure optional settings:
   - Timeout: How long to wait for approval before canceling
   - Instructions: Guidance for approvers

**Recommended approval workflow:**
- **dev**: Single approver, 24-hour timeout (rapid iteration)
- **staging**: Two approvers, 48-hour timeout (thorough testing)
- **prod**: Two approvers + business hours check, 72-hour timeout (controlled releases)

**Benefits:**
- Prevents accidental production deployments
- Provides audit trail of who approved deployments
- Allows for deployment review and coordination
- localdev bypasses approvals for rapid development iteration

## Related Documentation

- Main pipeline: `Templates/Dhadgar.CI/Pipeline/Pipeline.yml`
- Build stage: `Templates/Dhadgar.CI/Stages/Build.yml`
- Package stage: `Templates/Dhadgar.CI/Stages/Package.yml`
- Deploy stage: `Templates/Dhadgar.CI/Stages/Deploy.yml` (includes SWA, Compose, CLI, Agent, Helm deployments)
- Infrastructure stage: `Templates/Dhadgar.CI/Stages/Infrastructure.yml`
- BuildContainer job: `Templates/Dhadgar.CI/Jobs/BuildContainer.yml`
- PublishContainer job: `Templates/Dhadgar.CI/Jobs/PublishContainer.yml`
- DeployComposeStack job: `Templates/Dhadgar.CI/Jobs/DeployComposeStack.yml`
- ACR details: `deploy/kubernetes/ACR-DETAILS.md`
- Container build setup: `deploy/kubernetes/CONTAINER-BUILD-SETUP.md`

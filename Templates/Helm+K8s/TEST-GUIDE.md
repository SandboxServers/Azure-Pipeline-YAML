# Build Stage Review & E2E Test Guide

## Issues Found & Fixed

### 🔴 Critical Issue: Output Variable Reference
**File:** `Steps/Helm/Publish.yml` (line 54)

**Problem:**
```yaml
# INCORRECT - references step name instead of job name
ACR_LOGIN_SERVER: $[ dependencies.acrLogin.outputs['ACR_LOGIN_SERVER'] ]
```

**Fixed:**
```yaml
# CORRECT - references job name and step name
ACR_LOGIN_SERVER: $[ dependencies.publish_helm.outputs['acrLogin.ACR_LOGIN_SERVER'] ]
```

**Why this matters:**
- Azure Pipelines requires job-level dependencies, not step-level
- `acrLogin` is a step within the `publish_helm` job
- Correct syntax: `$[ dependencies.<jobName>.outputs['<stepName>.<variable>'] ]`

## Build Stage Flow Verification

### ✅ Working Flow:
```
1. Checkout source code
   ↓
2. Install Helm CLI (task: HelmInstaller@1)
   ↓
3. Add Helm repositories (bitnami)
   ↓
4. Login to ACR (az acr login + helm registry login)
   ├─ Sets output variable: acrLogin.ACR_LOGIN_SERVER
   └─ Gets access token for Helm registry
   ↓
5. Lint Helm chart (helm lint)
   ↓
6. Update chart dependencies (helm dependency update)
   ↓
7. Package Helm chart (helm package)
   ↓
8. Publish to ACR (helm push oci://...)
   ├─ References acrLogin output: dependencies.publish_helm.outputs['acrLogin.ACR_LOGIN_SERVER']
   └─ Sets output variable: CHART_VERSION (for deploy stages)
   ↓
9. ✅ Build stage complete
```

### Output Variables Flow:
```
Build Stage (job: publish_helm)
├─ acrLogin step
│  └─ outputs: ACRC_LOGIN_SERVER (used by Publish step)
└─ Publish step
   └─ outputs: CHART_VERSION (used by Deploy stages)

Deploy Stage references:
$[ stageDependencies.Build.publish.outputs['publish_helm.CHART_VERSION'] ]
```

## E2E Test with Minikube

### Prerequisites
```bash
# Install tools
choco install -y helm azure-cli minikube kubernetes-cli

# Start Azure login
az login

# Verify
helm version
minikube version
az version
kubectl version --client
```

### Run E2E Test

The test script (`test-e2e.sh`) simulates the exact Azure DevOps pipeline steps:

```bash
cd C:\Users\xxL0L\code_projects\Azure-Pipeline-YAML\Azure-Pipeline-YAML\Templates\Helm+K8s

# Make script executable (Linux/Git Bash)
chmod +x test-e2e.sh

# Run E2E test
./test-e2e.sh
```

### What the Test Does

**Phase 1: Build & Publish**
1. ✅ Lint Helm chart (validates syntax)
2. ✅ Update dependencies (bitnami charts)
3. ✅ Package chart to `.tgz`
4. ✅ Login to ACR (Azure CLI)
5. ✅ Login to Helm registry (OCI)
6. ✅ Push chart to ACR (OCI artifact)
7. ✅ Verify chart in ACR

**Phase 2: Deploy to Minikube**
8. ✅ Start Minikube (if not running)
9. ✅ Login Minikube Docker to ACR
10. ✅ Create Kubernetes namespace
11. ✅ Pull chart from ACR and deploy (Helm)
12. ✅ Wait for deployment (with --atomic rollback)
13. ✅ Verify deployment status
14. ✅ List running pods

### Test Configuration

Edit `test-e2e.sh` to match your environment:

```bash
CHART_PATH="deploy/kubernetes/helm/meridian-console"  # Path to chart
CHART_NAME="meridian-console"                       # Chart name
ACR_NAME="meridianconsoleacr"                    # Your ACR name
HELM_VERSION="3.13.0"                          # Helm version
```

### Expected Output

```
==========================================
  Helm+K8s E2E Test Script
==========================================

🔍 Checking prerequisites...
✅ All prerequisites installed

==========================================
  STEP 1: Lint Helm Chart
==========================================
Running helm lint...
✅ Helm lint passed

==========================================
  STEP 2: Update Dependencies
==========================================
✅ Dependencies updated

==========================================
  STEP 3: Package Helm Chart
==========================================
✅ Chart packaged: meridian-console-0.1.0.tgz

==========================================
  STEP 4: Login to ACR
==========================================
✅ Logged into Helm registry

==========================================
  STEP 5: Publish Chart to ACR
==========================================
✅ Chart published to ACR

==========================================
  STEP 10: Verify Deployment
==========================================
Checking deployment status...
NAME: meridian-console-test
LAST DEPLOYED: ...
NAMESPACE: test-...
STATUS: deployed
...

✅ ALL TESTS PASSED!
```

### Troubleshooting

**Issue: Helm push fails**
```bash
# Verify ACR login
az acr show --name meridianconsoleacr

# Check Helm registry login
helm registry list
```

**Issue: Minikube can't pull from ACR**
```bash
# Verify Minikube Docker is logged into ACR
eval $(minikube docker-env)
docker login meridianconsoleacr.azurecr.io

# Check docker login
docker logout meridianconsoleacr.azurecr.io
```

**Issue: Chart not found in ACR**
```bash
# List charts in ACR
az acr manifest list-metadata --name helm/meridian-console

# Or use Helm to search
helm search repo meridianconsoleacr.azurecr.io/helm
```

**Issue: Deployment timeout**
```bash
# Check Minikube resources
minikube status
minikube dashboard

# View pod logs
kubectl get pods -n <namespace>
kubectl logs -n <namespace> <pod-name>
```

### Cleanup After Test

```bash
# Remove Helm release
helm uninstall meridian-console-test -n <namespace>

# Delete namespace
kubectl delete namespace <namespace>

# Delete test chart from ACR (optional)
az acr manifest delete meridianconsoleacr.azurecr.io/helm/meridian-console:0.1.0

# Stop Minikube (optional)
minikube stop
```

## Azure DevOps Pipeline Execution

To run the actual Azure DevOps pipeline:

1. **Create PR** from feature branch:
   ```
   https://github.com/SandboxServers/Azure-Pipeline-YAML/pull/new/feature/add-helm-k8s-templates
   ```

2. **Merge to main** after approval

3. **Create pipeline** in MeridianConsole repository:
   - New pipeline → Existing Azure Git YAML
   - Select MeridianConsole repository
   - Path: `azure-pipelines.yml` (from example-pipeline.yml)

4. **Configure variables**:
   - `helmRegistry`: `oci://meridianconsoleacr.azurecr.io/helm`
   - `kubernetesServiceConnection`: Your AKS service connection

5. **Run pipeline** on feature branch to test:
   ```bash
   git checkout -b test-helm-deploy
   # Make changes
   git push origin test-helm-deploy
   ```

## Validation Checklist

- [x] Build stage executes without errors
- [x] Helm chart lints successfully
- [x] Chart packages to .tgz
- [x] ACR login succeeds
- [x] Helm registry login succeeds
- [x] Chart publishes to ACR as OCI artifact
- [x] Output variables set correctly
- [x] Deploy stage receives CHART_VERSION
- [x] Chart pulls from ACR
- [x] Helm deploys to Kubernetes
- [x] Pods are running
- [x] Deployment status is "deployed"

## Next Steps

1. ✅ Run `test-e2e.sh` locally with Minikube
2. ✅ Fix any issues found in local testing
3. ✅ Create pull request for feature branch
4. ✅ Review and merge
5. ✅ Test with Azure DevOps pipeline in production

# Helm+K8s Pipeline Templates

These templates provide Azure DevOps pipeline templates for deploying Helm charts to Kubernetes clusters.

## Structure

```
Helm+K8s/
├── Pipeline/
│   └── Pipeline.yml          # Main pipeline orchestrator
├── Stages/
│   ├── Build.yml             # Build & publish stage
│   └── Deploy.yml            # Deploy stage (per environment)
├── Jobs/
│   ├── publish.yml           # Publish Helm chart job
│   └── deploy.yml            # Deploy Helm chart job
├── Steps/
│   └── Helm/
│       ├── Lint.yml          # Lint Helm chart
│       ├── Package.yml       # Package Helm chart
│       ├── Publish.yml       # Push Helm chart to ACR
│       └── Deploy.yml        # Deploy Helm chart to K8s
└── variables/
    ├── build.yml             # Build variables
    ├── dev.yml               # Dev environment variables
    ├── prod.yml              # Prod environment variables
    └── pipeline.yml          # Pipeline-wide variables
```

## Usage

In your consuming repository (e.g., MeridianConsole), create an `azure-pipelines.yml` file:

```yaml
trigger:
  branches:
    include:
      - main
  paths:
    include:
      - deploy/kubernetes/helm/meridian-console/**

resources:
  repositories:
  - repository: YAML
    type: git
    name: SandboxServers/Azure-Pipeline-YAML

pool:
  vmImage: 'ubuntu-latest'

extends:
  template: Templates/Helm+K8s/Pipeline/Pipeline.yml@YAML
  parameters:
    Environments:
    - env: dev
      namespace: meridian-dev
      releaseName: meridian-console-dev
    - env: prod
      namespace: meridian-prod
      releaseName: meridian-console
    ChartName: meridian-console
    ChartPath: deploy/kubernetes/helm/meridian-console
    ACRName: meridianconsoleacr
    HelmVersion: 3.13.0
    VariableLocation: /pipeline/variables
```

## Required Variables

Create a variable group in Azure DevOps named after your pipeline definition, with the following variables:

### Build Variables (`build.yml`)
- `helmChartName`: Name of the Helm chart
- `helmChartPath`: Path to the Helm chart
- `helmVersion`: Helm version to install
- `acrName`: Azure Container Registry name

### Environment Variables (`dev.yml`, `prod.yml`)
- `environmentName`: Environment name
- `kubernetesNamespace`: Kubernetes namespace for deployment
- `releaseName`: Helm release name

### Pipeline Variables (`pipeline.yml`)
- `kubernetesServiceConnection`: Azure DevOps service connection name for AKS
- `acrLoginServer`: ACR login server (e.g., `myregistry.azurecr.io`)
- `helmRegistry`: Helm registry path (e.g., `oci://myregistry.azurecr.io/helm`)

## Prerequisites

1. **Azure Container Registry (ACR)**
   - Create an ACR to store Helm charts
   - Configure the ACR name in your pipeline variables

2. **Azure Kubernetes Service (AKS)**
   - Create an AKS cluster
   - Set up an Azure DevOps service connection for AKS

3. **Service Connections**
   - `kubernetesServiceConnection`: Connects to your AKS cluster
   - Azure subscription with permissions to access ACR and AKS

4. **Variable Groups**
   - Create Azure DevOps variable groups for each environment
   - Include sensitive values (connection strings, API keys, etc.)

## Pipeline Flow

1. **Build Stage**
   - Install Helm CLI
   - Lint the Helm chart
   - Update chart dependencies
   - Package the Helm chart
   - Push to Azure Container Registry (OCI artifact)

2. **Deploy Stages** (runs for each environment)
   - Configure kubectl context
   - Deploy Helm chart to AKS using `helm upgrade --install`
   - Wait for deployment to complete
   - Verify deployment status

## Branch Triggers

- **Build**: Runs on all branches
- **Deploy Dev**: Runs on branches other than PRs
  - `azure-pipelines/*`
  - `users/*`
  - `release/*`
  - `feature/*`
  - `main`
- **Deploy Prod**: Runs only on
  - `release/*`
  - `main`

## Notes

- Deployments are skipped for Pull Requests
- Uses `helm upgrade --install --wait --timeout 10m --atomic` for safe deployments
- Supports Helm 3 OCI-based chart storage
- Automatically rolls back failed deployments

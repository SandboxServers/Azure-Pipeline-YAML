# Quick Start Guide - Helm+K8s Deployment

This guide will help you set up the Helm+K8s deployment templates for MeridianConsole.

## Step 1: Add Variable Files to MeridianConsole

Create the following files in your MeridianConsole repository:

### `pipeline/variables/build.yml`
```yaml
variables:
  # Helm chart configuration
  helmChartName: meridian-console
  helmChartPath: deploy/kubernetes/helm/meridian-console
  helmVersion: 3.13.0

  # ACR configuration
  acrName: meridianconsoleacr
```

### `pipeline/variables/dev.yml`
```yaml
variables:
  environmentName: dev
  kubernetesNamespace: meridian-dev
  releaseName: meridian-console-dev
```

### `pipeline/variables/prod.yml`
```yaml
variables:
  environmentName: prod
  kubernetesNamespace: meridian-prod
  releaseName: meridian-console
```

## Step 2: Create Azure DevOps Variable Groups

In Azure DevOps, create the following variable groups (or add variables to existing ones):

### Variable Group: `MeridianConsole-dev`
- Environment-specific secrets and configs

### Variable Group: `MeridianConsole-prod`
- Environment-specific secrets and configs

## Step 3: Create or Update Azure Pipelines

### Option A: New Pipeline
Create a new pipeline in MeridianConsole using the example template:

See: `example-pipeline.yml` in the Helm+K8s templates

### Option B: Update Existing Pipeline
Update your existing `azure-pipelines.yml` to extend the Helm+K8s template:

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

## Step 4: Configure Required Resources

### 1. Azure Container Registry (ACR)
```bash
az acr create --name meridianconsoleacr --resource-group myResourceGroup --sku Basic
```

### 2. Azure Kubernetes Service (AKS)
```bash
az aks create --name meridian-aks --resource-group myResourceGroup --node-count 2
```

### 3. Service Connections in Azure DevOps

**ACR Service Connection:**
- Go to Project Settings > Service connections
- Create a new Azure Resource Manager service connection
- Connect to your ACR

**Kubernetes Service Connection:**
- Go to Project Settings > Service connections
- Create a new Kubernetes service connection
- Connect to your AKS cluster
- Name it: `meridian-aks-connection`

## Step 5: Set Pipeline Variables

In Azure DevOps, configure these pipeline variables:

- `kubernetesServiceConnection`: meridian-aks-connection
- `acrLoginServer`: meridianconsoleacr.azurecr.io
- `helmRegistry`: oci://meridianconsoleacr.azurecr.io/helm

## Step 6: Test the Pipeline

1. Commit your changes
2. Push to a feature branch
3. Run the pipeline
4. Verify the Helm chart is published to ACR
5. Deploy to dev environment
6. Verify deployment in AKS

## Troubleshooting

### Helm Chart Not Found
- Verify the ACR name is correct
- Check that the Helm chart path exists in your repository

### Permission Errors
- Verify the service connection has proper permissions to ACR and AKS
- Ensure the Azure subscription is accessible from Azure DevOps

### Deployment Fails
- Check the AKS cluster is accessible
- Verify the Kubernetes namespace exists
- Review Helm deployment logs in Azure Pipelines

## Next Steps

- Add monitoring and logging
- Configure Helm values for each environment
- Set up automated testing
- Add database migration scripts
- Configure CI/CD for Docker images (if needed)

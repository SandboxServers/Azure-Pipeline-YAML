# Helm+K8s Templates - Complete Reference

## Overview

This template set provides Azure DevOps pipeline templates for building, publishing, and deploying Helm charts to Kubernetes clusters (AKS). It follows the same pattern as the existing SWA+Functions+SQL and Dhadgar.CI templates.

## Directory Structure

```
Templates/Helm+K8s/
├── Pipeline/
│   └── Pipeline.yml              # Main pipeline orchestrator
├── Stages/
│   ├── Build.yml                 # Build & publish stage
│   └── Deploy.yml                # Deploy stage (multi-env)
├── Jobs/
│   ├── publish.yml               # Publish Helm chart job
│   └── deploy.yml                # Deploy Helm chart job
├── Steps/
│   └── Helm/
│       ├── Lint.yml              # Lint Helm chart
│       ├── Package.yml           # Package Helm chart
│       ├── Publish.yml           # Push to ACR (OCI)
│       └── Deploy.yml            # Deploy to Kubernetes
├── variables/
│   ├── build.yml                 # Build configuration
│   ├── dev.yml                   # Dev environment config
│   ├── prod.yml                  # Prod environment config
│   └── pipeline.yml              # Pipeline-wide config
├── README.md                     # Template documentation
├── QUICKSTART.md                 # Quick start guide
└── example-pipeline.yml          # Example usage
```

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Pipeline Trigger                         │
│                  (branches, paths, PRs)                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │   Build Stage   │
              ├─────────────────┤
              │ 1. Checkout     │
              │ 2. Install Helm │
              │ 3. Add Repo     │
              │ 4. Login ACR    │
              │ 5. Lint Chart   │
              │ 6. Update Deps  │
              │ 7. Package      │
              │ 8. Push to ACR  │
              └────────┬────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Is Build Reason PR?        │
        └───────┬──────────┬──────────┘
                │ Yes      │ No
                ▼          ▼
             Stop    ┌─────────────────┐
                     │  Deploy Stage   │
                     │  (Per Env)      │
                     ├─────────────────┤
                     │ 1. kubectl cfg  │
                     │ 2. Helm Upgrade │
                     │ 3. Wait & Test  │
                     │ 4. Verify       │
                     └─────────────────┘
```

## Key Features

### Build Stage
- **Helm Linting**: Validates chart syntax and best practices
- **Dependency Management**: Automatically updates chart dependencies (Bitnami charts)
- **ACR Integration**: Pushes Helm charts as OCI artifacts to Azure Container Registry
- **Version Tracking**: Captures and outputs chart version for downstream stages

### Deploy Stage
- **Multi-Environment**: Supports dev, staging, prod, and custom environments
- **Atomic Deployments**: Uses `helm upgrade --install --wait --atomic` for safe deployments
- **Auto Rollback**: Failed deployments automatically roll back
- **Namespace Isolation**: Each environment uses dedicated Kubernetes namespaces
- **Deployment Gates**: Branch-based deployment triggers (PRs skipped)

### Environment Triggers
- **Dev**: Runs on `azure-pipelines/*`, `users/*`, `release/*`, `feature/*`, `main`
- **Prod**: Runs only on `release/*`, `main`
- **PR**: Skips deployment, only builds

## Template Parameters

### Pipeline.yml
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| Environments | object | dev,prod | Environment definitions |
| ChartName | string | meridian-console | Helm chart name |
| ChartPath | string | deploy/.../meridian-console | Path to chart |
| ACRName | string | meridianconsoleacr | ACR name |
| HelmVersion | string | 3.13.0 | Helm CLI version |
| VariableLocation | string | /pipeline/variables | Var files path |

### Build.yml
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ChartName | string | - | Chart name |
| ChartPath | string | - | Chart path |
| ACRName | string | - | ACR name |
| HelmVersion | string | - | Helm version |

### Deploy.yml
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ChartName | string | - | Chart name |
| Environment | string | - | Environment name |
| Namespace | string | - | K8s namespace |
| ReleaseName | string | - | Helm release name |
| ValuesFile | string | - | Values file path |
| ChartVersion | string | - | Chart version |
| HelmRegistry | string | - | OCI registry URL |

## Required Infrastructure

### Azure Resources
1. **Azure Container Registry (ACR)**
   - Stores Helm charts as OCI artifacts
   - Minimum SKU: Basic

2. **Azure Kubernetes Service (AKS)**
   - Runs the Helm-deployed applications
   - Recommended: 2+ nodes for production

3. **Azure Key Vault** (optional)
   - Store sensitive values (connection strings, API keys)
   - Reference from Helm values files

### Azure DevOps Resources
1. **Service Connections**
   - ACR service connection
   - AKS service connection (Kubernetes)

2. **Variable Groups**
   - Environment-specific variables (dev, prod)
   - Pipeline-wide variables
   - Secrets (use Azure Key Vault integration)

## Best Practices

### 1. Chart Versioning
- Follow Semantic Versioning (SemVer)
- Update `Chart.yaml` version on changes
- Use tags for releases (v1.0.0, v1.1.0)

### 2. Values Management
- Keep default values in `values.yaml`
- Override per-environment values in separate files
- Store secrets in Azure Key Vault

### 3. Deployment Strategy
- Use atomic deployments with `--wait --atomic`
- Implement deployment gates for production
- Monitor deployments with Azure Monitor/Prometheus

### 4. Security
- Use least-privilege service accounts
- Implement network policies
- Enable pod security standards
- Scan container images (use ACR image scanning)

### 5. Observability
- Enable Kubernetes event logging
- Configure application insights/monitoring
- Set up alerting for failed deployments

## Integration with Existing Templates

The Helm+K8s templates follow the same conventions as existing templates:

### Similar to SWA+Functions+SQL
- Multi-stage pipeline (Build, Deploy)
- Environment-specific variables
- Branch-based triggers
- Template inheritance with `extends`

### Similar to Dhadgar.CI
- Service-based architecture
- Configurable build and deployment
- Reusable step templates

## Customization Examples

### Adding a New Environment
```yaml
Environments:
- env: dev
  namespace: meridian-dev
  releaseName: meridian-console-dev
- env: staging
  namespace: meridian-staging
  releaseName: meridian-console-staging
- env: prod
  namespace: meridian-prod
  releaseName: meridian-console
```

### Custom Helm Values
Create `pipeline/values/staging.yml`:
```yaml
variables:
  environmentName: staging
  kubernetesNamespace: meridian-staging
  releaseName: meridian-console-staging

  # Staging-specific values
  valuesFile: values-staging.yaml
  resources:
    cpu: 750m
    memory: 768Mi
```

### Adding Post-Deploy Steps
Edit `deploy.yml` to add steps after Helm deployment:
```yaml
- template: ../../Standalone/Steps/Helm/Deploy.yml@YAML
  parameters:
    # ... existing parameters ...
    upgrade: true

- bash: |
    # Custom health checks
    kubectl rollout status deployment/meridian-console -n ${{ parameters.namespace }}
  displayName: Verify deployment
```

## Troubleshooting

### Common Issues

1. **Chart not found in ACR**
   - Verify ACR login in publish job
   - Check ACR permissions
   - Ensure chart was successfully published

2. **Deployment timeout**
   - Increase `--timeout` value in Deploy.yml
   - Check resource limits in values files
   - Verify AKS cluster health

3. **Namespace not found**
   - Ensure namespace is created or set `--create-namespace` flag
   - Verify namespace permissions

4. **Image pull errors**
   - Check imagePullSecrets configuration
   - Verify ACR authentication
   - Ensure images exist in ACR

### Debugging

Enable verbose logging:
```yaml
steps:
- bash: |
    set -x  # Enable debug output
    helm upgrade --install --debug ...
```

Check Helm deployment status:
```bash
helm list -n <namespace>
helm status <release> -n <namespace>
helm get values <release> -n <namespace>
```

## Support and Contributing

For issues or questions:
1. Check the README.md for documentation
2. Review QUICKSTART.md for setup instructions
3. Refer to Azure DevOps pipeline logs
4. Examine Helm chart documentation

## License

Follows the same license as the Azure-Pipeline-YAML repository.

# Helm+K8s Pipeline Templates (Improved)

## Code Smells Fixed

### Critical Issues Resolved
1. **Variable Scoping**: Fixed cross-stage variable passing using job output variables (`isOutput=true`)
2. **Parameter Casing**: Fixed `Environment.env` vs `environment.env` inconsistency
3. **kubectl Configuration**: Removed unnecessary `kubectl config use-context` (auto-handled by Azure DevOps)
4. **Namespace Creation**: Added `--create-namespace` flag to Helm deployments

### High Priority Issues Resolved
5. **Service Connection Parameters**: Added `ACRServiceConnection` parameter
6. **Error Handling**: Added comprehensive error handling with `set -e`
7. **Timeout Values**: Parameterized `DeployTimeout` and `TestTimeout` with defaults
8. **Values File Validation**: Added file existence checks before deployment
9. **Retry Logic**: Added retry mechanisms for Helm push and deploy operations

### Medium Priority Issues Resolved
10. **Chart Path Validation**: Added validation before operations
11. **Dependency Management**: Improved error handling for dependency updates
12. **ACR Login**: Added better error handling and token validation
13. **Helm Tests**: Added non-blocking test execution with proper condition

## Key Improvements

### 1. Robust Variable Passing
```yaml
# Build stage sets output variable
echo "##vso[task.setvariable variable=CHART_VERSION;isOutput=true]$CHART_VERSION"

# Deploy stage references it
ChartVersion: $[ stageDependencies.Build.publish.outputs['publish_helm.CHART_VERSION'] ]
```

### 2. Enhanced Error Handling
- All bash scripts use `set -e` for immediate error exit
- Validation checks before operations
- Meaningful error messages with emojis
- Retry logic for transient failures

### 3. Parameterized Timeouts
```yaml
# Pipeline level
parameters:
  DeployTimeout: '10m'
  TestTimeout: '5m'

# Step level uses them
--timeout ${{ parameters.timeout }}
```

### 4. Flexible Dependencies
- Environment variable override for Helm repositories
- Warning if dependency add fails (doesn't break pipeline)
- Skip if no dependencies exist

### 5. Namespace Management
- Auto-create namespaces with `--create-namespace`
- Validate namespace is provided
- Clear error messages for missing namespaces

### 6. Values File Handling
- Warn if values file doesn't exist (doesn't fail)
- Continue deployment without values if missing
- Clear logging of values file usage

## Additional Improvements

### Logging Enhancements
- Detailed deployment configuration output
- Status updates with emojis for clarity
- Debug mode for Helm deployments

### Security
- Token validation before use
- No sensitive values in logs
- Proper service connection handling

### Debugging Support
- `--debug` flag for Helm operations
- Detailed status checks
- Resource listing after deployment

## Usage

The templates maintain backward compatibility with new optional parameters:

```yaml
extends:
  template: Templates/Helm+K8s/Pipeline/Pipeline.yml@YAML
  parameters:
    ChartName: meridian-console
    ChartPath: deploy/kubernetes/helm/meridian-console
    ACRName: meridianconsoleacr
    HelmVersion: 3.13.0
    VariableLocation: /pipeline/variables

    # New optional parameters
    ACRServiceConnection: 'my-acr-connection'
    DeployTimeout: '15m'      # Optional, default: 10m
    TestTimeout: '10m'         # Optional, default: 5m
```

## Testing Recommendations

1. Test chart version propagation between stages
2. Test namespace auto-creation
3. Test timeout configurations
4. Test retry logic with transient failures
5. Test with missing values file
6. Test service connection authentication

## Migration Notes

If using previous version:
- Update Pipeline.yml to pass new optional parameters
- No changes required for environment configuration
- Variables structure remains unchanged
- Backward compatible - old pipelines will work

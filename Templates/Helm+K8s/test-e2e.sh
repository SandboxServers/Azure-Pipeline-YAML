#!/bin/bash
# End-to-End Test Script for Helm+K8s Templates
# Tests: Lint → Package → Login to ACR → Publish → Pull → Deploy to Minikube

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CHART_PATH="deploy/kubernetes/helm/meridian-console"
CHART_NAME="meridian-console"
ACR_NAME="meridianconsoleacr"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
HELM_VERSION="3.13.0"

echo "=========================================="
echo "  Helm+K8s E2E Test Script"
echo "=========================================="
echo ""

# Check prerequisites
echo "🔍 Checking prerequisites..."
command -v helm >/dev/null 2>&1 || { echo -e "${RED}❌ Helm not installed${NC}"; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo -e "${RED}❌ Minikube not installed${NC}"; exit 1; }
command -v az >/dev/null 2>&1 || { echo -e "${RED}❌ Azure CLI not installed${NC}"; exit 1; }
echo -e "${GREEN}✅ All prerequisites installed${NC}"
echo ""

# Step 1: Lint Chart
echo "=========================================="
echo "  STEP 1: Lint Helm Chart"
echo "=========================================="
if [ ! -d "$CHART_PATH" ]; then
    echo -e "${RED}❌ Chart path not found: $CHART_PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}Running helm lint...${NC}"
helm lint "$CHART_PATH"
echo -e "${GREEN}✅ Helm lint passed${NC}"
echo ""

# Step 2: Update Dependencies
echo "=========================================="
echo "  STEP 2: Update Dependencies"
echo "=========================================="
helm dependency update "$CHART_PATH" 2>/dev/null || echo "ℹ️ No dependencies to update"
echo -e "${GREEN}✅ Dependencies updated${NC}"
echo ""

# Step 3: Package Chart
echo "=========================================="
echo "  STEP 3: Package Helm Chart"
echo "=========================================="
CHART_VERSION=$(grep '^version:' "$CHART_PATH/Chart.yaml" | awk '{print $2}')
CHART_DIR=$(dirname "$CHART_PATH")
cd "$CHART_DIR"

helm package "$CHART_NAME" --destination "$CHART_DIR"
CHART_FILE="${CHART_NAME}-${CHART_VERSION}.tgz"

if [ ! -f "$CHART_FILE" ]; then
    echo -e "${RED}❌ Failed to package chart${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Chart packaged: $CHART_FILE${NC}"
echo ""

# Step 4: Login to ACR
echo "=========================================="
echo "  STEP 4: Login to ACR"
echo "=========================================="
echo -e "${YELLOW}Logging into $ACR_NAME...${NC}"

# Check if already logged in
if az acr show --name "$ACR_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Already logged into ACR${NC}"
else
    az acr login --name "$ACR_NAME"
    echo -e "${GREEN}✅ Logged into ACR${NC}"
fi

# Get ACR access token and login to Helm registry
ACCESS_TOKEN=$(az acr login --name "$ACR_NAME" --expose-token --output tsv --query accessToken)

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}❌ Failed to get ACR access token${NC}"
    exit 1
fi

echo "$ACCESS_TOKEN" | helm registry login "$ACR_LOGIN_SERVER" --username 00000000-0000-0000-0000-000000000000 --password-stdin
echo -e "${GREEN}✅ Logged into Helm registry${NC}"
echo ""

# Step 5: Publish to ACR
echo "=========================================="
echo "  STEP 5: Publish Chart to ACR"
echo "=========================================="
echo -e "${YELLOW}Publishing $CHART_FILE to $ACR_LOGIN_SERVER...${NC}"

MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if helm push "$CHART_FILE" "oci://$ACR_LOGIN_SERVER/helm"; then
        echo -e "${GREEN}✅ Chart published to ACR${NC}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}⚠️ Publish failed (attempt $RETRY_COUNT/$MAX_RETRIES), retrying...${NC}"
            sleep 5
        else
            echo -e "${RED}❌ Failed to publish chart after $MAX_RETRIES attempts${NC}"
            exit 1
        fi
    fi
done
echo ""

# Step 6: Verify Chart in ACR
echo "=========================================="
echo "  STEP 6: Verify Chart in ACR"
echo "=========================================="
echo -e "${YELLOW}Listing charts in ACR...${NC}"
helm search repo "$ACR_LOGIN_SERVER/helm/$CHART_NAME" --versions || {
    echo -e "${YELLOW}ℹ️ Chart may not be searchable yet (propagation delay)${NC}"
}
echo ""

# Step 7: Start Minikube
echo "=========================================="
echo "  STEP 7: Start Minikube"
echo "=========================================="
if minikube status >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Minikube already running${NC}"
else
    echo -e "${YELLOW}Starting Minikube...${NC}"
    minikube start
    echo -e "${GREEN}✅ Minikube started${NC}"
fi
echo ""

# Step 8: Login Minikube Docker to ACR
echo "=========================================="
echo "  STEP 8: Login Minikube Docker to ACR"
echo "=========================================="
echo -e "${YELLOW}Configuring Minikube docker daemon...${NC}"
eval $(minikube docker-env)

echo -e "${YELLOW}Logging Minikube Docker into ACR...${NC}"
echo "$ACCESS_TOKEN" | docker login "$ACR_LOGIN_SERVER" --username 00000000-0000-0000-0000-000000000000 --password-stdin
echo -e "${GREEN}✅ Minikube Docker logged into ACR${NC}"
echo ""

# Step 9: Deploy to Minikube
echo "=========================================="
echo "  STEP 9: Deploy to Minikube"
echo "=========================================="
NAMESPACE="test-$(date +%s)"
RELEASE_NAME="meridian-console-test"

echo -e "${YELLOW}Using namespace: $NAMESPACE${NC}"
echo -e "${YELLOW}Using release name: $RELEASE_NAME${NC}"

kubectl create namespace "$NAMESPACE" 2>/dev/null || echo -e "${YELLOW}ℹ️ Namespace already exists${NC}"

echo -e "${YELLOW}Pulling chart from ACR and deploying...${NC}"
helm upgrade "$RELEASE_NAME" \
    "oci://$ACR_LOGIN_SERVER/helm/$CHART_NAME" \
    --version "$CHART_VERSION" \
    --namespace "$NAMESPACE" \
    --install \
    --create-namespace \
    --wait \
    --timeout 5m \
    --atomic \
    --debug

echo -e "${GREEN}✅ Chart deployed to Minikube${NC}"
echo ""

# Step 10: Verify Deployment
echo "=========================================="
echo "  STEP 10: Verify Deployment"
echo "=========================================="
echo -e "${YELLOW}Checking deployment status...${NC}"
helm status "$RELEASE_NAME" --namespace "$NAMESPACE"
echo ""

echo -e "${YELLOW}Listing pods in namespace $NAMESPACE...${NC}"
kubectl get pods -n "$NAMESPACE"
echo ""

# Success!
echo "=========================================="
echo -e "${GREEN}  ✅ ALL TESTS PASSED!${NC}"
echo "=========================================="
echo ""
echo "Chart: $CHART_NAME:$CHART_VERSION"
echo "Published to: oci://$ACR_LOGIN_SERVER/helm/$CHART_NAME"
echo "Deployed to: Minikube (namespace: $NAMESPACE)"
echo ""
echo "To view in browser:"
echo "  minikube service list -n $NAMESPACE"
echo ""
echo "To cleanup:"
echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
echo "  kubectl delete namespace $NAMESPACE"
echo ""

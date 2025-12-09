#!/bin/bash
# Planet Proxy - Complete Installation Script
#
# Usage:
#   Interactive mode:  ./install.sh
#   From env vars:     ./install.sh --from-env
#
# Environment variables (for --from-env mode):
#   DATABASE_URL      - Database connection string
#   JWT_SECRET        - JWT signing secret
#   API_KEY           - API key
#   GITHUB_USERNAME   - GitHub username (for GHCR)
#   GITHUB_PAT        - GitHub Personal Access Token (for GHCR)
#   GITHUB_EMAIL      - GitHub email (optional)
#   TUNNEL_ID         - Cloudflare Tunnel ID
#   SKIP_SECRETS      - Set to "true" to skip secrets creation
#   SKIP_MONITORING   - Set to "true" to skip monitoring stack
#   SKIP_DASHBOARD    - Set to "true" to skip K8s dashboard

set -e

MODE=${1:-interactive}
NAMESPACE="production"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_step() {
    echo -e "${BLUE}→ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        echo "Install: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    print_success "kubectl installed"

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Please configure your kubeconfig first"
        exit 1
    fi
    print_success "Connected to cluster"

    # Check Helm
    if ! command -v helm &> /dev/null; then
        print_warning "Helm is not installed (required for K8s Dashboard)"
        echo "Install: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        HELM_AVAILABLE=false
    else
        print_success "Helm installed"
        HELM_AVAILABLE=true
    fi

    echo ""
    kubectl cluster-info | head -2
}

# Create namespaces
create_namespaces() {
    print_header "Creating Namespaces"

    kubectl apply -f k8s/base/namespace-production.yaml
    print_success "production namespace"

    kubectl apply -f k8s/haproxy/namespace.yaml
    print_success "haproxy namespace"

    kubectl apply -f k8s/monitoring/namespace.yaml
    print_success "monitoring namespace"

    kubectl apply -f k8s/logging/namespace.yaml
    print_success "logging namespace"
}

# Create secrets interactively
create_secrets_interactive() {
    print_header "Creating Secrets"

    echo "Enter application secrets (input will be hidden):"
    echo ""

    echo "DATABASE_URL:"
    read -s DATABASE_URL
    echo "(set)"

    echo "JWT_SECRET:"
    read -s JWT_SECRET
    echo "(set)"

    echo "API_KEY:"
    read -s API_KEY
    echo "(set)"

    # Create application secrets
    kubectl create secret generic planet-proxy-secrets \
        --from-literal=DATABASE_URL="$DATABASE_URL" \
        --from-literal=JWT_SECRET="$JWT_SECRET" \
        --from-literal=API_KEY="$API_KEY" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Application secrets created"

    # Docker registry secret
    echo ""
    echo "Create Docker registry credentials for GHCR? (y/n)"
    read CREATE_DOCKER_SECRET

    if [ "$CREATE_DOCKER_SECRET" = "y" ]; then
        echo "GitHub username:"
        read GITHUB_USERNAME

        echo "GitHub PAT (with read:packages scope):"
        read -s GITHUB_PAT
        echo "(set)"

        echo "GitHub email:"
        read GITHUB_EMAIL

        kubectl create secret docker-registry ghcr-credentials \
            --docker-server=ghcr.io \
            --docker-username="$GITHUB_USERNAME" \
            --docker-password="$GITHUB_PAT" \
            --docker-email="$GITHUB_EMAIL" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -

        print_success "Docker registry secret created"
    fi
}

# Create secrets from environment variables
create_secrets_from_env() {
    print_header "Creating Secrets from Environment"

    if [ "$SKIP_SECRETS" = "true" ]; then
        print_warning "Skipping secrets creation (SKIP_SECRETS=true)"
        return
    fi

    # Validate required env vars
    if [ -z "$DATABASE_URL" ]; then
        print_error "DATABASE_URL environment variable is not set"
        exit 1
    fi
    if [ -z "$JWT_SECRET" ]; then
        print_error "JWT_SECRET environment variable is not set"
        exit 1
    fi
    if [ -z "$API_KEY" ]; then
        print_error "API_KEY environment variable is not set"
        exit 1
    fi

    # Create application secrets
    kubectl create secret generic planet-proxy-secrets \
        --from-literal=DATABASE_URL="$DATABASE_URL" \
        --from-literal=JWT_SECRET="$JWT_SECRET" \
        --from-literal=API_KEY="$API_KEY" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Application secrets created"

    # Create Docker registry secret if env vars are set
    if [ -n "$GITHUB_USERNAME" ] && [ -n "$GITHUB_PAT" ]; then
        kubectl create secret docker-registry ghcr-credentials \
            --docker-server=ghcr.io \
            --docker-username="$GITHUB_USERNAME" \
            --docker-password="$GITHUB_PAT" \
            --docker-email="${GITHUB_EMAIL:-noreply@github.com}" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -

        print_success "Docker registry secret created"
    fi
}

# Deploy HAProxy
deploy_haproxy() {
    print_header "Deploying HAProxy"

    kubectl apply -k k8s/haproxy/

    print_step "Waiting for HAProxy pods..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=haproxy -n haproxy --timeout=120s || true

    print_success "HAProxy deployed"
}

# Deploy application
deploy_application() {
    print_header "Deploying Application"

    kubectl apply -k k8s/overlays/production

    print_step "Waiting for application pods..."
    kubectl wait --for=condition=ready pod -l app=planet-proxy -n production --timeout=120s || true

    print_success "Application deployed"
}

# Deploy monitoring stack
deploy_monitoring() {
    print_header "Deploying Monitoring Stack"

    if [ "$SKIP_MONITORING" = "true" ]; then
        print_warning "Skipping monitoring (SKIP_MONITORING=true)"
        return
    fi

    # Prometheus
    print_step "Deploying Prometheus..."
    kubectl apply -f k8s/monitoring/prometheus-config.yaml
    kubectl apply -f k8s/monitoring/prometheus-deployment.yaml
    kubectl apply -f k8s/monitoring/alerting-rules.yaml

    # Grafana
    print_step "Deploying Grafana..."
    kubectl apply -f k8s/monitoring/grafana-deployment.yaml
    kubectl apply -f k8s/monitoring/grafana-dashboards.yaml

    # ELK Stack
    print_step "Deploying ELK Stack..."
    kubectl apply -f k8s/logging/elasticsearch.yaml
    kubectl apply -f k8s/logging/fluentd.yaml
    kubectl apply -f k8s/logging/kibana.yaml

    print_success "Monitoring stack deployed"
    print_warning "Grafana default credentials: admin / changeme"
}

# Deploy Kubernetes Dashboard
deploy_dashboard() {
    print_header "Deploying Kubernetes Dashboard"

    if [ "$SKIP_DASHBOARD" = "true" ]; then
        print_warning "Skipping dashboard (SKIP_DASHBOARD=true)"
        return
    fi

    if [ "$HELM_AVAILABLE" = "false" ]; then
        print_warning "Skipping dashboard (Helm not installed)"
        return
    fi

    print_step "Adding Helm repository..."
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ 2>/dev/null || true
    helm repo update

    print_step "Installing dashboard..."
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --create-namespace \
        --namespace kubernetes-dashboard \
        -f k8s/config-dashboard/kubernetes-dashboard.yaml

    print_step "Creating admin user..."
    kubectl apply -f k8s/config-dashboard/dashboard-admin.yaml

    print_success "Kubernetes Dashboard deployed"
}

# Setup Cloudflare Tunnel
setup_cloudflare_interactive() {
    print_header "Cloudflare Tunnel Setup"

    echo "Do you want to setup Cloudflare Tunnel now? (y/n)"
    read SETUP_TUNNEL

    if [ "$SETUP_TUNNEL" != "y" ]; then
        print_warning "Skipping Cloudflare Tunnel setup"
        return
    fi

    # Check if cloudflared is installed
    if ! command -v cloudflared &> /dev/null; then
        print_step "Installing cloudflared..."
        curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
        chmod +x /tmp/cloudflared
        sudo mv /tmp/cloudflared /usr/local/bin/
    fi

    print_success "cloudflared installed"

    echo ""
    echo "Enter your Cloudflare Tunnel ID:"
    read TUNNEL_ID

    if [ -z "$TUNNEL_ID" ]; then
        print_warning "No Tunnel ID provided, skipping"
        return
    fi

    # Check if credentials file exists
    CREDS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
    if [ ! -f "$CREDS_FILE" ]; then
        print_error "Credentials file not found: $CREDS_FILE"
        echo "Run: cloudflared tunnel login && cloudflared tunnel create planet-proxy"
        return
    fi

    # Create secret
    kubectl create secret generic cloudflared-credentials \
        --from-file=credentials.json="$CREDS_FILE" \
        -n production \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Cloudflare credentials secret created"

    # Update tunnel config
    sed -i.bak "s/<YOUR_TUNNEL_ID>/$TUNNEL_ID/g" k8s/cloudflare/tunnel-config-production.yaml

    # Deploy tunnel
    kubectl apply -f k8s/cloudflare/tunnel-config-production.yaml
    kubectl apply -f k8s/cloudflare/tunnel-deployment.yaml

    print_success "Cloudflare Tunnel deployed"
}

# Print summary
print_summary() {
    print_header "Installation Complete!"

    echo "Deployed components:"
    echo "  • HAProxy load balancer"
    echo "  • Planet Proxy application"
    if [ "$SKIP_MONITORING" != "true" ]; then
        echo "  • Prometheus & Grafana"
        echo "  • ELK Stack (Elasticsearch, Fluentd, Kibana)"
    fi
    if [ "$SKIP_DASHBOARD" != "true" ] && [ "$HELM_AVAILABLE" = "true" ]; then
        echo "  • Kubernetes Dashboard"
    fi

    echo ""
    echo "Verify installation:"
    echo "  kubectl get pods -n production"
    echo "  kubectl get pods -n haproxy"
    echo "  kubectl get pods -n monitoring"
    echo "  kubectl get pods -n logging"

    if [ "$SKIP_DASHBOARD" != "true" ] && [ "$HELM_AVAILABLE" = "true" ]; then
        echo ""
        echo "Get K8s Dashboard token:"
        echo "  kubectl -n kubernetes-dashboard create token admin-user"
    fi

    echo ""
    echo "Access via port-forward:"
    echo "  kubectl port-forward svc/haproxy 8080:80 -n haproxy"
    echo "  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "  kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
    echo "  kubectl port-forward svc/kibana 5601:5601 -n logging"

    if [ "$HELM_AVAILABLE" = "true" ]; then
        echo "  kubectl port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 -n kubernetes-dashboard"
    fi

    echo ""
    if [ -z "$TUNNEL_ID" ] && [ "$MODE" = "interactive" ]; then
        echo -e "${YELLOW}Next step: Setup Cloudflare Tunnel for external access${NC}"
        echo "  1. cloudflared tunnel login"
        echo "  2. cloudflared tunnel create planet-proxy"
        echo "  3. Update k8s/cloudflare/tunnel-config-production.yaml with your TUNNEL_ID"
        echo "  4. kubectl create secret generic cloudflared-credentials \\"
        echo "       --from-file=credentials.json=~/.cloudflared/<TUNNEL_ID>.json -n production"
        echo "  5. kubectl apply -f k8s/cloudflare/"
    fi
}

# Main
main() {
    print_header "Planet Proxy Installation"
    echo "Mode: $MODE"

    check_prerequisites
    create_namespaces

    if [ "$MODE" = "--from-env" ]; then
        create_secrets_from_env
    else
        create_secrets_interactive
    fi

    deploy_haproxy
    deploy_application
    deploy_monitoring
    deploy_dashboard

    if [ "$MODE" = "interactive" ]; then
        setup_cloudflare_interactive
    fi

    print_summary
}

main

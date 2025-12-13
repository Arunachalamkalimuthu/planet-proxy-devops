# Planet Proxy DevOps

Kubernetes deployment infrastructure for Planet Proxy Node.js application with HAProxy load balancer and Cloudflare Tunnel integration.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cloudflare Edge                          │
│                  ┌─────────────────────┐                        │
│                  │    domain.com       │                        │
│                  │  api.domain.com     │                        │
│                  └──────────┬──────────┘                        │
└─────────────────────────────┼───────────────────────────────────┘
                              │
                    Cloudflare Tunnel
                              │
┌─────────────────────────────┼───────────────────────────────────┐
│                             ▼                                   │
│                  ┌─────────────────────┐                        │
│                  │     cloudflared     │                        │
│                  │   (production ns)   │                        │
│                  └──────────┬──────────┘                        │
│                             │                                   │
│              ┌──────────────┼──────────────┐                    │
│              ▼              ▼              ▼                    │
│    ┌──────────────┐ ┌─────────────┐ ┌──────────────┐           │
│    │   HAProxy    │ │  Grafana    │ │  K8s         │           │
│    │   (API)      │ │  Prometheus │ │  Dashboard   │           │
│    └──────┬───────┘ │  Kibana     │ │  (Config)    │           │
│           │         └─────────────┘ └──────────────┘           │
│           ▼                                                     │
│    ┌─────────────────────┐                                     │
│    │    Node.js App      │                                     │
│    │    (3 replicas)     │                                     │
│    │     HPA: 3-10       │                                     │
│    └─────────────────────┘                                     │
│                                                                 │
│                  Self-Hosted Kubernetes Cluster                 │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Architecture Diagram

```
                                    INTERNET
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           CLOUDFLARE EDGE                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ SSL/TLS     │  │ DDoS        │  │ WAF         │  │ Cloudflare  │      │
│  │ Termination │  │ Protection  │  │ Rules       │  │ Access      │      │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘      │
│                                        │                                   │
│                            Cloudflare Tunnel                               │
└────────────────────────────────────────┼──────────────────────────────────┘
                                         │
┌────────────────────────────────────────┼──────────────────────────────────┐
│                    KUBERNETES CLUSTER  │                                   │
│                                        ▼                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                    PRODUCTION NAMESPACE                              │  │
│  │  ┌─────────────┐    ┌─────────────────────────────────────────┐    │  │
│  │  │ cloudflared │───▶│              ROUTING                     │    │  │
│  │  │  (tunnel)   │    │  api.* ──────────▶ HAProxy               │    │  │
│  │  └─────────────┘    │  grafana.* ──────▶ Grafana               │    │  │
│  │                     │  prometheus.* ───▶ Prometheus            │    │  │
│  │                     │  kibana.* ───────▶ Kibana                │    │  │
│  │                     │  k8s-dashboard.* ▶ K8s Dashboard         │    │  │
│  │                     └─────────────────────────────────────────┘    │  │
│  │                                                                     │  │
│  │  ┌─────────────────────────────────────────────────────────────┐   │  │
│  │  │                    NODE.JS APPLICATION                       │   │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │   │  │
│  │  │  │ Pod 1   │  │ Pod 2   │  │ Pod 3   │  (HPA: 3-10 replicas)│   │  │
│  │  │  └─────────┘  └─────────┘  └─────────┘                      │   │  │
│  │  └─────────────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                      HAPROXY NAMESPACE                               │  │
│  │  ┌─────────────────────────────────────────────────────────────┐   │  │
│  │  │                    HAPROXY LOAD BALANCER                     │   │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐                      │   │  │
│  │  │  │ Pod 1   │  │ Pod 2   │  │ Pod 3   │  (HPA: 3-20 replicas)│   │  │
│  │  │  └─────────┘  └─────────┘  └─────────┘                      │   │  │
│  │  │                                                              │   │  │
│  │  │  Features:                                                   │   │  │
│  │  │  • Rate Limiting (500 req/10s)                              │   │  │
│  │  │  • URL Rewriting (/gateway/* → /api/peer/1/*)               │   │  │
│  │  │  • Health Checks                                             │   │  │
│  │  │  • Circuit Breaker                                           │   │  │
│  │  │  • Security Headers                                          │   │  │
│  │  └─────────────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                     MONITORING NAMESPACE                             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │  │
│  │  │ Prometheus  │  │  Grafana    │  │ Alertmanager│                 │  │
│  │  │ (metrics)   │  │ (dashboards)│  │  (alerts)   │                 │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │  │
│  │         │                │                │                         │  │
│  │         └────────────────┴────────────────┘                         │  │
│  │                          │                                          │  │
│  │              ServiceMonitor (scrapes metrics)                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                      LOGGING NAMESPACE                               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │  │
│  │  │Elasticsearch│◀─│  Fluentd    │  │   Kibana    │                 │  │
│  │  │  (storage)  │  │ (collector) │  │   (UI)      │                 │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                 KUBERNETES-DASHBOARD NAMESPACE                       │  │
│  │  ┌─────────────────────────────────────────────────────────────┐   │  │
│  │  │              Kubernetes Dashboard                            │   │  │
│  │  │  • View/Edit ConfigMaps                                      │   │  │
│  │  │  • Manage Deployments                                        │   │  │
│  │  │  • View Logs                                                 │   │  │
│  │  │  • Execute Commands                                          │   │  │
│  │  └─────────────────────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

## Request Flow Sequence Diagram

### API Request Flow

```
┌──────┐     ┌────────────┐     ┌───────────┐     ┌─────────┐     ┌─────────┐
│Client│     │ Cloudflare │     │cloudflared│     │ HAProxy │     │ Node.js │
└──┬───┘     └─────┬──────┘     └─────┬─────┘     └────┬────┘     └────┬────┘
   │               │                  │                │               │
   │ HTTPS Request │                  │                │               │
   │──────────────>│                  │                │               │
   │               │                  │                │               │
   │               │ SSL Termination  │                │               │
   │               │ DDoS Protection  │                │               │
   │               │ WAF Rules        │                │               │
   │               │                  │                │               │
   │               │  Tunnel Request  │                │               │
   │               │─────────────────>│                │               │
   │               │                  │                │               │
   │               │                  │ Route by hostname               │
   │               │                  │ (api.domain.com)               │
   │               │                  │                │               │
   │               │                  │  HTTP Request  │               │
   │               │                  │───────────────>│               │
   │               │                  │                │               │
   │               │                  │                │ Rate Limit    │
   │               │                  │                │ Check         │
   │               │                  │                │               │
   │               │                  │                │ URL Rewrite   │
   │               │                  │                │ /gateway/* →  │
   │               │                  │                │ /api/peer/1/* │
   │               │                  │                │               │
   │               │                  │                │ Load Balance  │
   │               │                  │                │──────────────>│
   │               │                  │                │               │
   │               │                  │                │   Response    │
   │               │                  │                │<──────────────│
   │               │                  │                │               │
   │               │                  │                │ Add Security  │
   │               │                  │                │ Headers       │
   │               │                  │                │               │
   │               │                  │  HTTP Response │               │
   │               │                  │<───────────────│               │
   │               │                  │                │               │
   │               │ Tunnel Response  │                │               │
   │               │<─────────────────│                │               │
   │               │                  │                │               │
   │HTTPS Response │                  │                │               │
   │<──────────────│                  │                │               │
   │               │                  │                │               │
└──┴───┘     └─────┴──────┘     └─────┴─────┘     └────┴────┘     └────┴────┘
```

### Admin Dashboard Access Flow

```
┌───────┐     ┌────────────┐     ┌──────────────┐     ┌───────────┐     ┌───────────┐
│ Admin │     │ Cloudflare │     │  Cloudflare  │     │cloudflared│     │  Grafana/ │
│       │     │   Edge     │     │    Access    │     │           │     │  K8s Dash │
└───┬───┘     └─────┬──────┘     └──────┬───────┘     └─────┬─────┘     └─────┬─────┘
    │               │                   │                   │                 │
    │ HTTPS Request │                   │                   │                 │
    │ grafana.domain│                   │                   │                 │
    │──────────────>│                   │                   │                 │
    │               │                   │                   │                 │
    │               │  Check Access     │                   │                 │
    │               │  Policy           │                   │                 │
    │               │──────────────────>│                   │                 │
    │               │                   │                   │                 │
    │               │                   │ Auth Required?    │                 │
    │               │                   │                   │                 │
    │<──────────────────────────────────│                   │                 │
    │  Login Page (Email/SSO)           │                   │                 │
    │               │                   │                   │                 │
    │  Authenticate │                   │                   │                 │
    │──────────────────────────────────>│                   │                 │
    │               │                   │                   │                 │
    │               │                   │ ✓ Authenticated   │                 │
    │               │                   │                   │                 │
    │               │  Tunnel Request   │                   │                 │
    │               │───────────────────────────────────────>                 │
    │               │                   │                   │                 │
    │               │                   │                   │  Forward to     │
    │               │                   │                   │  Service        │
    │               │                   │                   │────────────────>│
    │               │                   │                   │                 │
    │               │                   │                   │    Dashboard    │
    │               │                   │                   │<────────────────│
    │               │                   │                   │                 │
    │<──────────────────────────────────────────────────────│                 │
    │      Dashboard Response           │                   │                 │
    │               │                   │                   │                 │
└───┴───┘     └─────┴──────┘     └──────┴───────┘     └─────┴─────┘     └─────┴─────┘
```

### Deployment Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  GitHub  │     │  GitHub  │     │   GHCR   │     │  Server  │     │   K8s    │
│   Repo   │     │ Actions  │     │ Registry │     │          │     │ Cluster  │
└────┬─────┘     └────┬─────┘     └────┬─────┘     └────┬─────┘     └────┬─────┘
     │                │                │                │                │
     │  Push to main  │                │                │                │
     │───────────────>│                │                │                │
     │                │                │                │                │
     │                │  Build Image   │                │                │
     │                │───────────────>│                │                │
     │                │                │                │                │
     │                │  Push Image    │                │                │
     │                │───────────────>│                │                │
     │                │                │                │                │
     │                │  SSH Deploy    │                │                │
     │                │───────────────────────────────>│                │
     │                │                │                │                │
     │                │                │                │  kubectl apply │
     │                │                │                │───────────────>│
     │                │                │                │                │
     │                │                │                │  Pull Image    │
     │                │                │                │<───────────────│
     │                │                │                │                │
     │                │                │  Image Pull    │                │
     │                │                │<──────────────────────────────────
     │                │                │                │                │
     │                │                │                │ Rolling Update │
     │                │                │                │   Complete     │
     │                │                │                │                │
└────┴─────┘     └────┴─────┘     └────┴─────┘     └────┴─────┘     └────┴─────┘
```

> **Note:** PlantUML diagram files are available in the [docs/](docs/) folder for detailed architecture visualization.

## Repository Structure

```
planet-proxy-devops/
├── docs/                                # Architecture diagrams (PlantUML)
│   ├── architecture.puml
│   ├── sequence-api-request.puml
│   ├── sequence-admin-access.puml
│   ├── sequence-deployment.puml
│   ├── sequence-monitoring.puml
│   └── README.md
├── k8s/
│   ├── base/                             # Base Kubernetes manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── hpa.yaml
│   │   ├── namespace-production.yaml
│   │   └── kustomization.yaml
│   ├── overlays/
│   │   └── production/                   # Production environment overrides
│   │       ├── kustomization.yaml
│   │       └── hpa-patch.yaml
│   ├── haproxy/                          # HAProxy load balancer
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── rbac.yaml
│   │   ├── hpa.yaml
│   │   ├── network-policy.yaml
│   │   ├── servicemonitor.yaml
│   │   └── kustomization.yaml
│   ├── cloudflare/                       # Cloudflare Tunnel configs
│   │   ├── tunnel-deployment.yaml
│   │   ├── tunnel-config-production.yaml
│   │   └── tunnel-secret.yaml.template
│   ├── config-dashboard/                 # Kubernetes Dashboard
│   │   ├── kubernetes-dashboard.yaml
│   │   └── dashboard-admin.yaml
│   ├── monitoring/                       # Prometheus & Grafana
│   │   ├── namespace.yaml
│   │   ├── prometheus-config.yaml
│   │   ├── prometheus-deployment.yaml
│   │   ├── grafana-deployment.yaml
│   │   ├── grafana-dashboards.yaml
│   │   ├── alerting-rules.yaml
│   │   └── servicemonitor.yaml
│   ├── logging/                          # ELK Stack
│   │   ├── namespace.yaml
│   │   ├── elasticsearch.yaml
│   │   ├── fluentd.yaml
│   │   └── kibana.yaml
│   └── secrets/                          # Secret templates
│       ├── app-secrets.yaml.template
│       └── docker-registry-secret.yaml.template
├── scripts/
│   └── install.sh                        # Complete installation script
└── README.md
```

## Prerequisites

### Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **OS** | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| **CPU** | 2 cores | 4 cores |
| **RAM** | 4 GB | 8 GB |
| **Storage** | 40 GB SSD | 80 GB SSD |

> **Recommended OS:** Ubuntu 22.04 LTS (supported until April 2027)

### Other Requirements
- Root or sudo access
- Domain configured in Cloudflare
- GitHub account with Container Registry access

## New Server Deployment Guide

Complete step-by-step guide for deploying on a fresh Ubuntu server.

### Step 1: Initial Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git nano htop
```

### Step 2: Install K3s (Lightweight Kubernetes)

```bash
# Install K3s
curl -sfL https://get.k3s.io | sh -

# Wait for K3s to be ready
sudo systemctl status k3s

# Setup kubectl for current user
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Add to bashrc for persistence
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
export KUBECONFIG=~/.kube/config

# Verify cluster is running
kubectl get nodes
```

### Step 3: Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### Step 4: Clone the DevOps Repository

```bash
git clone https://github.com/your-org/planet-proxy-devops.git
cd planet-proxy-devops
chmod +x scripts/*.sh
```

### Step 5: Run the Installation Script

**Option A: Interactive Mode (Recommended for first-time)**
```bash
./scripts/install.sh
```
This will prompt you for:
- GitHub credentials (for pulling images from GHCR)
- Cloudflare Tunnel setup

**Option B: Automated Mode (CI/CD or scripted setup)**
```bash
# Set environment variables
export GITHUB_USERNAME="your-github-username"
export GITHUB_PAT="ghp_your-personal-access-token"

# Run installation
./scripts/install.sh --from-env
```

**Option C: Minimal Installation (skip monitoring)**
```bash
export SKIP_MONITORING=true
export SKIP_DASHBOARD=true

./scripts/install.sh --from-env
```

### Step 6: Setup Cloudflare Tunnel

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared
sudo mv cloudflared /usr/local/bin/

# Authenticate with Cloudflare (opens browser)
cloudflared tunnel login

# Create a new tunnel
cloudflared tunnel create planet-proxy
# Note the TUNNEL_ID from the output

# Create Kubernetes secret with tunnel credentials
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=~/.cloudflared/<TUNNEL_ID>.json \
  -n production

# Update tunnel config with your TUNNEL_ID
nano k8s/cloudflare/tunnel-config-production.yaml
# Replace <YOUR_TUNNEL_ID> with your actual tunnel ID

# Deploy the tunnel
kubectl apply -f k8s/cloudflare/tunnel-config-production.yaml
kubectl apply -f k8s/cloudflare/tunnel-deployment.yaml
```

### Step 7: Configure Cloudflare DNS

In Cloudflare Dashboard → DNS → Add CNAME records:

| Type | Name | Target |
|------|------|--------|
| CNAME | @ | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | www | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | api | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | grafana | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | prometheus | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | kibana | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | haproxy-stats | `<TUNNEL_ID>.cfargotunnel.com` |
| CNAME | k8s-dashboard | `<TUNNEL_ID>.cfargotunnel.com` |

### Step 8: Setup Cloudflare Access (Secure Admin Endpoints)

In Cloudflare Dashboard → Zero Trust → Access → Applications:

1. Create a new application
2. Add hostnames: `grafana.yourdomain.com`, `prometheus.yourdomain.com`, `kibana.yourdomain.com`, `haproxy-stats.yourdomain.com`, `k8s-dashboard.yourdomain.com`
3. Set policy: Allow only your email domain or specific emails
4. Save

### Step 9: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Check specific namespaces
kubectl get pods -n production
kubectl get pods -n haproxy
kubectl get pods -n monitoring
kubectl get pods -n logging

# Check services
kubectl get svc -A

# Test HAProxy health
kubectl run debug --rm -it --image=alpine -- wget -qO- http://haproxy.haproxy.svc.cluster.local/health
```

### Step 10: Access Your Services

After DNS propagation (1-5 minutes):

| Service | URL |
|---------|-----|
| API | `https://api.yourdomain.com` |
| Website | `https://yourdomain.com` |
| Grafana | `https://grafana.yourdomain.com` |
| Prometheus | `https://prometheus.yourdomain.com` |
| Kibana | `https://kibana.yourdomain.com` |
| HAProxy Stats | `https://haproxy-stats.yourdomain.com` |
| K8s Dashboard | `https://k8s-dashboard.yourdomain.com` |

**Get K8s Dashboard Token:**
```bash
kubectl -n kubernetes-dashboard create token admin-user
```

## Component Details

### HAProxy Features

| Feature | Description |
|---------|-------------|
| **Rate Limiting** | 500 requests/10s per IP |
| **Connection Limit** | Max 200 concurrent connections per IP |
| **Health Checks** | Active health checks on `/health` endpoint |
| **Circuit Breaker** | Automatic server removal on 3 consecutive failures |
| **URL Rewriting** | `/gateway/*` → `/api/peer/1/*` |
| **Security Headers** | X-Frame-Options, X-Content-Type-Options, XSS Protection |
| **Prometheus Metrics** | Exposed on port 8404 |

### Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| Grafana | admin | changeme |

### Port Forward Commands (Local Access)

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
kubectl port-forward svc/grafana 3000:3000 -n monitoring
kubectl port-forward svc/kibana 5601:5601 -n logging
kubectl port-forward svc/haproxy 8404:8404 -n haproxy
kubectl port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 -n kubernetes-dashboard
```

## Production Configuration

| Setting | Value |
|---------|-------|
| App Replicas | 3 (HPA: 3-20) |
| HAProxy Replicas | 3 (HPA: 3-20) |
| CPU Request | 200m |
| CPU Limit | 1000m |
| Memory Request | 256Mi |
| Memory Limit | 1Gi |
| NODE_ENV | production |
| LOG_LEVEL | warn |

## Troubleshooting

```bash
# Check pods
kubectl get pods -n production
kubectl get pods -n haproxy
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n kubernetes-dashboard

# View logs
kubectl logs -l app=planet-proxy -n production --tail=100
kubectl logs -l app.kubernetes.io/name=haproxy -n haproxy --tail=100
kubectl logs -l app=cloudflared -n production --tail=50

# Debug connectivity
kubectl run debug --rm -it --image=alpine -- sh
wget -qO- http://haproxy.haproxy.svc.cluster.local/health
```

## Security Best Practices

- All secrets stored as Kubernetes Secrets (never in Git)
- Container runs as non-root user
- Read-only root filesystem enabled
- Resource limits enforced
- Network policies restrict traffic
- HAProxy provides rate limiting and security headers
- Cloudflare provides DDoS protection and SSL termination
- Cloudflare Access protects admin endpoints
- Kubernetes Dashboard requires token authentication

## License

MIT

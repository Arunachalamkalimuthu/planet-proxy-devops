# Architecture Diagrams

PlantUML diagrams for Planet Proxy infrastructure.

## Files

| File | Description |
|------|-------------|
| `architecture.puml` | Complete system architecture diagram |
| `sequence-api-request.puml` | API request flow sequence diagram |
| `sequence-admin-access.puml` | Admin dashboard access flow |
| `sequence-deployment.puml` | CI/CD deployment pipeline |
| `sequence-monitoring.puml` | Monitoring and logging flow |

## Viewing Diagrams

### Option 1: PlantUML Online Server
1. Go to [PlantUML Web Server](http://www.plantuml.com/plantuml/uml/)
2. Paste the content of any `.puml` file
3. Click "Submit" to render

### Option 2: VS Code Extension
1. Install "PlantUML" extension
2. Open any `.puml` file
3. Press `Alt+D` to preview

### Option 3: Command Line
```bash
# Install PlantUML
brew install plantuml  # macOS
apt install plantuml   # Ubuntu

# Generate PNG
plantuml architecture.puml

# Generate SVG
plantuml -tsvg architecture.puml
```

### Option 4: Docker
```bash
docker run -v $(pwd):/data plantuml/plantuml architecture.puml
```

## Diagrams Overview

### 1. System Architecture (`architecture.puml`)
Shows the complete infrastructure including:
- Cloudflare Edge (SSL, DDoS, WAF, Access)
- Kubernetes namespaces (production, haproxy, monitoring, logging, dashboard)
- Component relationships and data flow

### 2. API Request Flow (`sequence-api-request.puml`)
Shows how API requests flow through:
- Client → Cloudflare (SSL termination, DDoS, WAF)
- Cloudflare → cloudflared (tunnel)
- cloudflared → HAProxy (rate limiting, URL rewrite)
- HAProxy → Node.js (load balanced)

### 3. Admin Access Flow (`sequence-admin-access.puml`)
Shows admin dashboard access:
- Cloudflare Access authentication
- Zero Trust policy enforcement
- Dashboard access after authentication

### 4. Deployment Flow (`sequence-deployment.puml`)
Shows CI/CD pipeline:
- GitHub Actions workflow
- Docker image build and push to GHCR
- SSH deployment to server
- Kubernetes rolling update

### 5. Monitoring Flow (`sequence-monitoring.puml`)
Shows observability stack:
- Prometheus metrics scraping
- Fluentd log collection
- Grafana dashboards
- Kibana log search
- Alertmanager notifications

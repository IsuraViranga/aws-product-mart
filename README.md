# CloudMart — Starter Code

**IS 4630 Cloud Infrastructure Management | University of Moratuwa**

CloudMart is a microservices-based e-commerce platform used as the group assignment project for IS 4630. This repository contains fully working starter code for all five services.

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Frontend   │────▶│  product-service │     │   user-service   │
│  (React/Nginx│────▶│  (Flask :8001)   │     │  (Flask :8003)   │
│   :80/443)   │────▶│                  │     │  JWT + bcrypt    │
│              │     └──────────────────┘     └──────────────────┘
│              │────▶┌──────────────────┐
│              │     │  order-service   │────▶ product-service
└──────────────┘     │  (Express :8002) │        (stock check)
                     │                  │
                     └───────┬──────────┘
                             │ publishes
                             ▼
                     ┌──────────────────┐
                     │  Message Queue   │
                     │  (in-memory/SQS/ │
                     │   Pub-Sub/SB)    │
                     └───────┬──────────┘
                             │ consumes
                             ▼
                     ┌──────────────────┐
                     │ notification-svc │
                     │  (Node.js :8004) │
                     │  sends emails    │
                     └──────────────────┘
```

## Services

| Service | Port | Language | Description |
|---------|------|----------|-------------|
| **product-service** | 8001 | Python/Flask | Product catalogue CRUD, search, categories, stock management |
| **order-service** | 8002 | Node.js/Express | Order creation, status management, publishes events to queue |
| **user-service** | 8003 | Python/Flask | User registration, JWT authentication, profile management |
| **notification-service** | 8004 | Node.js | Consumes order events, sends email notifications |
| **frontend** | 80 | React/Nginx | SPA with product browsing, cart, checkout, order history |

## Quick Start (Local Development)

### Prerequisites

- Docker Desktop installed and running
- Git

### Run with Docker Compose

```bash
git clone <your-repo-url>
cd cloudmart-starter
docker compose up --build
```

Open http://localhost:3000 in your browser.

**Demo credentials:** `alice@cloudmart.example` / `password123`

### Test individual services

```bash
# Health checks
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:8004/health

# List products
curl http://localhost:8001/products

# Search products
curl "http://localhost:8001/products?search=headphone"

# Filter by category
curl "http://localhost:8001/products?category=electronics"

# Register a new user
curl -X POST http://localhost:8003/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com","password":"password123"}'

# Login
curl -X POST http://localhost:8003/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@cloudmart.example","password":"password123"}'

# Create an order (use the token from login response)
curl -X POST http://localhost:8002/orders \
  -H "Content-Type: application/json" \
  -d '{"userId":"user-001","items":[{"productId":"prod-001","quantity":1}]}'

# Check notification log
curl http://localhost:8004/notifications
```

## Cloud Adapter Pattern

All services use an **adapter pattern** for cloud backends. By default, they run with in-memory data stores (no cloud credentials needed). To connect to cloud-managed services, set the appropriate environment variables:

### Product Service

| Variable | Values | Description |
|----------|--------|-------------|
| `STORE_BACKEND` | `memory` (default), `dynamodb`, `firestore`, `cosmosdb` | Data store backend |
| `DYNAMODB_TABLE` | Table name | Required when STORE_BACKEND=dynamodb |
| `FIRESTORE_COLLECTION` | Collection name | Required when STORE_BACKEND=firestore |

When you run the product service in Docker with `STORE_BACKEND=dynamodb`, make sure the container can see your local AWS profile files. The provided Compose file mounts `${USERPROFILE}/.aws` into `/app/.aws`, which is the home directory used by the non-root app user in the image.

### Order Service

| Variable | Values | Description |
|----------|--------|-------------|
| `QUEUE_BACKEND` | `memory` (default), `sqs`, `pubsub`, `servicebus` | Message queue backend |
| `SQS_QUEUE_URL` | Queue URL | Required when QUEUE_BACKEND=sqs |
| `PUBSUB_TOPIC` | Topic name | Required when QUEUE_BACKEND=pubsub |

### User Service

| Variable | Values | Description |
|----------|--------|-------------|
| `DB_BACKEND` | `memory` (default), `postgres` | Database backend |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Connection details | Required when DB_BACKEND=postgres |
| `JWT_SECRET` | Secret string | **Change this in production!** |

### Notification Service

| Variable | Values | Description |
|----------|--------|-------------|
| `QUEUE_BACKEND` | `memory` (default), `sqs`, `pubsub`, `servicebus` | Queue to poll for events |
| `EMAIL_BACKEND` | `console` (default), `ses`, `sendgrid` | Email sending backend |
| `FROM_EMAIL` | Email address | Sender email for cloud backends |

## Assignment Tasks

Your group needs to:

1. **Containerise** — The Dockerfiles are provided as best-practice examples. Review and understand them.
2. **Push to registry** — Push all 5 images to your cloud provider's container registry.
3. **Implement cloud adapters** — Replace the in-memory stores with real cloud databases and queues.
4. **Deploy to Kubernetes** — Create Deployments, Services, Ingress, ConfigMaps, and Secrets.
5. **Secure** — Add NetworkPolicy, workload identity, WAF, and threat detection.
6. **Build CI/CD** — Automate test → build → scan → push → deploy.
7. **Monitor** — Set up dashboards, logging, and alerts.
8. **Optimise costs** — Tag resources, analyse spend, right-size instances.

### Pushing Images to ECR

If you are using PowerShell, make sure the image tag is defined before you call `docker tag`. A blank tag value produces the exact `repo:` error you saw.

```powershell
$repoUri = "175342148842.dkr.ecr.us-east-1.amazonaws.com/cloudmart/product-service"
$commitSha = git rev-parse --short HEAD

docker tag product-service:latest "$repoUri`:$commitSha"
docker push "$repoUri`:$commitSha"
```

If you do not want to use the Git commit as a tag, replace `$commitSha` with a literal value such as `latest` or `v1.0.0`.

See the full assignment brief for detailed requirements.

## Project Structure

```
cloudmart-starter/
├── docker-compose.yml          # Local development orchestration
├── README.md                   # This file
├── services/
│   ├── product-service/
│   │   ├── app.py              # Flask app with in-memory + cloud adapters
│   │   ├── requirements.txt
│   │   ├── Dockerfile          # Multi-stage, non-root, healthcheck
│   │   └── .dockerignore
│   ├── order-service/
│   │   ├── src/index.js        # Express app with queue adapters
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   ├── user-service/
│   │   ├── app.py              # Flask app with JWT + bcrypt
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   ├── notification-service/
│   │   ├── src/index.js        # Queue consumer + email sender
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   └── frontend/
│       ├── src/                # React SPA source
│       ├── public/
│       ├── nginx.conf          # Reverse proxy config
│       ├── package.json
│       ├── Dockerfile          # Multi-stage: npm build → nginx
│       └── .dockerignore
├── k8s/                        # Kubernetes manifest templates
│   ├── namespace.yaml
│   ├── product-service.yaml
│   ├── order-service.yaml
│   ├── user-service.yaml
│   ├── notification-service.yaml
│   ├── frontend.yaml
│   ├── configmap.yaml
│   └── network-policy.yaml
└── docs/adr/                   # Architecture Decision Records go here
```

## Cloud Provider

**Chosen provider:** _[Your group fills this in: AWS / GCP / Azure]_

## Team Members

| Name | Student ID | Responsibilities |
|------|-----------|-----------------|
| Gamage LPG | 214065V | User Service |
| Bhagya LGV | 214034C | Order Service |
| Warnasooriya ISB | 214220T | Notification Service |
| Welhena WIT | 214226R | Frontend |
| Rathnayake RMMN| 214172V | Product Service |

## AI Tool Disclosure


| Model/Tool | Usage | Review Process |
|------|-----------|-----------------|
| Claude Web | Brainstorming the approach and work breakdown | Groupwise review of concepts suggested and WBS items.
| Claude Code | Writing tests for services, develop infrastructure scripts and related development tasks | Code reviews through manual PR review process |

---

*IS 4630 Cloud Infrastructure Management | University of Moratuwa | Academic Year 2025/2026*

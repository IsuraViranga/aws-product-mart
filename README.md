# ProductMart on AWS

A five-service e-commerce platform, deployed to Amazon EKS entirely from code.
Browse a catalogue, place an order, get a confirmation email — split into
services that each own one job, so the interesting problems are the
distributed ones rather than the shopping cart.

Everything here is provisioned by Terraform and deployed by GitHub Actions.
Nothing was created by clicking in the AWS console.

> **A note on naming.** The project was renamed from *CloudMart* to
> *ProductMart*. AWS resources still carry the original `cloudmart-` prefix
> (cluster, ECR repositories, IAM roles, the Kubernetes namespace). Renaming
> them would mean destroying and recreating live infrastructure for no
> functional gain, so the prefix stays. Where this README shows a real
> resource name, it is the real one.

---

## Table of contents

- [What it does](#what-it-does)
- [Architecture](#architecture)
- [The services](#the-services)
- [Infrastructure](#infrastructure)
- [Security model](#security-model)
- [CI/CD pipeline](#cicd-pipeline)
- [Running locally](#running-locally)
- [Deploying to AWS](#deploying-to-aws)
- [What it costs](#what-it-costs)
- [Repository layout](#repository-layout)
- [Known gaps](#known-gaps)

---

## What it does

| Capability | Service that owns it |
|---|---|
| Browse, search and filter a product catalogue | `product-service` |
| Register, log in, hold a session | `user-service` |
| Place an order, check stock first | `order-service` |
| Send a confirmation email when an order is placed | `notification-service` |
| Serve the UI and route API calls | `frontend` |

Placing an order touches four services and a queue. That is the point: it
exercises service-to-service HTTP, asynchronous messaging, per-service
identity and independent scaling, in a domain everyone already understands.

---

## Architecture

```
  Developer                                              ┌──────────┐
      │ git push                            OIDC, no keys│   ECR    │
      ▼                                     ────────────▶│ 5 repos  │
┌──────────────┐   kubectl apply  ┌───────────────────┐  └────┬─────┘
│GitHub Actions│─────────────────▶│ EKS control plane │       │ image
└──────────────┘                  │   (AWS-managed)   │       │ pull
                                  └─────────┬─────────┘       │
                                            │ schedules pods  │
╔═══════════════════════════════════════════╪═════════════════╪═══════╗
║ VPC 10.0.0.0/16          2 AZs: ap-southeast-1a / 1b        │       ║
║                                            │                 │       ║
║  ┌─ public subnets ──────────┐             ▼                 │       ║
║  │  Application Load Balancer│   ┌─ private app subnets ─────┴────┐  ║
║  │  NAT Gateway (AZ-a only)  │   │  frontend  ×2   (no IAM role)  │  ║
║  └───────────┬───────────────┘   │  product   ×2 ──┐              │  ║
║              │ inbound            │  order    ×2 ──┼─▶ IRSA       │  ║
║              ▼                    │  user     ×2   │  (no IAM     │  ║
║         frontend pods             │  notification×1─┘   role)     │  ║
║                                   └────────────────────────────────┘  ║
║  ┌─ private data subnets ────────────────────────────────────────┐   ║
║  │  empty — reserved for RDS / ElastiCache, no route out         │   ║
║  └───────────────────────────────────────────────────────────────┘   ║
║                                                                       ║
║  Gateway VPC Endpoints (S3 + DynamoDB) ──── free path ───▶ DynamoDB  ║
╚═══════════════════════════════════════════════════════════════════════╝
      ▲                                                          │
      │ HTTPS                                    order ──▶ SQS ──┘
   End user                                      SQS  ──▶ notification
```

**Request path.** Browser → Internet Gateway → ALB → `frontend` pod. Nginx
inside the frontend proxies `/api/*` to the backend services by Kubernetes
Service name. Only the frontend is exposed; the other three are `ClusterIP`
and unreachable from outside the cluster.

**Two outbound paths, deliberately different.** DynamoDB traffic leaves through
a **gateway VPC endpoint** — free, and it never touches the public internet.
SQS traffic cannot: AWS offers gateway endpoints only for S3 and DynamoDB, so
it egresses through the NAT Gateway at $0.045/GB. An interface endpoint would
remove that charge for ~$7/month, which only pays for itself above ~155 GB.

---

## The services

| Service | Port | Stack | Replicas | AWS access |
|---|---|---|---|---|
| `frontend` | 80 | React + nginx | 2 | **none** |
| `product-service` | 8001 | Python / Flask | 2 | DynamoDB (one table) |
| `order-service` | 8002 | Node / Express | 2 | SQS — **send only** |
| `user-service` | 8003 | Python / Flask | 2 | **none** |
| `notification-service` | 8004 | Node | **1** | SQS — **receive + delete only** |

**Why `notification-service` runs a single replica.** Two consumers polling the
same SQS queue both receive messages, and standard queues guarantee
*at-least-once* delivery, not exactly-once — so two replicas means customers
can get duplicate emails. Scaling it safely requires idempotent handling, which
the service does not have. It also uses `strategy: Recreate` rather than a
rolling update, so there is never a moment with two consumers on the queue.

**Health probes.** Every service exposes both `/health` and `/ready`, and they
mean different things:

- **liveness → `/health`** — is the process alive? Failing this *restarts* the
  container, so it must not depend on a downstream service.
- **readiness → `/ready`** — can it actually serve? `product-service` queries
  DynamoDB here. Failing this removes the pod from its Service but does **not**
  restart it.

Getting these the wrong way round produces a restart loop whenever a
dependency blips.

---

## Infrastructure

Terraform is split into independent roots, each with its own state file in S3.
A mistake in one cannot damage another.

| Root | Contents | Lifecycle |
|---|---|---|
| `infra/bootstrap` | S3 state bucket, state locking | created once, never destroyed |
| `infra/core` | ECR ×5, DynamoDB table, SQS queue + DLQ, IAM, GitHub OIDC provider | permanent, ~$0 |
| `infra/network` | VPC, 6 subnets, IGW, NAT (behind a flag), gateway endpoints | permanent, $0 with NAT off |
| `infra/eks` | Cluster, node group, addons, IRSA roles, load balancer controller, CI access | **ephemeral** — created for a session, destroyed after |
| `infra/budget` | Monthly and daily spend alarms | created first, destroyed last |
| `infra/learn` | A throwaway S3 bucket used to learn the Terraform workflow | scratch, not part of the system |

`infra/modules/networking` and `infra/modules/eks` are reusable modules the
roots call.

**The two-tier split is the central cost decision.** Everything permanent costs
nothing. Everything that costs money lives in `infra/eks`, so a single
`terraform destroy` returns the account to roughly zero while leaving the VPC,
images and data intact.

**Cluster:** EKS 1.36 (pinned), 2× `t3.small` **spot** nodes in private
subnets, managed `vpc-cni` / `coredns` / `kube-proxy` addons.

---

## Security model

**No AWS credential is stored anywhere in this system.** Not in GitHub secrets,
not in a container, not on disk.

### GitHub Actions → AWS, via OIDC

GitHub presents a short-lived signed token; AWS verifies it against a trust
policy that pins the repository and branch, and returns temporary credentials.
There is no access key to leak or rotate.

The one line people forget:

```yaml
permissions:
  id-token: write   # without this the token is never minted
```

### Pods → AWS, via IRSA

Each pod runs as a Kubernetes ServiceAccount annotated with an IAM role ARN.
EKS injects a signed token; the AWS SDK trades it at STS for credentials valid
one hour.

```
pod runs as ServiceAccount "product-service"
  → kubelet mounts a signed JWT naming that ServiceAccount
    → SDK calls sts:AssumeRoleWithWebIdentity
      → STS verifies the signature against the cluster's OIDC provider
        → the role's trust policy checks the "sub" claim matches
          → temporary credentials
```

The condition that makes this safe:

```
"oidc.eks.ap-southeast-1.amazonaws.com/id/<id>:sub"
  = "system:serviceaccount:cloudmart:product-service"
```

Without it, *any* pod in the cluster could assume the role.

This replaces what `docker-compose.yml` does locally — it bind-mounts
`~/.aws` into three containers, handing each one full admin credentials.

### Least privilege, concretely

| Role | Permitted | Notably absent |
|---|---|---|
| `cloudmart-irsa-product-service` | DynamoDB item read/write on **one table** | `DeleteTable`, and any other table |
| `cloudmart-irsa-order-service` | `sqs:SendMessage` | `ReceiveMessage`, `DeleteMessage` |
| `cloudmart-irsa-notification-service` | `sqs:ReceiveMessage`, `DeleteMessage` | `SendMessage` |

The producer **cannot read the queue**; the consumer **cannot write to it**.
A bug in one cannot cause the other's failure mode.

`frontend` and `user-service` get a ServiceAccount with **no role annotation**
at all — a compromise there yields no AWS access of any kind.

### Cluster access

`authentication_mode = "API"` — access is granted with real AWS resources
(`aws_eks_access_entry`), visible in CloudTrail and revocable without
`kubectl`. The old `aws-auth` ConfigMap approach had no audit trail and one bad
edit could lock everyone out.

| Principal | Policy | Scope |
|---|---|---|
| `user/isura-admin` | ClusterAdmin | whole cluster |
| `role/cloudmart-github-actions` | **Edit** | **namespace `cloudmart` only** |

CI can deploy the application and nothing else. It cannot touch `kube-system`,
so a compromised workflow cannot replace CoreDNS or the load balancer
controller.

> **Two permission systems, both required.** An EKS access entry grants
> *Kubernetes* permissions. `aws eks update-kubeconfig` is an *AWS API* call
> needing `eks:DescribeCluster` in IAM. Missing the second produces an IAM
> error at the first `kubectl` step that reads as though the access entry is
> broken. Both are granted in `infra/eks/cicd-access.tf`.

---

## CI/CD pipeline

`.github/workflows/build-and-push.yml` — triggered by push to `main`, any pull
request, or manually.

### Job 1 — `build` (five in parallel, one per service)

```
checkout → run tests → authenticate via OIDC → docker build
         → push (main only) → wait for ECR scan → report CRITICAL/HIGH
```

- `fail-fast: false` so one broken service does not hide the other four.
- Images are tagged **by commit SHA** and `latest`. Deployments use the SHA, so
  you can look at any running pod and know exactly which commit built it.
- Pull requests build but never push — a PR must not publish an image someone
  could then deploy.
- `--provenance=false` on the build, because otherwise the tag points at an
  image index and ECR's scanner has nothing to scan.
- The scan currently **reports** rather than blocks. Set
  `FAIL_ON_CRITICAL: 'true'` to make it a gate.

### Job 2 — `deploy` (once, after all five pass)

```
authenticate → verify AWS access → verify Kubernetes access
             → pin manifests to this commit (kustomize)
             → kubectl apply -k
             → rollout status, 5 min timeout per service
             → roll back on failure
```

- `needs: build` waits for every matrix leg, so a broken service cannot be
  half-deployed alongside four working ones.
- `concurrency: deploy-eks` with `cancel-in-progress: false` queues overlapping
  runs — a half-finished rollout is worse than a slightly stale one.
- **`kubectl rollout status` is the step that matters.** Without it the job goes
  green the moment the API accepts the new spec, before a single pod has
  started. A crash-looping image would report a successful deploy.
- **`maxUnavailable: 0`** in every Deployment means a new pod must pass its
  readiness probe before an old one is removed. A failed deploy therefore
  leaves the previous version still serving, and `rollout undo` is instant.

---

## Running locally

**Prerequisites:** Docker Desktop, Git.

```bash
git clone <your-repo-url>
cd productmart
docker compose up --build
```

Open <http://localhost:3000>.

**Demo login:** `alice@cloudmart.example` / `password123`

By default every service runs against in-memory stores and needs no cloud
credentials. To point them at real AWS services, set the backend variables
below.

<details>
<summary><b>Backend configuration (adapter pattern)</b></summary>

**product-service**

| Variable | Values |
|---|---|
| `STORE_BACKEND` | `memory` (default), `dynamodb`, `firestore`, `cosmosdb` |
| `DYNAMODB_TABLE` | table name, required when `STORE_BACKEND=dynamodb` |

**order-service / notification-service**

| Variable | Values |
|---|---|
| `QUEUE_BACKEND` | `memory` (default), `sqs`, `pubsub`, `servicebus` |
| `SQS_QUEUE_URL` | queue URL, required when `QUEUE_BACKEND=sqs` |
| `EMAIL_BACKEND` | `console` (default), `ses`, `sendgrid` — notification only |

**user-service**

| Variable | Values |
|---|---|
| `DB_BACKEND` | `memory` (default), `postgres` |
| `JWT_SECRET` | signing key — **change in production** |

</details>

<details>
<summary><b>Smoke tests</b></summary>

```bash
curl http://localhost:8001/health          # product
curl http://localhost:8001/ready           # product, actually reaches the store
curl http://localhost:8001/products
curl "http://localhost:8001/products?search=headphone"

curl -X POST http://localhost:8003/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@cloudmart.example","password":"password123"}'

curl -X POST http://localhost:8002/orders \
  -H "Content-Type: application/json" \
  -d '{"userId":"user-001","items":[{"productId":"prod-001","quantity":1}]}'

curl http://localhost:8004/notifications
```

</details>

---

## Deploying to AWS

Full step-by-step in **[docs/RUNBOOK.md](docs/RUNBOOK.md)**, including the two
failure modes that bite on teardown. The short version:

```powershell
# 1. NAT on — nodes in private subnets cannot reach ECR without it (~2 min)
cd infra/network ; terraform apply -var enable_nat_gateway=true

# 2. Cluster, nodes, addons, IRSA, load balancer controller (~12 min)
cd ../eks ; terraform apply

# 3. Point kubectl at it
aws eks update-kubeconfig --region ap-southeast-1 --name cloudmart

# 4. The application (~2 min)
cd ../.. ; kubectl apply -k k8s/

# 5. The public URL — blank for 2-3 min while the ALB provisions
kubectl get ingress -n cloudmart
```

Or skip step 4 entirely: push to `main` and CI deploys.

**Teardown — order matters.** Deleting the cluster before the Ingress orphans
the ALB, which then bills ~$16/month with nothing visibly using it.

```powershell
kubectl delete -f k8s/30-ingress.yaml     # deletes the ALB — do this FIRST
cd infra/eks ; terraform destroy
cd ../network ; terraform apply -var enable_nat_gateway=false
```

Then verify with the API rather than trusting the exit code — a failed
`destroy` leaves a half-torn-down state, and the surviving half is usually the
part that bills:

```powershell
aws eks list-clusters --region ap-southeast-1
aws ec2 describe-nat-gateways --region ap-southeast-1 --filter "Name=state,Values=available" --query "length(NatGateways)"
aws elbv2 describe-load-balancers --region ap-southeast-1 --query "length(LoadBalancers)"
aws ec2 describe-addresses --region ap-southeast-1 --query "Addresses[].PublicIp"
```

---

## What it costs

| Component | Per hour | Note |
|---|---|---|
| EKS control plane | $0.100 | **fixed** — same whether you run 1 pod or 100 |
| NAT Gateway | $0.045 | **fixed** while enabled |
| 2× t3.small spot | $0.025 | on-demand would be $0.053 |
| 2× 20 GB gp3 | $0.005 | charged idle or busy |
| ALB | $0.023 | plus negligible LCU |
| **Total** | **≈ $0.20** | |

```
4-hour session     $0.80
Full day           $4.70
Left a month     $145.00
```

**The two fixed charges are 73% of the bill and do not shrink if you run fewer
pods.** Cutting from two nodes to one saves about a cent an hour. The only
lever that matters is how long the cluster exists — which is why everything
expensive sits in one destroyable Terraform root.

**Guardrails** (`infra/budget`, free):

- **$20/month** — alerts at 50%, 90% actual and 100% *forecasted*. The forecast
  alert is the useful one: it fires while there is still time to act.
- **$3/day** — a forgotten cluster burns ~$4.70/day, so this trips within about
  15 hours. You find out the next morning, not on payday.

Both exclude credits, so they track real usage rather than netting to zero
behind free-tier credit.

---

## Repository layout

```
.
├── .github/workflows/
│   └── build-and-push.yml       test → build → scan → push → deploy
├── docs/
│   └── RUNBOOK.md               bring-up and tear-down, with known failure modes
├── infra/
│   ├── bootstrap/               S3 state backend
│   ├── core/                    ECR, DynamoDB, SQS, IAM, GitHub OIDC
│   ├── network/                 VPC root
│   ├── eks/                     cluster, IRSA, LB controller, CI access
│   ├── budget/                  spend alarms
│   ├── learn/                   scratch — not part of the system
│   └── modules/
│       ├── networking/          reusable 3-tier VPC
│       └── eks/                 reusable cluster
├── k8s/
│   ├── kustomization.yaml       entry point — kubectl apply -k k8s/
│   ├── 00-namespace.yaml
│   ├── 10-product-service.yaml  ServiceAccount + Deployment + Service
│   ├── 11-order-service.yaml
│   ├── 12-user-service.yaml     + Secret for the JWT key
│   ├── 13-notification-service.yaml   no Service — nothing calls it
│   ├── 20-frontend.yaml
│   └── 30-ingress.yaml          creates the ALB
├── services/
│   ├── product-service/         Flask, DynamoDB adapter
│   ├── order-service/           Express, SQS producer
│   ├── user-service/            Flask, JWT + bcrypt
│   ├── notification-service/    Node, SQS consumer
│   └── frontend/                React + nginx (nginx.conf routes /api/*)
└── docker-compose.yml           local development
```

**File numbering in `k8s/` is load-bearing.** Nginx resolves its upstreams once
at startup and exits if a Service is missing, so the backends must be created
before the frontend. `kustomization.yaml` fixes the order, and also excludes
the two unused starter files (`namespace.yaml`, `configmap.yaml`) that
reference namespaces this deployment does not use.

---

## Known gaps

Listed rather than hidden — each is a deliberate stopping point, not an
oversight.

**No TLS.** The ALB serves plain HTTP. ACM will only issue a certificate for a
domain you control, and AWS will not certify its own `elb.amazonaws.com`
hostname. So a JWT login page is served unencrypted. The fix is a domain plus
ACM, roughly $12/year.

**No lockfiles for the Node services.** The Dockerfiles run `npm install`, which
re-resolves every semver range at build time. Two builds of the same commit can
produce different dependency trees — meaning **the image CI scanned is not
provably the image CI deployed**, which undercuts the scanning stage. Fix:
generate `package-lock.json`, commit it, switch to `npm ci`.

**`runAsNonRoot` is not set.** The Dockerfiles use `USER appuser` — a name, not
a numeric UID — and Kubernetes cannot verify a name is non-root, so the pod
would refuse to start. Containers do still run as `appuser`. Proper fix:
`USER 10001` in the Dockerfile.

**The JWT secret is a Kubernetes Secret, which is encoding, not encryption.**
`base64 -d` reverses it and the value is in this repository. A real deployment
would use AWS Secrets Manager via the Secrets Store CSI driver.

**Single NAT Gateway.** One gateway serves both AZs, halving the cost and
accepting that an AZ-a outage removes egress for both. Production would run one
per AZ. It also means AZ-b traffic crosses an AZ boundary at $0.01/GB.

**Empty data subnet tier.** Built for an RDS instance that does not exist yet.
Defensible as design-for-growth, but it is currently unused.

**No monitoring or alerting** beyond the control-plane logs shipped to
CloudWatch with 7-day retention. No dashboards, no application metrics.

---

## Team

| Name | Student ID | Responsibilities |
|---|---|---|
| | | |
| | | |
| | | |

## AI tool disclosure

_State which AI assistants were used, for which tasks, and what review process
was applied before merging their output._

---

*IS 4630 Cloud Infrastructure Management · University of Moratuwa · 2025/2026*

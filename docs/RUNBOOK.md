# CloudMart on EKS — bring up and tear down

Everything is in code. Nothing here needs editing between runs; this is the
order to run it in, which is the part the code cannot express.

Two tiers:

| Tier | What | Cost | Lifecycle |
|---|---|---|---|
| **Permanent** | VPC, subnets, endpoints, ECR, DynamoDB, SQS, IAM, budgets | $0 | never destroyed |
| **Ephemeral** | NAT, EKS, nodes, ALB | ~$0.20/hr | up for a session, then gone |

---

## Bring up (~20 min)

```powershell
$ROOT = "D:\My Own Projects\cloud_mart-main\cloud_mart-main"

# 1. NAT on. Nodes are in private subnets and cannot reach ECR or the EKS
#    API without it. ~2 min.
cd "$ROOT\infra\network"
terraform apply -var enable_nat_gateway=true

# 2. Cluster, node group, addons, IRSA roles, load balancer controller.
#    ~12 min - the control plane alone is ~9 of those.
cd "$ROOT\infra\eks"
terraform apply

# 3. Point kubectl at it.
aws eks update-kubeconfig --region ap-southeast-1 --name cloudmart
kubectl get nodes          # expect 2, Ready

# 4. The application. ~2 min for pods to become ready.
cd "$ROOT"
kubectl apply -k k8s/
kubectl get pods -n cloudmart -w

# 5. The public URL - blank for 2-3 min while the ALB provisions.
kubectl get ingress -n cloudmart
```

Alternatively, skip step 4 and push a commit to `main` — CI builds, scans and
deploys on its own.

### If step 2 fails at plan time

The Helm provider is configured from outputs of a cluster created in the same
root. Terraform usually defers this correctly, but on a completely cold apply
it can refuse with an unknown-provider-configuration error. If that happens,
build the cluster first and then everything else:

```powershell
terraform apply -target=module.eks
terraform apply
```

This is a known wrinkle with provider configs that depend on same-root
resources. The permanent fix is to split the Helm release into its own root.

---

## Tear down (~12 min)

**Order matters.** Deleting the cluster before the Ingress orphans the ALB,
which then bills ~$16/month with nothing to show it exists.

```powershell
$ROOT = "D:\My Own Projects\cloud_mart-main\cloud_mart-main"

# 1. Ingress FIRST. This is what deletes the ALB.
cd "$ROOT"
kubectl delete -f k8s/30-ingress.yaml

#    Confirm before continuing - must print 0.
aws elbv2 describe-load-balancers --region ap-southeast-1 --query "length(LoadBalancers)"

# 2. Cluster. ~8 min.
cd "$ROOT\infra\eks"
terraform destroy

# 3. NAT off. Separate root, easiest thing to forget, $1.08/day on its own.
cd "$ROOT\infra\network"
terraform apply -var enable_nat_gateway=false
```

### Step 3 usually needs running twice

The first run deletes the NAT gateway and then fails releasing the Elastic IP:

```
InvalidNetworkInterfaceID.NotFound: The networkInterface ID 'eni-...' does not exist
```

AWS reports the NAT gateway deleted before its network interface is actually
gone, so the release call references an ENI mid-deletion. Run the same command
again and it succeeds. An unreleased EIP costs ~$3.60/month, so this is worth
checking rather than assuming.

---

## Verify you are back to zero

A failed `terraform destroy` leaves a half-torn-down state, and the half that
survives is usually the half that bills. Check with the API, not the exit code:

```powershell
aws eks list-clusters --region ap-southeast-1
aws ec2 describe-nat-gateways --region ap-southeast-1 `
  --filter "Name=state,Values=available,pending" --query "length(NatGateways)"
aws elbv2 describe-load-balancers --region ap-southeast-1 --query "length(LoadBalancers)"
aws ec2 describe-addresses --region ap-southeast-1 --query "Addresses[].PublicIp"
```

All four must be empty or `0`.

---

## Things that change between rebuilds

| Changes | Stays the same |
|---|---|
| ALB DNS name — bookmarks break | IRSA role ARNs — names are stable, so the ServiceAccount annotations in `k8s/` keep working |
| OIDC provider ID — a new cluster means a new issuer | Everything in the permanent tier |
| Node IPs and pod names | The cluster name, `cloudmart` |

The OIDC change is handled automatically: the IRSA trust policies are built
from module outputs, so they regenerate with the new issuer on every apply.
That is why the ARNs in the manifests can be hardcoded and the trust policies
cannot.

---

## Costs

| | per hour |
|---|---|
| EKS control plane | $0.100 |
| 2× t3.small spot | $0.025 |
| 2× 20 GB gp3 | $0.005 |
| NAT gateway | $0.045 |
| ALB | $0.023 |
| **Total** | **~$0.20** |

A 4-hour session is under $1. Left running it is ~$4.70/day, and the daily
budget in `infra/budget` trips at $3 — roughly 15 hours in.

Note what dominates: the control plane and the NAT are **fixed** costs that do
not shrink if you run fewer pods. Cutting to one node saves about a cent an
hour. The only lever that matters is how long the cluster exists.

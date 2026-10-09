# Chapter 08: Production Deployment Patterns and Safety Rails

Deploying applications into production clusters introduces strict reproducibility, immutability, and safety requirements. In this chapter, we establish production patterns using Skaffold.

---

## 1. Core Principle: Build Once, Promote Immutably

A foundational rule of Kubernetes operations:
- **Never run `skaffold dev` against a production cluster.** Dev mode watches local disk files and synchronizes development artifacts that bypass code review, tagging gates, and CI verification.
- **Build once in CI and promote immutable artifacts.** Container images should be built from a verified Git commit, tested with structure tests, published to a registry, and referenced by an immutable content digest (`@sha256:...`).

---

## 2. Safety Rails in `skaffold.yaml`

To prevent accidental deployments to the wrong environment:

### 1. Pinning `deploy.kubeContext`
In `skaffold.yaml`:
```yaml
profiles:
  - name: prod
    deploy:
      kubeContext: prod-cluster
      statusCheck: true
      statusCheckDeadlineSeconds: 120
      kubectl: {}
```
If you accidentally run `skaffold deploy -p prod` while your local shell is pointed to a dev cluster (like `kind-skaffold-demo`), Skaffold halts with a profile/context mismatch error and refuses to execute.

### 2. Default Confirmation (`--assume-yes=false`)
By default, Skaffold commands that mutate a non-local Kubernetes cluster pause and prompt for confirmation before modifying cluster state unless `--assume-yes` is explicitly passed in non-interactive CI environments.

### 3. Explicit Namespaces
Always bind target namespaces declaratively in your Kustomize overlays or pass `--namespace=skaffold-demo` to prevent deploying into default or cluster-wide namespaces.

---

## 3. The Two Production Deployment Architectures

Skaffold supports two enterprise deployment patterns:

### Pattern A: Imperative CI/CD Deployment
In this model, the CI pipeline drives the deployment using Skaffold's artifact-passing mechanism:

1. **Build and emit artifact metadata**:
   ```bash
   skaffold build -p prod --default-repo=ghcr.io/org --file-output=artifacts.json
   ```
   Generates `artifacts.json` mapping each artifact to its published digest-pinned tag:
   ```json
   {"builds":[{"imageName":"skaffold-demo","tag":"ghcr.io/org/skaffold-demo:v1@sha256:abc..."}]}
   ```
2. **Deploy using artifact metadata**:
   ```bash
   skaffold deploy -p prod --build-artifacts=artifacts.json
   ```
   Skaffold reads the exact digests from `artifacts.json`, renders the production Kustomize overlay, applies manifests with `kubectl`, and validates the rollout with `statusCheck`.

### Pattern B: GitOps Deployment (Argo CD / Flux)
In this model, CI never connects directly to production clusters:

1. CI runs `skaffold build -p prod --default-repo=ghcr.io/org --file-output=artifacts.json`.
2. CI renders final Kubernetes manifests:
   ```bash
   skaffold render -p prod --build-artifacts=artifacts.json --output=rendered/prod.yaml
   ```
3. CI commits `rendered/prod.yaml` to a target GitOps manifests repository.
4. An in-cluster GitOps agent (such as Argo CD or Flux) synchronizes the cluster state from Git.

---

## 4. Production Hardening Checklist

| Security / Resilience Dimension | Implementation in `k8s/overlays/prod` |
| :--- | :--- |
| **High Availability** | `replicas: 2` in `deployment-patch.yaml` |
| **Voluntary Eviction Protection** | `PodDisruptionBudget` (`minAvailable: 1`) in `pdb.yaml` |
| **Zero-Downtime Updates** | `strategy: RollingUpdate` (`maxSurge: 1, maxUnavailable: 0`) |
| **Resource Quotas** | Guaranteed CPU/Memory `requests` and upper `limits` |
| **Least Privilege** | Non-root UID 65532, read-only rootfs, drop all capabilities |
| **Rollout Verification** | `deploy.statusCheck` with explicit timeout deadline |

---

## 5. Secret Management: Anti-Patterns and Best Practices

### Anti-Pattern: Committing Raw Secrets
Never commit unencrypted `kind: Secret` manifests or `.env` files to git repositories.

### Recommended Approaches:
1. **External Secrets Operator (ESO)**: Synchronizes secrets directly from AWS Secrets Manager, Google Secret Manager, HashiCorp Vault, or Azure Key Vault into standard Kubernetes `Secret` objects.
2. **Sealed Secrets**: Encrypts secret values using asymmetric cryptography; only the cluster controller holding the private key can decrypt them.
3. **Workload Identity**: Cloud IAM mechanisms (GKE Workload Identity, AWS IAM Roles for Service Accounts) allow pods to authenticate directly with cloud APIs without static API keys or credentials.

---

## 6. Disaster Recovery and Rollbacks

Because deployments are driven by immutable `artifacts.json` files:
- To roll back instantly to the prior release, re-execute:
  ```bash
  skaffold deploy -p prod --build-artifacts=artifacts-previous.json
  ```
- Because images are pinned by SHA256 digest, no rebuilding or image re-pulling is required, ensuring deterministic rollback times.

In Phase 9, we assemble the complete reference documentation and repository guide.

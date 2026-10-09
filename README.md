# Learn Skaffold: From Kind Local Dev to Production

A comprehensive, hands-on tutorial that walks through Kubernetes local development and production deployment using [Skaffold](https://skaffold.dev/).

---

## Tutorial Chapters

1. [Chapter 01: Environment and Mental Model](docs/01-environment-and-mental-model.md)
   Understand the Skaffold pipeline (build -> tag -> render -> deploy -> watch), tool ecosystem relationships, automatic Kind detection, and automated setup.
2. [Chapter 02: Demo Application and Dockerfile](docs/02-demo-app-and-dockerfile.md)
   Build an HTTP service in Go with graceful shutdown, server timeouts, and an optimized multi-stage Dockerfile leveraging BuildKit cache mounts and non-root distroless containers.
3. [Chapter 03: Kubernetes Manifests and Manual Baseline](docs/03-kubernetes-manifests.md)
   Author raw Kubernetes manifests (Namespace, Deployment, Service), establish the manual build-load-apply baseline, and learn why Skaffold uses plain artifact names.
4. [Chapter 04: First `skaffold.yaml` — Build and Run](docs/04-first-skaffold-yaml.md)
   Structure the pipeline configuration, learn tag resolution policies (`gitCommit`), inspect transformations with `skaffold render`, and deploy with `skaffold run`.
5. [Chapter 05: Inner Development Loop](docs/05-inner-dev-loop.md)
   Automate continuous local development with `skaffold dev`, declarative port-forwarding, rebuild-on-change caching dynamics, file sync trade-offs, and `skaffold debug`.
6. [Chapter 06: Testing and Verification in the Pipeline](docs/06-testing-and-verification.md)
   Enforce quality gates using Google's `container-structure-test`, configure `deploy.statusCheck` deadlines to catch failing probes, and run post-deploy verification probes.
7. [Chapter 07: Profiles, Kustomize, and Multi-Artifact Pipelines](docs/07-profiles-kustomize-multi-artifact.md)
   Eliminate YAML duplication using Kustomize `base` and `overlays/{dev,prod}`, configure context-activated Skaffold profiles, and utilize `--default-repo`.
8. [Chapter 08: Production Deployment Patterns and Safety Rails](docs/08-production-deployment.md)
   Production immutability principles, `deploy.kubeContext` safety guards, PodDisruptionBudgets, rolling update policies, GitHub Actions CI/CD workflows, and instant digest-based rollbacks.

---

## Pinned Tool Versions

| Tool | Pinned Version | Purpose |
| :--- | :--- | :--- |
| `kubectl` | `v1.36.1` | Kubernetes CLI client |
| `kind` | `v0.33.0` | Local Kubernetes cluster in Docker |
| `skaffold` | `v2.25.0` | Development workflow orchestrator |
| `container-structure-test` | `v1.22.1` | Container image metadata and filesystem testing |
| `go` | `1.22+` | Demo application runtime and compiler |
| `docker` | `24+` / `29+` | Container runtime engine with BuildKit support |

---

## Command Cheat Sheet

### Environment Setup
```bash
# Install all required tooling idempotently
./setup.sh

# Verify all prerequisites are installed and ready
./setup.sh check

# Provision the local Kind cluster (skaffold-demo)
./setup.sh cluster
```

### Core Skaffold Commands
```bash
# Continuous development with live watch and automatic port-forwarding
skaffold dev --port-forward=true

# One-shot build, test, deploy, and status verification
skaffold run

# Execute container structure tests
skaffold test --build-artifacts=artifacts.json

# Execute post-deployment in-cluster verifier
skaffold verify

# Inspect rendered Kubernetes YAML without deploying
skaffold render -p dev
skaffold render -p prod

# Delete all resources deployed by Skaffold
skaffold delete
```

---

## Troubleshooting Guide

### 1. `ImagePullBackOff` / Image Not Found in Kind
- **Cause**: Kubernetes cannot find the image tag on the node, or `imagePullPolicy: Always` forces a remote registry pull that fails.
- **Remedy**:
  - In manifests, set `imagePullPolicy: IfNotPresent`.
  - When deploying manually, execute `kind load docker-image <image>:<tag> --name skaffold-demo`.
  - With Skaffold, ensure your kubectl context starts with `kind-` so Skaffold activates local image side-loading automatically.

### 2. Port Forward Conflict (`bind: address already in use`)
- **Cause**: Port 8080 is already held by a previous process or container.
- **Remedy**: Identify and stop the process using `lsof -i :8080` or `netstat -tlpn | grep 8080`, or configure an alternative local port in `skaffold.yaml` (`localPort: 8081`).

### 3. Profile / Context Refusal Error
- **Message**: `profiles ["dev"] were activated by kube-context "...", but the effective kube-context is "..."`.
- **Cause**: The production profile pins `deploy.kubeContext`, and Skaffold detects that the active cluster does not match the target environment.
- **Remedy**: Switch to the target cluster context using `kubectl config use-context <context>`, or pass `--kube-context=<context>`.

### 4. Stale BuildKit Cache
- **Cause**: Docker BuildKit cache holds intermediate build artifacts that need refreshing.
- **Remedy**: Run `docker builder prune` or pass `--no-cache` to `skaffold build` / `skaffold run`.

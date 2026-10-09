# Chapter 01: Environment and Mental Model

## What is Skaffold?

Developing applications targeting Kubernetes often introduces significant friction:
1. Make a code change.
2. Build a container image (`docker build`).
3. Tag the image with a unique identifier or hash (`docker tag`).
4. Push the image to a container registry (`docker push`) or side-load it into a local cluster (`kind load`).
5. Update Kubernetes manifests with the new tag.
6. Apply manifests (`kubectl apply`).
7. Wait for pods to restart and reach readiness.
8. Port-forward or inspect logs.

Skaffold is a client-side command-line tool developed by Google that automates this entire loop. It monitors your source directory, triggers incremental builds when changes are detected, manages tagging and cluster deployment, and streams container logs back to your terminal.

```
Source Code Change -> Build -> Tag -> Render -> Deploy -> Watch / Stream Logs
```

### Where Skaffold Sits in the Ecosystem

Skaffold does not replace Docker, kubectl, Helm, or Kustomize. Instead, it serves as an orchestrator that drives them:

| Tool | Role | Relationship to Skaffold |
| :--- | :--- | :--- |
| **Docker / BuildKit** | Container runtime & image builder | Skaffold invokes Docker (or alternatives like Kaniko, Cloud Native Buildpacks) to build images. |
| **kubectl** | Kubernetes CLI tool | Skaffold drives `kubectl` to apply rendered manifests or check rollout statuses. |
| **Kustomize / Helm** | Manifest templating & configuration management | Skaffold renders manifests using Kustomize overlays or Helm charts before passing them to the cluster. |
| **Kind / Minikube** | Local development Kubernetes clusters | Skaffold detects local clusters and optimizes deployment by bypassing remote image registries. |

### Automatic Kind Detection and Local Image Loading

When targeting remote clusters, every image build must be pushed to a registry that the cluster nodes can access. This introduces network overhead and latency to the inner dev loop.

Skaffold has built-in cluster detection for local environments like **Kind** (Kubernetes in Docker), Minikube, Docker Desktop, and k3d:
- When Skaffold detects that the active `kubectl` context belongs to Kind (e.g. `kind-skaffold-demo`), it automatically disables pushing to remote registries.
- Instead, Skaffold side-loads built images directly into Kind node containers (equivalent to `kind load docker-image`).
- The cluster pulls the image locally without authenticating against or contacting an external registry.

---

## Toolchain & Setup

The demo repository provides `./setup.sh`, an idempotent automation script for Debian/Ubuntu (apt-based) environments.

### Pinned Versions

The tutorial pins specific tool versions to guarantee reproducible behavior:
- `kubectl`: v1.36.1
- `kind`: v0.33.0
- `skaffold`: v2.25.0
- `go`: 1.21+ (demo uses Go standard library)

### Docker Installation Decision

`setup.sh` defaults to installing `docker.io` from the standard Ubuntu/Debian repositories:
- **Rationale**: `docker.io` comes signed by canonical distribution keys and integrates cleanly without adding third-party apt repositories or external GPG keys.
- **Alternative**: The official upstream `docker-ce` repository provides faster access to newly released Docker features, but adds extra repository management complexity. For local Skaffold workflows, `docker.io` satisfies all container building and Kind runtime requirements.

### Using `setup.sh`

`setup.sh` supports four subcommands:

1. **Full setup**:
   ```bash
   ./setup.sh
   # or
   ./setup.sh all
   ```
   Installs prerequisite apt packages (`curl`, `ca-certificates`, `git`, `make`), Docker, Go, and downloads checksum-verified binaries for `kubectl`, `kind`, and `skaffold` to `/usr/local/bin`. Existing tools meeting version requirements are skipped.

2. **Verify prerequisites without modification**:
   ```bash
   ./setup.sh check
   ```
   Checks whether all required CLIs are installed and whether Docker is reachable. Returns exit code 0 on success, or non-zero if dependencies are missing.

3. **Provision Kind cluster**:
   ```bash
   ./setup.sh cluster
   ```
   Creates a Kind cluster named `skaffold-demo` using `kind-config.yaml` (skips creation if the cluster already exists) and switches the kubectl context to `kind-skaffold-demo`.

4. **Summarize installed versions**:
   ```bash
   ./setup.sh summary
   ```

---

## Sanity Checks

Verify the installation and local cluster connectivity:

### 1. Check Skaffold Version
```bash
skaffold version
```
Expected output:
```
v2.25.0
```

### 2. Check Skaffold Diagnostic Utility
`skaffold diagnose` parses and validates the Skaffold configuration in the current directory and prints the effective pipeline settings. Before creating `skaffold.yaml` in Phase 4, running it without arguments confirms the CLI binary is responsive:
```bash
skaffold diagnose --help
```

### 3. Check Cluster Nodes
```bash
kubectl get nodes
```
Expected output:
```
NAME                           STATUS   ROLES           AGE   VERSION
skaffold-demo-control-plane   Ready    control-plane   1m    v1.33.0
```

With the tooling and cluster ready, Phase 2 implements the demo Go HTTP service and container build.

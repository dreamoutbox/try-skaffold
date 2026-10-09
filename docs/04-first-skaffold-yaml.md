# Chapter 04: First `skaffold.yaml` — Build and Run

In this chapter, we automate the build-load-apply-clean cycle by defining our first `skaffold.yaml` pipeline and running it against Kind.

---

## 1. Initializing and Structuring `skaffold.yaml`

Skaffold can discover Dockerfiles and Kubernetes manifests in the repository:

```bash
skaffold init
```

The resulting `skaffold.yaml` is organized into distinct lifecycle stages:

```yaml
apiVersion: skaffold/v4beta14
kind: Config
metadata:
  name: skaffold-demo
build:
  local:
    useBuildkit: true
  artifacts:
    - image: skaffold-demo
      docker:
        dockerfile: Dockerfile
manifests:
  rawYaml:
    - k8s/namespace.yaml
    - k8s/deployment.yaml
    - k8s/service.yaml
deploy:
  kubectl: {}
```

### Schema Anatomy:
- `apiVersion`: Defines the schema contract (verified with `skaffold fix`).
- `metadata.name`: Project identifier used across multi-config setups.
- `build.local.useBuildkit`: Ensures the Docker CLI uses BuildKit so that modern cache mounts (`--mount=type=cache`) function seamlessly.
- `build.artifacts`: List of container images to build. The `image` property (`skaffold-demo`) is the symbolic name that Skaffold matches in Kubernetes manifests.
- `manifests.rawYaml`: Paths to Kubernetes manifest files applied during deployment.
- `deploy.kubectl`: Specifies the deployment tool (`kubectl`). Skaffold can also deploy using Helm or Kustomize.

---

## 2. Tagging Policies & Resolved Image Tags

By default, Skaffold employs the `gitCommit` tag policy:
- Tags are derived from the latest git commit SHA (with a `-dirty` suffix if uncommitted changes exist in the working tree).
- Other tag policies include `dateTime`, `envTemplate`, `sha256`, and `inputDigest`.

### Inspecting Manifest Transformation with `skaffold render`

`skaffold render` performs the build evaluation, determines tags, and outputs the exact YAML manifests that would be sent to the cluster:

```bash
skaffold render
```

Excerpt of the rendered output:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skaffold-demo
  namespace: skaffold-demo
spec:
  template:
    spec:
      containers:
        - name: skaffold-demo
          image: skaffold-demo:754e75d-dirty
```

Notice how `image: skaffold-demo` in `k8s/deployment.yaml` is rewritten to `image: skaffold-demo:754e75d-dirty` without modifying the source files on disk.

---

## 3. The Core Commands

Skaffold provides discrete lifecycle commands:

| Command | Action |
| :--- | :--- |
| `skaffold build` | Builds configured artifacts using the active tag policy without deploying. |
| `skaffold render` | Builds and transforms manifests to standard stdout for inspection or GitOps pipelines. |
| `skaffold run` | Executes a complete one-off cycle: builds artifacts, loads them into Kind, applies manifests, and waits for deployment stabilization. |
| `skaffold delete` | Deletes all resources managed by the current Skaffold configuration from the cluster. |
| `skaffold fix` | Upgrades deprecated `skaffold.yaml` schema versions to the latest supported version. |

---

## 4. End-to-End Verification

Deploy the application to Kind:
```bash
skaffold run
```
Output:
```
Build [skaffold-demo] succeeded
Tags used in deployment:
 - skaffold-demo -> skaffold-demo:5a0a7393afe...
Starting deploy...
Loading images into kind cluster nodes...
 - skaffold-demo:... -> Loaded in 676ms
 - namespace/skaffold-demo created
 - deployment.apps/skaffold-demo created
 - service/skaffold-demo created
Waiting for deployments to stabilize...
 - skaffold-demo:deployment/skaffold-demo is ready.
Deployments stabilized in 6.044 seconds
```

Verify pod health:
```bash
kubectl get pods -n skaffold-demo
```

Clean up all deployed Kubernetes resources:
```bash
skaffold delete
```

In Phase 5, we explore `skaffold dev` to establish an automated inner development loop with continuous file watching and port forwarding.

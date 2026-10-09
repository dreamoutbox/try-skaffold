# Chapter 07: Profiles, Kustomize, and Multi-Artifact Pipelines

In this chapter, we eliminate duplicate manifests by organizing our Kubernetes resources with Kustomize and configuring Skaffold profiles for dev and prod environments.

---

## 1. Kustomize Hierarchy

Rather than duplicating YAML manifests between environments, Kustomize splits configuration into a shared `base/` and environment-specific `overlays/`:

```
k8s/
├── base/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        ├── deployment-patch.yaml
        └── kustomization.yaml
```

### Dev Overlay (`k8s/overlays/dev/kustomization.yaml`)
Labels all resources with `environment: dev` and keeps single-replica lightweight resource limits:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

commonLabels:
  environment: dev
```

### Prod Overlay (`k8s/overlays/prod/kustomization.yaml`)
Applies `deployment-patch.yaml` to scale to 2 replicas, bumps resource requests and limits, and tags resources with `environment: prod`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

commonLabels:
  environment: prod

patches:
  - path: deployment-patch.yaml
```

---

## 2. Skaffold Profiles

Profiles allow you to adapt your pipeline behavior based on the deployment target:

```yaml
manifests:
  kustomize:
    paths:
      - k8s/overlays/dev

profiles:
  - name: dev
    activation:
      - kubeContext: kind-skaffold-demo
    manifests:
      kustomize:
        paths:
          - k8s/overlays/dev
  - name: prod
    manifests:
      kustomize:
        paths:
          - k8s/overlays/prod
    build:
      local:
        push: true
```

### Profile Activation Mechanisms:
1. **Context-based auto-activation**: The `dev` profile specifies `activation: [{kubeContext: kind-skaffold-demo}]`. When `kubectl` points to the Kind cluster, Skaffold activates this profile automatically without extra CLI flags.
2. **Explicit CLI activation**: Pass `-p <profile>` (or `--profile <profile>`). For instance:
   ```bash
   skaffold render -p prod
   ```
   This overrides default settings, renders the production overlay, and sets `push: true`.

---

## 3. Environment Variable Templating and `--default-repo`

In shared CI/CD pipelines, container registries vary per branch or developer account.

### Registry Prefixing with `--default-repo`
Rather than hardcoding registry URLs in `skaffold.yaml`, run:
```bash
skaffold build --default-repo=ghcr.io/my-org
```
Skaffold prefixes image artifacts automatically:
- Artifact: `skaffold-demo`
- Resulting tag: `ghcr.io/my-org/skaffold-demo:<tag>`

### Env-Var Templating
Skaffold supports Go template syntax in select configuration fields:
```yaml
build:
  artifacts:
    - image: '{{.IMAGE_REPO | default "skaffold-demo"}}'
```
When invoked as `IMAGE_REPO=myregistry.example.com/demo skaffold run`, the template evaluates to the provided environment variable.

---

## 4. Multi-Config and `requires:` (Architecture Overview)

For repositories containing multiple microservices, Skaffold supports multi-config files separated by `---` or across distinct directories:

```yaml
apiVersion: skaffold/v4beta14
kind: Config
metadata:
  name: frontend
build:
  artifacts:
    - image: frontend
requires:
  - configs: [backend]
---
apiVersion: skaffold/v4beta14
kind: Config
metadata:
  name: backend
build:
  artifacts:
    - image: backend
```

Using `requires:`, Skaffold calculates dependency graphs and builds shared prerequisites in topological order.

---

## 5. Verification: Dev vs. Prod

Render the dev overlay:
```bash
skaffold render -p dev
```
Shows `replicas: 1` and `labels: { environment: dev }`.

Render the prod overlay:
```bash
skaffold render -p prod
```
Shows `replicas: 2`, `cpu: 500m`, `memory: 128Mi`, and `labels: { environment: prod }`.

In Phase 8, we build out the full production deployment pipeline.

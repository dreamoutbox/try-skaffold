# Chapter 06: Testing and Verification in the Pipeline

In this chapter, we add automated quality gates to the Skaffold pipeline: structural image tests, cluster status checks, and post-deployment verification.

---

## 1. Container Structure Tests (`test:` section)

Container images should adhere to security standards and contract requirements before being deployed to any cluster. We use Google's `container-structure-test` framework.

### Test Definition (`test/structure-test.yaml`)
```yaml
schemaVersion: 2.0.0

metadataTest:
  exposedPorts: ["8080"]
  user: "nonroot:nonroot"
  entrypoint: ["/app/server"]
  workdir: "/app"

fileExistenceTests:
  - name: "Server binary exists"
    path: "/app/server"
    shouldExist: true
```

### Pipeline Integration (`skaffold.yaml`)
```yaml
test:
  - image: skaffold-demo
    structureTests:
      - test/structure-test.yaml
```

When building artifacts with `skaffold run` or `skaffold test`, Skaffold executes the structure tests against the freshly built image. If an unauthorized user or missing entrypoint is detected, deployment is halted immediately.

---

## 2. Deployment Status Checks (`deploy.statusCheck`)

By default, `kubectl apply` returns as soon as manifests are accepted by the Kubernetes API server, even if the resulting pods crash loop or fail probes.

We enable active status monitoring in `skaffold.yaml`:
```yaml
deploy:
  statusCheck: true
  statusCheckDeadlineSeconds: 60
  kubectl: {}
```

### Simulating a Deployment Failure
To see how Skaffold protects against bad rollouts:
1. Edit `k8s/deployment.yaml` and point the readiness probe to a nonexistent endpoint:
   ```yaml
   readinessProbe:
     httpGet:
       path: /broken-probe
       port: 8080
   ```
2. Run the deployment:
   ```bash
   skaffold run
   ```
3. Kubernetes reports `Readiness probe failed: HTTP probe failed with statuscode: 404`.
4. Skaffold monitors the rollout until the deadline and halts with an exit code:
   ```
   Waiting for deployments to stabilize...
    - skaffold-demo:deployment/skaffold-demo: Readiness probe failed: HTTP probe failed with statuscode: 404
    - skaffold-demo:deployment/skaffold-demo failed. Error: Readiness probe failed: HTTP probe failed with statuscode: 404.
   1/1 deployment(s) failed
   ```
5. Restoring `path: /healthz` allows subsequent rollouts to stabilize and succeed.

---

## 3. Post-Deployment Verification (`verify:` section)

Once pods stabilize, end-to-end synthetic verification tests can confirm network connectivity and application health from within the cluster:

```yaml
verify:
  - name: verify-service-health
    executionMode:
      kubernetesCluster:
        overrides: '{"metadata":{"namespace":"skaffold-demo"}}'
    container:
      name: curl-verifier
      image: curlimages/curl:8.6.0
      command: ["curl"]
      args:
        - "-f"
        - "--retry"
        - "5"
        - "--retry-connrefused"
        - "http://skaffold-demo.skaffold-demo.svc.cluster.local/healthz"
```

### Verification Execution
Run standalone:
```bash
skaffold verify
```
Output:
```
Loading images into kind cluster nodes...
[curl-verifier]   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
[curl-verifier] OK
```

In Phase 7, we introduce Kustomize and Skaffold profiles to manage multi-environment configurations (dev vs. prod).

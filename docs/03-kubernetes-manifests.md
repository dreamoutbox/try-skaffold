# Chapter 03: Kubernetes Manifests and Manual Deployment Baseline

In this chapter, we create standard Kubernetes manifests and execute the manual deployment workflow against our Kind cluster. This establishes the exact manual baseline that Skaffold replaces in Phase 4.

---

## 1. Manifest Design

The application manifests are located in `k8s/`:

### `k8s/namespace.yaml`
Isolates the demo application inside the `skaffold-demo` namespace:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: skaffold-demo
```

### `k8s/deployment.yaml`
Runs the application container with security controls and health checks:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skaffold-demo
  namespace: skaffold-demo
  labels:
    app: skaffold-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: skaffold-demo
  template:
    metadata:
      labels:
        app: skaffold-demo
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
      containers:
        - name: skaffold-demo
          image: skaffold-demo
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 64Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 3
            periodSeconds: 10
```

### `k8s/service.yaml`
Exposes the pods as an internal ClusterIP service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: skaffold-demo
  namespace: skaffold-demo
  labels:
    app: skaffold-demo
spec:
  type: ClusterIP
  selector:
    app: skaffold-demo
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

---

## 2. Why Image Names Are Plain Placeholders

Notice the image specification in `k8s/deployment.yaml`:
```yaml
image: skaffold-demo
```

### Anti-Pattern: Hardcoded Tags or Custom Placeholders
In traditional manual setups or CI scripting, developers often write templates with placeholder tokens like `image: REPO/APP:__TAG__` or `image: skaffold-demo:v1.2.3` and rely on `sed` or custom scripts to substitute values before applying.

### How Skaffold Matches and Rewrites Images
Skaffold uses an artifact-matching approach:
1. In `skaffold.yaml`, you declare build artifacts with an `image` name (e.g. `skaffold-demo`).
2. When Skaffold renders or deploys manifests, it inspects every container image in all manifests.
3. When it sees an image name that matches an artifact (`skaffold-demo`), it automatically replaces that reference with the uniquely tagged and digest-resolved image generated during the build step (e.g. `skaffold-demo:latest@sha256:abc...` or `skaffold-demo:v1.0.0-dirty`).
4. Plain image names keep raw manifests valid Kubernetes objects that can still be inspected or dry-run independently with `kubectl apply --dry-run=client`.

---

## 3. The Manual Workflow (The Baseline to Automate)

To deploy changes manually without Skaffold, every code edit requires the following sequence:

### Step 1: Build the image
```bash
docker build -t skaffold-demo:latest .
```

### Step 2: Load the image into Kind
Kind nodes run in isolated container environments and do not pull directly from the host Docker daemon's storage:
```bash
kind load docker-image skaffold-demo:latest --name skaffold-demo
```

### Step 3: Apply the manifests
```bash
kubectl apply -f k8s/
```

### Step 4: Wait for the rollout to complete
```bash
kubectl rollout status deployment/skaffold-demo -n skaffold-demo --timeout=60s
```

### Step 5: Port-forward to verify
```bash
kubectl port-forward -n skaffold-demo svc/skaffold-demo 8080:80
```
In another terminal:
```bash
curl http://localhost:8080/
curl http://localhost:8080/healthz
```

### Step 6: Teardown
```bash
kubectl delete -f k8s/
```

This multi-step ritual takes 30–60 seconds per iteration and requires manual tracking of image tags whenever caching issues occur. In Phase 4, we replace this entire multi-command workflow with a single `skaffold` command.

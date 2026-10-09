# Chapter 05: Inner Development Loop — Dev, Port-Forward, and File Sync

In this chapter, we transition from one-shot executions (`skaffold run`) to a continuous, automated inner development loop using `skaffold dev`.

---

## 1. Automated Port Forwarding

Manually running `kubectl port-forward` breaks whenever pods restart or roll over during redeployment. Skaffold manages port forwards declaratively in `skaffold.yaml`:

```yaml
portForward:
  - resourceType: service
    resourceName: skaffold-demo
    namespace: skaffold-demo
    port: 80
    localPort: 8080
```

When you start `skaffold dev --port-forward=true`:
- Skaffold automatically opens a local tunnel on port `8080` forwarding to port `80` of `service/skaffold-demo`.
- When pods are recreated during code updates, Skaffold reconnects the tunnel automatically without requiring manual restarts or changing the local listening port.

---

## 2. Rebuild-on-Change and BuildKit Caching

Running `skaffold dev` sets up file system watchers for files associated with each artifact:

```bash
skaffold dev --port-forward=true
```

Output:
```
Port forwarding service/skaffold-demo, remote port 80 -> http://127.0.0.1:8080
Listing files to watch...
 - skaffold-demo
Press Ctrl+C to exit
Watching for changes...
```

When you edit `main.go` and save:
1. Skaffold detects the file change immediately.
2. BuildKit executes the build. Because `go.mod` has not changed:
   - Layer `COPY go.mod go.sum* ./` and `RUN go mod download` are marked `CACHED`.
   - The Go compiler utilizes `--mount=type=cache,target=/root/.cache/go-build`, so compiling only your changed function takes milliseconds (~0.2–0.3s).
3. The new image is tagged and side-loaded into the Kind cluster in ~700ms.
4. Kubernetes performs a rolling update of `deployment/skaffold-demo`.
5. The port-forwarder switches to the new pod, serving the updated response immediately.

---

## 3. File Sync: Mechanics and Constraints

Skaffold supports direct file synchronization (`sync`), copying modified files into running containers via `tar` streaming:

```yaml
# Conceptual sync configuration:
build:
  artifacts:
    - image: skaffold-demo
      sync:
        manual:
          - src: 'static/**/*'
            dest: '/app/static'
```

### Why File Sync is Limited for Compiled Languages (Go, Rust, C++)
- In interpreted runtimes (Node.js, Python, Ruby), hot code reloading (e.g., nodemon, webpack HMR, uvicorn) can interpret modified source files instantly inside the running container.
- For compiled languages like Go running on minimal runtime images like distroless:
  1. The container image has no Go compiler, no shell, and no libc tools to build source code in-place.
  2. Modifying `.go` files on the host cannot execute in the container without a compiler.
- **Best Practice for Go**: Rely on fast multi-stage Dockerfile builds with BuildKit caching. Rebuilding and reloading an incremental Go binary takes under 2 seconds, which is as fast as file sync while maintaining immutable, production-identical container images.

---

## 4. Debugging with `skaffold debug`

Skaffold includes native debugging orchestration:
```bash
skaffold debug --port-forward=true
```

### What `skaffold debug` Injects:
1. **Runtime inspection**: Skaffold detects the Go runtime in the container.
2. **Debugger injection**: It can inject the Delve debugger (`dlv`) into the pod dynamically.
3. **Debug port-forward**: It exposes Delve's headless debugging port (by default `56268`) to localhost.
4. **IDE Integration**: You attach VS Code or GoLand directly to `localhost:56268` to set breakpoints, step through code, and inspect memory inside the Kubernetes pod.

---

## 5. Development Flags & Workflow Guidance

### Useful Flags for `skaffold dev`:
- `--cleanup=false`: Leaves all deployed Kubernetes resources and port-forwards running when you press `Ctrl+C` (useful when inspecting a state after shutting down the watcher).
- `--no-prune`: Disables image pruning between builds, speeding up subsequent runs at the expense of disk space.
- `--auto-build=false` / `--auto-deploy=false`: Disables automatic rebuilding on file changes; press Enter in the terminal to trigger builds on demand.

### `skaffold dev` vs. `skaffold run`:
- Use `skaffold dev` for the inner development loop: active coding, rapid iteration, and live log tailing.
- Use `skaffold run` for verification passes, integration testing, and CI smoke checks.

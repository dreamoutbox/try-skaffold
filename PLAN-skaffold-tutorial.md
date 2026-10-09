# PLAN: Learn Skaffold with a Demo Project (Kind → Production)

Format: tutorial series. Each phase produces a working, committed state of the demo repo and one tutorial chapter (`docs/NN-*.md`). Source files are created while executing a phase; this plan lists what and why, not contents.

Demo project: `skaffold-demo` — a tiny Go HTTP service (stdlib `net/http`) with `/` and `/healthz`, containerized, deployed to Kubernetes. Optional second service in Phase 7 to show multi-artifact builds. Go keeps the app trivial so the tutorial stays focused on Skaffold; its static binaries allow a minimal runtime image.

Prerequisites (installed by `./setup.sh` in Phase 1 where possible): Docker, Kind, kubectl, Skaffold v2, Go toolchain; plus a container registry account for the production phase (GHCR or equivalent). Target OS: Debian/Ubuntu (apt-based).

---

### Phase 1: Environment and mental model [STATUS: DONE]
- Goal: Tooling installed and the reader understands what Skaffold automates.
- Tasks:
  - [x] Chapter 01: explain the Skaffold pipeline (build → tag → render → deploy → watch) and where it sits relative to Docker, kubectl, Helm, Kustomize.
  - [x] Write `./setup.sh` wrapper at repo root, with these requirements:
    - Strict mode, runs as normal user, uses `sudo` only for apt and `/usr/local/bin` installs; refuses non-apt systems with a clear message.
    - Idempotent: skips any tool already installed at an acceptable version; safe to re-run.
    - Installs apt packages: `curl`, `ca-certificates`, `git`, `make` (and `golang` or a pinned Go tarball if the apt version is too old for the demo's `go.mod`).
    - Installs Docker via apt (`docker.io` or the official Docker apt repo, decision recorded in chapter) and adds the user to the `docker` group, with a note to re-login.
    - Installs `kubectl`, `kind`, and `skaffold` as pinned-version binaries downloaded to `/usr/local/bin`, with checksum verification (Kind and Skaffold are not in default apt repos).
    - Versions pinned in one variables block at the top (overridable by env vars), matching versions documented in the README.
    - Subcommands: `./setup.sh` (install all), `./setup.sh check` (verify only, no changes, non-zero exit if anything is missing), `./setup.sh cluster` (create Kind cluster from the config file; skip if it exists).
    - Prints a final summary of installed versions.
  - [x] Create Kind cluster with a named cluster config; confirm context `kind-<name>` with `kubectl cluster-info`.
  - [x] Document `skaffold diagnose` and `skaffold version` as sanity checks.
  - [x] Explain Skaffold's automatic Kind detection: local images are loaded into Kind, no registry or push needed.
- Done when: on a clean Ubuntu environment `./setup.sh` completes, a second run changes nothing, `./setup.sh check` exits 0, `kubectl get nodes` shows Ready, `skaffold version` prints v2.x; `shellcheck setup.sh` is clean; chapter 01 committed.

### Phase 2: Demo app and Dockerfile [STATUS: DONE]
- Goal: A service that runs standalone in Docker.
- Tasks:
  - [x] Scaffold Go module with `/` and `/healthz`, port from env var, graceful shutdown on SIGTERM via `http.Server.Shutdown`, sane server timeouts.
  - [x] Add a unit test for the handlers (`httptest`).
  - [x] Multi-stage Dockerfile: Go builder stage with module download layer cached separately and BuildKit cache mounts for the build cache, static binary (`CGO_ENABLED=0`), minimal non-root runtime image (distroless or scratch).
  - [x] Add `.dockerignore` (exclude `.git`, local binaries).
  - [x] Chapter 02: build and run with plain Docker; note the pain points Skaffold will remove (manual tag, load into Kind, apply, restart).
- Done when: `docker build` succeeds, container responds 200 on `/healthz`, `go test ./...`, `go vet ./...` pass.

### Phase 3: Kubernetes manifests [STATUS: TODO]
- Goal: Raw manifests that deploy manually to Kind.
- Tasks:
  - [ ] Namespace, Deployment (resource requests/limits, readiness and liveness probes on `/healthz`, securityContext), Service.
  - [ ] Keep image name in the manifest as a plain placeholder-free name that matches the Skaffold artifact name (explain how Skaffold substitutes tags).
  - [ ] Chapter 03: manual flow once (build, `kind load`, `kubectl apply`, port-forward) to establish the baseline being automated.
- Done when: manual deploy to Kind works and `kubectl port-forward` reaches the service; manifests pass `kubectl apply --dry-run=server`.

### Phase 4: First `skaffold.yaml` — build and run [STATUS: TODO]
- Goal: One command replaces the manual flow.
- Tasks:
  - [ ] Generate with `skaffold init`, then hand-edit; explain `apiVersion`, `build.artifacts`, `manifests.rawYaml`, `deploy.kubectl`.
  - [ ] Explain tag policy (`gitCommit` default) and `skaffold build`, `skaffold render`, `skaffold run`, `skaffold delete`.
  - [ ] Show `skaffold render` output to demonstrate resolved image tags.
  - [ ] Chapter 04.
- Done when: `skaffold run` deploys to Kind, pod becomes Ready, `skaffold delete` cleans everything; `skaffold fix` reports no migrations needed.

### Phase 5: Inner dev loop — `dev`, port-forward, file sync [STATUS: TODO]
- Goal: Edit code, see it running in the cluster automatically.
- Tasks:
  - [ ] `skaffold dev` with `portForward` config; show rebuild-on-change.
  - [ ] Explain build caching and why the separate module-download layer plus build cache mounts keep rebuilds fast; show cache hit/miss in logs.
  - [ ] Explain file sync (manual sync rules) and its limits for compiled languages; recommend rebuild for Go, sync for static assets/config only.
  - [ ] Add `skaffold debug` overview (debug ports, what it injects) as optional section.
  - [ ] Chapter 05, including `--cleanup=false`, `--no-prune`, and `skaffold dev` vs `skaffold run` guidance.
- Done when: changing the `/` response text and saving results in a new pod serving the new text without manual commands; Ctrl+C removes resources.

### Phase 6: Testing and verification in the pipeline [STATUS: TODO]
- Goal: Skaffold gates deploys on tests and health.
- Tasks:
  - [ ] Add `container-structure-test` config (non-root user, exposed port, binary present) via `test:` section.
  - [ ] Add `verify:` step: a small job/container that curls the service after deploy (`skaffold verify` / `skaffold run`).
  - [ ] Configure `deploy.statusCheck` and deadline; demonstrate failure by breaking the readiness probe.
  - [ ] Chapter 06.
- Done when: broken probe makes `skaffold run` fail with a clear status-check error; fixed version passes tests and verify.

### Phase 7: Profiles, config, and multi-artifact (Kustomize) [STATUS: TODO]
- Goal: Same project, multiple environments, no manifest duplication.
- Tasks:
  - [ ] Restructure manifests into Kustomize `base/` and `overlays/{dev,prod}/`; switch `skaffold.yaml` to `manifests.kustomize`.
  - [ ] Add profiles: `dev` (local build, Kind) and `prod` (registry push, prod overlay), explain profile activation by kube-context and `-p` flag.
  - [ ] Show env-var templating in `skaffold.yaml` (e.g. image repo) and `--default-repo`.
  - [ ] Optional: add a second small service as a second artifact to show `requires:`/multi-config and per-artifact dependencies.
  - [ ] Chapter 07.
- Done when: `skaffold render -p dev` and `skaffold render -p prod` produce different, correct output; dev loop on Kind still works unchanged.

### Phase 8: Production deployment [STATUS: TODO]
- Goal: Reproducible, safe deploy to a real Kubernetes cluster.
- Tasks:
  - [ ] Chapter 08 explains the principle: build once in CI, promote the same immutable image; never run `skaffold dev` against production.
  - [ ] Registry: create repo, pull credentials as an imagePullSecret or cloud-native identity; push via `--default-repo`.
  - [ ] Safety rails: pin `deploy.kubeContext` and `--kube-context` in the prod profile; add `--assume-yes=false` default behavior note; set `--namespace`.
  - [ ] Choose the deploy path and document both:
    - Imperative CI deploy: `skaffold build --file-output` then `skaffold deploy --build-artifacts` (digest-pinned images, tag by git SHA).
    - GitOps: `skaffold render` output committed to a manifests repo/branch, applied by Argo CD or Flux.
  - [ ] CI pipeline (GitHub Actions): lint/test → `skaffold build` → push → `skaffold deploy -p prod` on tag/main, with cluster credentials from CI secrets or OIDC.
  - [ ] Production hardening checklist: replicas ≥ 2, PodDisruptionBudget, resource limits, rollout strategy and `statusCheck`, rollback procedure (redeploy previous build artifacts file / revert git SHA).
  - [ ] Secrets: do not commit; use External Secrets, Sealed Secrets, or cloud secret manager reference.
  - [ ] Dry-run the production path against a second Kind cluster (or a cloud test cluster) before the real one.
- Done when: CI run on a tag builds, pushes, and deploys to the target cluster; pods run the digest-pinned image; rolling back to the previous artifact set succeeds; `skaffold deploy` against the wrong context is refused.

### Phase 9: Wrap-up and reference [STATUS: TODO]
- Goal: Tutorial is navigable and maintainable.
- Tasks:
  - [ ] README with chapter index, command cheat sheet, and troubleshooting (Kind image not found, `ImagePullBackOff`, stale cache, port-forward conflicts).
  - [ ] Pin tool versions in the README and CI.
  - [ ] Final pass: run every chapter's commands from a clean clone.
- Done when: clean-clone walkthrough passes end to end on a fresh Kind cluster.

---

## Unknowns, risks, assumptions
- Assumes Skaffold v2 schema (`skaffold/v4beta*` or current); verify exact apiVersion with `skaffold fix` at execution time.
- Demo app is Go (stdlib only); Skaffold chapters are language-agnostic except Dockerfile caching and file-sync advice.
- `setup.sh` targets apt-based Debian/Ubuntu only; Docker install route (distro package vs official repo) and Go install route (apt vs pinned tarball) to be decided during Phase 1.
- Production target and registry are unspecified; Phase 8 stays provider-neutral. Pick GHCR + one managed cluster (or a second Kind cluster) before starting Phase 8.
- Deploy path choice (imperative CI vs GitOps) is left open; both are documented, implement one end to end.
- File sync gives little benefit for compiled Go; included for completeness only.

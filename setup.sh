#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Pinned Tool Versions (override via environment variables)
# ==============================================================================
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.36.1}"
KUBECTL_SHA256_AMD64="${KUBECTL_SHA256_AMD64:-629d3f410e09bf49b64ae7079f7f0bda1191efed311f7d37fdbab0ad5b0ec2b7}"

KIND_VERSION="${KIND_VERSION:-v0.33.0}"
KIND_SHA256_AMD64="${KIND_SHA256_AMD64:-aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d}"

SKAFFOLD_VERSION="${SKAFFOLD_VERSION:-v2.25.0}"
SKAFFOLD_SHA256_AMD64="${SKAFFOLD_SHA256_AMD64:-42b9e2e3246c19b78fcc53dd60cc7ded1da8704293886b909a2a02b9bef34d20}"

MIN_GO_VERSION="${MIN_GO_VERSION:-1.21.0}"
GO_INSTALL_VERSION="${GO_INSTALL_VERSION:-1.22.6}"

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
CLUSTER_NAME="${CLUSTER_NAME:-skaffold-demo}"
KIND_CONFIG="${KIND_CONFIG:-kind-config.yaml}"

# ==============================================================================
# Helpers
# ==============================================================================
ensure_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: setup.sh supports apt-based Debian/Ubuntu systems only." >&2
    exit 1
  fi
}

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_arch() {
  local raw_arch
  raw_arch="$(uname -m)"
  case "${raw_arch}" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "Error: Unsupported architecture ${raw_arch}" >&2
      exit 1
      ;;
  esac
}

install_binary_file() {
  local name="$1"
  local target_path="$2"
  local url="$3"
  local expected_hash="$4"

  local tmp_file
  tmp_file="$(mktemp)"

  echo "Downloading ${name} from ${url}..."
  curl -fsSL -o "${tmp_file}" "${url}"

  if [ -n "${expected_hash}" ]; then
    local actual_hash
    actual_hash="$(sha256sum "${tmp_file}" | awk '{print $1}')"
    if [ "${actual_hash}" != "${expected_hash}" ]; then
      rm -f "${tmp_file}"
      echo "Error: Checksum verification failed for ${name}!" >&2
      echo "  Expected: ${expected_hash}" >&2
      echo "  Actual:   ${actual_hash}" >&2
      exit 1
    fi
  fi

  chmod 0755 "${tmp_file}"
  local dest_dir
  dest_dir="$(dirname "${target_path}")"
  if [ -w "${dest_dir}" ]; then
    mv "${tmp_file}" "${target_path}"
  else
    run_sudo mv "${tmp_file}" "${target_path}"
  fi
  echo "Successfully installed ${name} to ${target_path}"
}

# ==============================================================================
# Component Installers
# ==============================================================================
install_apt_packages() {
  ensure_apt
  local pkgs=()
  for pkg in curl ca-certificates git make; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
      pkgs+=("${pkg}")
    fi
  done

  if [ ${#pkgs[@]} -gt 0 ]; then
    echo "Installing prerequisite apt packages: ${pkgs[*]}..."
    run_sudo apt-get update
    run_sudo apt-get install -y "${pkgs[@]}"
  else
    echo "Base apt packages already installed (curl, ca-certificates, git, make)."
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker is already installed ($(docker --version))."
  else
    ensure_apt
    echo "Installing Docker via apt (docker.io)..."
    run_sudo apt-get update
    run_sudo apt-get install -y docker.io
  fi

  if ! id -nG 2>/dev/null | grep -qw "docker"; then
    echo "Adding current user to 'docker' group..."
    run_sudo usermod -aG docker "${USER}"
    echo "Notice: User added to 'docker' group. You may need to log out and log back in, or run 'newgrp docker'."
  fi
}

install_go() {
  if command -v go >/dev/null 2>&1; then
    echo "Go is already installed ($(go version))."
    return 0
  fi

  ensure_apt
  echo "Installing Go toolchain..."
  local arch
  arch="$(detect_arch)"
  local tarball="go${GO_INSTALL_VERSION}.linux-${arch}.tar.gz"
  local url="https://go.dev/dl/${tarball}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  curl -fsSL -o "${tmp_dir}/${tarball}" "${url}"
  run_sudo rm -rf /usr/local/go
  run_sudo tar -C /usr/local -xzf "${tmp_dir}/${tarball}"
  rm -rf "${tmp_dir}"
  echo "Installed Go to /usr/local/go. Ensure /usr/local/go/bin is in PATH."
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is already installed."
    return 0
  fi

  local arch
  arch="$(detect_arch)"
  local expected_hash=""
  if [ "${arch}" = "amd64" ]; then
    expected_hash="${KUBECTL_SHA256_AMD64}"
  fi

  local url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  install_binary_file "kubectl" "${BIN_DIR}/kubectl" "${url}" "${expected_hash}"
}

install_kind() {
  if command -v kind >/dev/null 2>&1; then
    echo "kind is already installed ($(kind version))."
    return 0
  fi

  local arch
  arch="$(detect_arch)"
  local expected_hash=""
  if [ "${arch}" = "amd64" ]; then
    expected_hash="${KIND_SHA256_AMD64}"
  fi

  local url="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${arch}"
  install_binary_file "kind" "${BIN_DIR}/kind" "${url}" "${expected_hash}"
}

install_skaffold() {
  if command -v skaffold >/dev/null 2>&1; then
    echo "skaffold is already installed ($(skaffold version))."
    return 0
  fi

  local arch
  arch="$(detect_arch)"
  local expected_hash=""
  if [ "${arch}" = "amd64" ]; then
    expected_hash="${SKAFFOLD_SHA256_AMD64}"
  fi

  local url="https://github.com/GoogleContainerTools/skaffold/releases/download/${SKAFFOLD_VERSION}/skaffold-linux-${arch}"
  install_binary_file "skaffold" "${BIN_DIR}/skaffold" "${url}" "${expected_hash}"
}

# ==============================================================================
# Subcommands
# ==============================================================================
cmd_all() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "Warning: Running setup.sh as root is discouraged. Sudo is used only when required." >&2
  fi

  install_apt_packages
  install_docker
  install_go
  install_kubectl
  install_kind
  install_skaffold
  cmd_summary
}

cmd_check() {
  local missing=0

  echo "Verifying prerequisites..."
  for tool in curl git make docker kubectl kind skaffold go; do
    if command -v "${tool}" >/dev/null 2>&1; then
      printf "  [OK] %-10s found: %s\n" "${tool}" "$(command -v "${tool}")"
    else
      printf "  [MISSING] %-10s NOT found in PATH\n" "${tool}"
      missing=$((missing + 1))
    fi
  done

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      echo "  [OK] Docker daemon is running and accessible."
    else
      echo "  [WARN] Docker daemon is not accessible by current user without sudo."
    fi
  fi

  if [ "${missing}" -ne 0 ]; then
    echo "Verification failed: ${missing} required tool(s) missing." >&2
    return 1
  fi

  echo "All required tools are installed and present in PATH."
  return 0
}

cmd_cluster() {
  if ! command -v kind >/dev/null 2>&1; then
    echo "Error: kind binary not found in PATH. Run './setup.sh' first." >&2
    exit 1
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "Error: kubectl binary not found in PATH. Run './setup.sh' first." >&2
    exit 1
  fi

  if [ ! -f "${KIND_CONFIG}" ]; then
    echo "Error: Kind config file '${KIND_CONFIG}' does not exist." >&2
    exit 1
  fi

  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    echo "Kind cluster '${CLUSTER_NAME}' already exists. Skipping creation."
  else
    echo "Creating Kind cluster '${CLUSTER_NAME}' using ${KIND_CONFIG}..."
    kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
  fi

  local target_context="kind-${CLUSTER_NAME}"
  echo "Switching kubectl context to '${target_context}'..."
  kubectl config use-context "${target_context}"
  kubectl cluster-info --context "${target_context}"
  echo "Kind cluster '${CLUSTER_NAME}' ready."
}

cmd_summary() {
  echo ""
  echo "=== Installed Toolchain Summary ==="
  if command -v docker >/dev/null 2>&1; then
    docker --version
  fi
  if command -v kubectl >/dev/null 2>&1; then
    kubectl version --client
  fi
  if command -v kind >/dev/null 2>&1; then
    kind --version
  fi
  if command -v skaffold >/dev/null 2>&1; then
    printf "Skaffold version: %s\n" "$(skaffold version)"
  fi
  if command -v go >/dev/null 2>&1; then
    go version
  fi
  echo "==================================="
}

# ==============================================================================
# Entrypoint
# ==============================================================================
subcmd="${1:-all}"
case "${subcmd}" in
  all|"")
    cmd_all
    ;;
  check)
    cmd_check
    ;;
  cluster)
    cmd_cluster
    ;;
  summary)
    cmd_summary
    ;;
  *)
    echo "Usage: $0 [all|check|cluster|summary]" >&2
    exit 1
    ;;
esac

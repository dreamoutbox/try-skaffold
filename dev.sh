#!/usr/bin/env bash
set -euo pipefail

# Ensure kind cluster exists
./setup.sh cluster

echo "===================="

# Run skaffold in dev mode with port forwarding
skaffold dev --port-forward=true

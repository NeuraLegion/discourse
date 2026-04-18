#!/bin/bash
set -euo pipefail

# Start Discourse dev environment using the project's Docker-aware wrapper.
# This ensures bundle/pnpm installs happen inside discourse_dev, where those tools exist.
exec ./bin/docker/boot_dev --init

#!/usr/bin/env bash
#
# Configure git-secrets pre-commit hooks and credential filters for this repository.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! command -v git-secrets >/dev/null 2>&1; then
  echo "Error: git-secrets is not installed."
  echo "Install via Homebrew: brew install git-secrets"
  exit 1
fi

echo "==> Configuring git hooks directory (.githooks)..."
git config core.hooksPath .githooks

echo "==> Registering AWS credential patterns..."
git secrets --register-aws

echo "==> Registering private key patterns..."
# Prevent accidental commit of private SSH / TLS / PGP keys
git config --replace-all secrets.patterns 'BEGIN.+PRIVATE.+KEY' 'BEGIN.+PRIVATE.+KEY' 2>/dev/null || \
git config --add secrets.patterns 'BEGIN.+PRIVATE.+KEY'

echo "==> Running security scan on repository..."
git secrets --scan

echo "==> git-secrets pre-commit hook is active and configured!"

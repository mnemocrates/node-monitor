#!/usr/bin/env bash
# Fix file permissions after deployment
set -euo pipefail

echo "Setting permissions to 700 for all .sh files..."
find . -name "*.sh" -exec chmod 700 {} \;

echo "Done! All .sh files now have 700 permissions."

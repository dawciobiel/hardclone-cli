#!/usr/bin/env bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <new_version>"
    exit 1
fi

VERSION="$1"

# Actualization of VERSION file
echo "$VERSION" > VERSION

# Commit and tagging
git add VERSION
git commit -m "Release $VERSION"
git tag "$VERSION"

# Push commit and tag
git push origin main
git push origin "$VERSION"

echo "✅ Version $VERSION pushed to repository!"


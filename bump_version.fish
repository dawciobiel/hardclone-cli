#!/usr/bin/fish

# Exit on first error
function fish_posterror --on-event fish_posterror
    echo "❌ Error occurred. Exiting."
    exit 1
end

# Sprawdzenie argumentu
if test (count $argv) -lt 1
    echo "Usage: (status filename) <new_version>"
    echo "Example version number: vMAJOR.MINOR.PATCH -> v5.1.3"
    exit 1
end

set VERSION $argv[1]

# Walidacja formatu wersji vMAJOR.MINOR.PATCH
if not string match -rq '^v[0-9]+\.[0-9]+\.[0-9]+$' -- $VERSION
    echo "❌ Invalid version format: $VERSION"
    echo "   Expected: vMAJOR.MINOR.PATCH (e.g. v5.1.3)"
    exit 1
end

# Aktualizacja pliku VERSION
echo $VERSION > VERSION

# Commit i tag
git add VERSION
git commit -m "Release $VERSION"
git tag $VERSION

# Push commit i tag
git push origin main
git push origin $VERSION

echo "✅ Version $VERSION pushed to repository!"

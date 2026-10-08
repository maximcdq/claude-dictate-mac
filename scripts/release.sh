#!/bin/bash
# Cuts a release from master: bumps VERSION and the mod's version, commits, tags, pushes and publishes the GitHub
# release; the release workflow then attaches ClaudeDictate.zip and installed apps update themselves.
#   scripts/release.sh 0.2.1 "notes"   (notes: what changed, for people)
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?version, e.g. 0.2.1}"
notes="${2:?release notes}"

[[ "$(git branch --show-current)" == master ]] || { echo "release from master"; exit 1; }
git pull --ff-only
[[ -z "$(git status --porcelain)" ]] || { echo "the working tree is not clean"; exit 1; }

echo "$version" > VERSION
sed -i '' -E "s/\"version\": \"[^\"]+\"/\"version\": \"$version\"/" mod/.claude-plugin/plugin.json
swift build -c release >/dev/null
git diff --quiet || git commit -am "$version"  # already bumped in the merged PR: nothing to commit
git tag "v$version"
git push origin master "v$version"
gh release create "v$version" --title "v$version" --notes "$notes"
echo "released v$version: watch the asset build with: gh run watch \$(gh run list -w release -L1 --json databaseId -q '.[0].databaseId')"

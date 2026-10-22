#!/bin/bash
set -euo pipefail
TAG=${1:?Usage: publish-release.sh YYMMDD-commit}
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
if [[ ! "$TAG" =~ ^[0-9]{6}-[0-9a-f]{7,40}$ ]] || [[ "$TAG" != "$(bash scripts/release-tag.sh)" ]] || [[ "$GITHUB_SHA" != "$(git rev-parse HEAD)" ]]; then
  echo 'Release tag and checked-out commit must match the workflow commit.' >&2
  exit 1
fi
ASSETS=('dist/Rich-Markdown-Diff-macos-arm64.app.zip' 'dist/rich-markdown-diff-source.zip' 'dist/SHA256SUMS')
for asset in "${ASSETS[@]}"; do test -s "$asset"; done
METADATA="$RUNNER_TEMP/rmd-release-$TAG.json"
NOTES="$RUNNER_TEMP/rmd-release-$TAG.md"
if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isDraft,targetCommitish,assets > "$METADATA"; then
  # Published releases may be immutable. Re-runs preserve their assets.
  STATE=$(node --input-type=commonjs - "$METADATA" "$GITHUB_SHA" <<'NODE'
const fs=require('node:fs');
const release=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
if(release.targetCommitish!==process.argv[3])throw Error('Existing release targets a different commit.');
if(!release.isDraft){
  const names=new Set(release.assets.map(asset=>asset.name));
  for(const name of ['Rich-Markdown-Diff-macos-arm64.app.zip','rich-markdown-diff-source.zip','SHA256SUMS'])
    if(!names.has(name))throw Error('Published release is missing asset: '+name);
}
console.log(release.isDraft?'draft':'published');
NODE
)
  if [[ "$STATE" == published ]]; then
    echo "Release $TAG is already published with all assets."
    exit 0
  fi
else
  cat > "$NOTES" <<NOTES
## Rich Markdown Diff — $TAG

- Commit: $GITHUB_SHA
- Download **Rich-Markdown-Diff-macos-arm64.app.zip**, extract it, and move the app to Applications.
- Requires Apple Silicon (M1 or later), macOS 14+, and a working /usr/bin/git.
- Node.js and Python are not needed to run the app.
- This build is ad-hoc signed; Developer ID signing and Apple notarization are not included.
- CI runs engine, Git integration and comment tests. GUI acceptance tests are not run on the hosted runner.

The source ZIP and SHA256SUMS are attached. Download all three files into one folder to verify with:

\`shasum -a 256 -c SHA256SUMS\`
NOTES
  # Upload while draft, then publish only after every asset succeeds.
  gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
    --title "$TAG" --notes-file "$NOTES" --draft
fi
gh release upload "$TAG" "${ASSETS[@]}" --repo "$GITHUB_REPOSITORY" --clobber
gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest

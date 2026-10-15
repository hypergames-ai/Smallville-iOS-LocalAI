#!/bin/bash
# Copies the Smallville map and sprite assets from YOUR clone of the Stanford repository
# into Assets/ThirdParty/ (gitignored). Nothing is downloaded and nothing is committed.
#
#   usage: scripts/fetch-assets.sh /path/to/generative_agents
#
# The assets are by PixyMoon, LimeZu and pipoya and are not covered by this project's
# license. See ATTRIBUTION.md before using them anywhere outside your own machine.

set -euo pipefail

src="${1:-}"
if [ -z "$src" ] || [ ! -d "$src" ]; then
  echo "usage: $0 /path/to/generative_agents (a local clone)" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Assets/ThirdParty"

# VERIFY: paths inside the Stanford repo. Known layout as of 2023:
#   environment/frontend_server/static_dirs/assets/the_ville/   (map json + tilesets under visuals/)
#   environment/frontend_server/static_dirs/assets/characters/  (sprite sheets)
assets="$src/environment/frontend_server/static_dirs/assets"
for sub in the_ville characters; do
  if [ ! -d "$assets/$sub" ]; then
    echo "expected $assets/$sub to exist; is this a clone of joonspk-research/generative_agents?" >&2
    exit 1
  fi
done

mkdir -p "$dest"
rsync -a --delete "$assets/the_ville/" "$dest/the_ville/"
rsync -a --delete "$assets/characters/" "$dest/characters/"

{
  echo "source: $src"
  echo "commit: $(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "license: see ATTRIBUTION.md; these files are NOT redistributable with this project"
} > "$dest/MANIFEST.txt"

echo "Copied assets into $dest (gitignored)."
echo "Reminder: support the artists — PixyMoon, LimeZu (limezu.itch.io), pipoya (pipoya.itch.io)."
if git -C "$root" status --porcelain 2>/dev/null | grep -q "Assets/"; then
  echo "WARNING: git sees files under Assets/. Check .gitignore before committing." >&2
fi

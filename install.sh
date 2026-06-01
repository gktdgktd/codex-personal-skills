#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="$repo_dir/skills"
target_root="${CODEX_HOME:-$HOME/.codex}/skills"

if [[ ! -d "$source_root" ]]; then
  echo "Missing skills directory: $source_root" >&2
  exit 1
fi

mkdir -p "$target_root"

for skill_dir in "$source_root"/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  mkdir -p "$target_root/$skill_name"
  cp -R "$skill_dir"/. "$target_root/$skill_name"
  echo "Installed skill: $skill_name"
done

echo "Done. Restart Codex to reload skills."

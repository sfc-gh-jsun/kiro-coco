#!/bin/bash
# Sync root skill files → powers/steering/ for Kiro power distribution.
# Run this after editing any root-level .md files.
#
# Usage: bash powers/sync-steering.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
STEERING_DIR="$SCRIPT_DIR/steering"

MD_HEADER="<!-- Synced from root skill. Do not edit directly. Run powers/sync-steering.sh -->"
YAML_HEADER="# Synced from root skill. Do not edit directly. Run powers/sync-steering.sh"

sync_file() {
  local src="$1"
  local dst="$2"
  if [ ! -f "$src" ]; then
    echo "SKIP (not found): $src"
    return
  fi
  case "$dst" in
    *.yaml|*.yml) echo "$YAML_HEADER" > "$dst" ;;
    *)            echo "$MD_HEADER" > "$dst" ;;
  esac
  echo "" >> "$dst"
  cat "$src" >> "$dst"
  echo "  OK: $(basename "$src") → $(basename "$dst")"
}

echo "Syncing root files → powers/steering/"
echo "---"

sync_file "$SKILL_DIR/connector-auth.md"            "$STEERING_DIR/connector-auth.md"
sync_file "$SKILL_DIR/openflow-setup.md"             "$STEERING_DIR/openflow-setup.md"
sync_file "$SKILL_DIR/kinesis-openflow/guide.md"     "$STEERING_DIR/kinesis-openflow.md"
sync_file "$SKILL_DIR/kinesis-openflow/params.yaml"  "$STEERING_DIR/kinesis-openflow-params.yaml"

# Sync reference files
for ref in "$SKILL_DIR/kinesis-openflow/references/"*.md; do
  [ -f "$ref" ] || continue
  basename=$(basename "$ref")
  sync_file "$ref" "$STEERING_DIR/kinesis-openflow-${basename}"
  done

echo "---"
echo "Done. Review changes with: git diff powers/steering/"

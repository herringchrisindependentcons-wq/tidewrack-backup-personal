#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Never touch a developer/player save. Linux headless test runner.
test_data=$(mktemp -d)
trap 'rm -rf "$test_data"' EXIT
export XDG_DATA_HOME="$test_data"
godot --headless --editor --path . --quit
godot --headless --path . tests/save_journal.tscn
godot --headless --path . tests/save_journal.tscn -- seed
godot --headless --path . tests/save_journal.tscn -- verify

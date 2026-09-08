#!/usr/bin/env bash
# Install the shared core into the Omarchy plugin and the integration bridges.
#
#   tools/sync-omarchy-plugin.sh            # install plugin files and bridges
#   tools/sync-omarchy-plugin.sh --check    # report drift, change nothing
#   tools/sync-omarchy-plugin.sh --plugin   # plugin files only
#   tools/sync-omarchy-plugin.sh --bridges  # bridge scripts only
#
# This repository is the source of truth. The Quickshell plugin directory is a
# deployment target, so edits made there are overwritten - run --check first if
# you are not sure which side is ahead.
#
# Override the destination with OMARCHY_CUSTOMIZATIONS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CUSTOMIZATIONS="${OMARCHY_CUSTOMIZATIONS:-$HOME/.config/omarchy-customizations}"
PLUGIN_DIR="$CUSTOMIZATIONS/files/omarchy/plugins/dukunuu.pomodoro"
BIN_DIR="$CUSTOMIZATIONS/files/local-bin"

CHECK_ONLY=0
DO_PLUGIN=1
DO_BRIDGES=1
for argument in "$@"; do
  case "$argument" in
    --check) CHECK_ONLY=1 ;;
    --plugin) DO_BRIDGES=0 ;;
    --bridges) DO_PLUGIN=0 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

# source:destination pairs. The destination is relative to its target directory.
PLUGIN_FILES=(
  "core/qml/Service.qml:Service.qml"
  "core/qml/Dashboard.qml:Dashboard.qml"
  "core/qml/IconSet.qml:IconSet.qml"
  "core/ui/TextArea.qml:TextArea.qml"
  "platform/quickshell/Platform.qml:Platform.qml"
  "platform/quickshell/BarWidget.qml:BarWidget.qml"
  "platform/quickshell/manifest.json:manifest.json"
  "assets/pomodoro.svg:assets/pomodoro.svg"
)

# The bridges are installed under the names the plugin calls on PATH. The two
# shared modules must sit beside them so the imports resolve.
BRIDGE_FILES=(
  "scripts/pomodoro_integrations.py:omarchy-pomodoro-integrations"
  "scripts/pomodoro_google_auth.py:omarchy-pomodoro-google-auth"
  "scripts/pomodoro_whistler_setup.py:omarchy-pomodoro-whistler-setup"
  "scripts/pomodoro_whistler_import.py:omarchy-pomodoro-whistler-import"
  "scripts/pomodoro_paths.py:pomodoro_paths.py"
  "scripts/pomodoro_notify.py:pomodoro_notify.py"
)

DRIFT=0
COPIED=0

install_file() {
  local source="$ROOT/$1" destination="$2" executable="$3"
  [[ -f "$source" ]] || { echo "missing source: $1" >&2; exit 1; }

  # The plugin invokes these by name with no interpreter, so a bridge without a
  # shebang would be handed to the shell and hang on its Python source.
  if [[ "$executable" == "yes" ]] && ! head -c2 "$source" | grep -q '#!'; then
    echo "$1 is installed as an executable but has no shebang" >&2
    exit 1
  fi

  if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then
    return 0
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    if [[ -f "$destination" ]]; then
      echo "  differs: $destination"
    else
      echo "  missing: $destination"
    fi
    DRIFT=1
    return 0
  fi

  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
  [[ "$executable" == "yes" ]] && chmod +x "$destination"
  echo "  wrote: $destination"
  COPIED=$((COPIED + 1))
}

if [[ "$DO_PLUGIN" == "1" ]]; then
  echo "==> plugin: $PLUGIN_DIR"
  for entry in "${PLUGIN_FILES[@]}"; do
    install_file "${entry%%:*}" "$PLUGIN_DIR/${entry##*:}" no
  done
fi

if [[ "$DO_BRIDGES" == "1" ]]; then
  echo "==> bridges: $BIN_DIR"
  for entry in "${BRIDGE_FILES[@]}"; do
    case "${entry##*:}" in
      *.py) install_file "${entry%%:*}" "$BIN_DIR/${entry##*:}" no ;;
      *)    install_file "${entry%%:*}" "$BIN_DIR/${entry##*:}" yes ;;
    esac
  done
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  if [[ "$DRIFT" == "1" ]]; then
    echo "Deployment differs from this repository. Run without --check to overwrite it," >&2
    echo "or copy the deployed changes back into the repository first." >&2
    exit 1
  fi
  echo "up to date"
  exit 0
fi

echo "$COPIED file(s) written."
if [[ "$COPIED" -gt 0 ]]; then
  echo "Restart the Omarchy shell to pick up the plugin change (omarchy-restart-shell)."
fi

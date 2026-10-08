#!/usr/bin/env sh
# Install oc-resume. Optionally shadow `opencode` so `opencode -r` works.
#
#   curl -fsSL <raw-url>/install.sh | sh            # standalone `oc-resume`
#   curl -fsSL <raw-url>/install.sh | sh -s -- --shadow   # also `opencode -r`
#
set -eu

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN_NAME=oc-resume
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SHADOW=0
[ "${1:-}" = "--shadow" ] && SHADOW=1

if ! command -v zsh >/dev/null 2>&1; then
  echo "error: oc-resume needs zsh (macOS ships it; Debian/Ubuntu: apt install zsh)" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "warning: 'sqlite3' not found on PATH -- install it or oc-resume cannot read sessions." >&2
  echo "         macOS ships it; Debian/Ubuntu: sudo apt install sqlite3" >&2
fi

mkdir -p "$INSTALL_DIR"
if cp "$SRC_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME.new" 2>/dev/null; then
  mv "$INSTALL_DIR/$BIN_NAME.new" "$INSTALL_DIR/$BIN_NAME"
else
  rm -f "$INSTALL_DIR/$BIN_NAME.new"
  cat "$SRC_DIR/$BIN_NAME" > "$INSTALL_DIR/$BIN_NAME"
fi
chmod +x "$INSTALL_DIR/$BIN_NAME"
echo "installed $INSTALL_DIR/$BIN_NAME"

# Make sure INSTALL_DIR is on PATH for future shells.
RC=""
for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
  [ -f "$f" ] && { RC="$f"; break; }
done
if [ -n "$RC" ]; then
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) : ;;
    *)
      if ! grep -q "$INSTALL_DIR" "$RC" 2>/dev/null; then
        printf '\n# oc-resume\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$RC"
        echo "added $INSTALL_DIR to PATH in $RC"
      fi
      ;;
  esac
else
  echo
  echo "No ~/.zshrc, ~/.bashrc or ~/.profile found, so PATH was not modified."
  echo "Add this to your shell's startup file:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

if [ "$SHADOW" -eq 1 ]; then
  echo
  echo "To make 'opencode -r' work, put a wrapper named 'opencode' earlier in PATH:"
  echo "  ln -s $INSTALL_DIR/$BIN_NAME $INSTALL_DIR/opencode"
  echo "then ensure $INSTALL_DIR comes before opencode's own bin dir, and run: exec \$SHELL"
fi

echo
echo "Done. Try:  $BIN_NAME        (standalone)"
[ "$SHADOW" -eq 1 ] && echo "        opencode -r     (wrapper)"
exit 0

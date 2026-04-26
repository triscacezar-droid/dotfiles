#!/usr/bin/env bash
# Switch the system-wide color theme across terminal, editor, desktop widget,
# folders, wallpaper, and GTK. Theme data lives in scripts/themes/<name>.sh.
#
# Usage:  set-theme.sh <theme>
# Run with no args to see the list of themes.
#
# Apps that stay hand-authored (not switched): zathura, yazi, lazygit, starship.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="${1:-}"

if [[ -z "$THEME" || "$THEME" == "-h" || "$THEME" == "--help" ]]; then
    echo "usage: $0 <theme>"
    echo "themes:"
    for t in "$DOTFILES/scripts/themes/"*.sh; do
        echo "  - $(basename "$t" .sh)"
    done
    exit 1
fi

THEME_FILE="$DOTFILES/scripts/themes/${THEME}.sh"
ALACRITTY_THEME_FILE="$DOTFILES/configs/alacritty/themes/${THEME}.toml"
[[ -f "$THEME_FILE"     ]] || { echo "error: no theme file '$THEME_FILE'"; exit 1; }
[[ -f "$ALACRITTY_THEME_FILE" ]] || { echo "error: no alacritty theme '$ALACRITTY_THEME_FILE'"; exit 1; }

# shellcheck disable=SC1090
source "$THEME_FILE"

echo "==> Switching to '$THEME'"

# ---- Alacritty -------------------------------------------------------------
ALACRITTY_CONFIG="$DOTFILES/configs/alacritty/alacritty.toml"
if [[ -f "$ALACRITTY_CONFIG" ]]; then
    echo "    alacritty:  themes/${THEME}.toml"
    sed -i -E "s|\"~/.config/alacritty/themes/[^\"]+\"|\"~/.config/alacritty/themes/${THEME}.toml\"|" \
        "$ALACRITTY_CONFIG"
fi

# ---- Kitty -----------------------------------------------------------------
if command -v kitten >/dev/null && [[ -n "${KITTY_NAME:-}" ]]; then
    echo "    kitty:      ${KITTY_NAME}"
    kitten themes --reload-in=all "${KITTY_NAME}" >/dev/null 2>&1 \
        || echo "                (kitty theme apply failed — non-fatal)"
fi

# ---- Cursor IDE ------------------------------------------------------------
# Rewrite settings.json in place (preserve inode) so Cursor's file watcher
# fires a MODIFY event — `sed -i` renames a temp file over the original,
# which Cursor's watcher could miss, leaving the theme un-applied.
# Auto-reload of a running Cursor window isn't possible from a script on
# Wayland (xdotool can't reach native-Wayland windows; ydotool needs root
# uinput setup). Print a reload hint when Cursor is running.
CURSOR_SETTINGS="$HOME/.config/Cursor/User/settings.json"
if [[ -f "$CURSOR_SETTINGS" && -n "${CURSOR_NAME:-}" ]]; then
    echo "    cursor:     ${CURSOR_NAME}"
    if grep -q '"workbench.colorTheme"' "$CURSOR_SETTINGS"; then
        tmp="$(mktemp)"
        sed -E "s|(\"workbench.colorTheme\":\s*)\"[^\"]*\"|\1\"${CURSOR_NAME}\"|" \
            "$CURSOR_SETTINGS" > "$tmp"
        cat "$tmp" > "$CURSOR_SETTINGS"     # truncate-and-write keeps the same inode
        rm -f "$tmp"
    fi
    if pgrep -x cursor >/dev/null 2>&1; then
        echo "    cursor:     (if not applied live: Ctrl+Shift+P → Reload Window)"
    fi
fi

# ---- GNOME color-scheme ----------------------------------------------------
if command -v gsettings >/dev/null && [[ -n "${GNOME_SCHEME:-}" ]]; then
    echo "    gnome:      color-scheme=${GNOME_SCHEME}"
    gsettings set org.gnome.desktop.interface color-scheme "${GNOME_SCHEME}"
fi

# ---- GTK theme (skip if not installed) -------------------------------------
if command -v gsettings >/dev/null && [[ -n "${GTK_THEME:-}" ]]; then
    if [[ -d "$HOME/.themes/${GTK_THEME}" ]] \
       || [[ -d "/usr/share/themes/${GTK_THEME}" ]]; then
        echo "    gtk:        ${GTK_THEME}"
        gsettings set org.gnome.desktop.interface gtk-theme "${GTK_THEME}"
    else
        echo "    gtk:        ${GTK_THEME}  [skipped — not installed in ~/.themes or /usr/share/themes]"
    fi
fi

# ---- Papirus folder color --------------------------------------------------
# papirus-folders edits /usr/share/icons → needs root. Use pkexec for a GUI
# password prompt; fall back to a plain message if pkexec isn't available.
if [[ -x "$HOME/.local/bin/papirus-folders" && -n "${PAPIRUS_COLOR:-}" ]]; then
    PAPIRUS_BASE="${PAPIRUS_BASE:-Papirus-Dark}"
    echo "    folders:    ${PAPIRUS_COLOR} on ${PAPIRUS_BASE}  (auth prompt)"
    if command -v pkexec >/dev/null; then
        pkexec "$HOME/.local/bin/papirus-folders" -C "$PAPIRUS_COLOR" -t "$PAPIRUS_BASE" >/dev/null \
            || echo "                (papirus-folders apply failed — re-run with sudo)"
    else
        sudo "$HOME/.local/bin/papirus-folders" -C "$PAPIRUS_COLOR" -t "$PAPIRUS_BASE" >/dev/null \
            || echo "                (papirus-folders apply failed)"
    fi
    # Also switch the active icon theme to match (Dark vs Light variant).
    gsettings set org.gnome.desktop.interface icon-theme "$PAPIRUS_BASE" 2>/dev/null || true
fi

# ---- Wallpaper -------------------------------------------------------------
if command -v python3 >/dev/null && python3 -c "from PIL import Image" 2>/dev/null; then
    WALL_DIR="$HOME/Pictures/Wallpapers"
    WALL_OUT="$WALL_DIR/theme_${THEME}.png"
    mkdir -p "$WALL_DIR"
    echo "    wallpaper:  #${WALL_TOP:-32302f} → #${WALL_BOTTOM:-1d2021}"
    python3 "$DOTFILES/scripts/gen-wallpaper.py" "$WALL_OUT" \
            --top "${WALL_TOP:-32302f}" --bottom "${WALL_BOTTOM:-1d2021}" >/dev/null
    gsettings set org.gnome.desktop.background  picture-uri      "file://$WALL_OUT"
    gsettings set org.gnome.desktop.background  picture-uri-dark "file://$WALL_OUT"
    gsettings set org.gnome.desktop.background  picture-options  "zoom"
    gsettings set org.gnome.desktop.screensaver picture-uri      "file://$WALL_OUT"
    gsettings set org.gnome.desktop.screensaver picture-options  "zoom"
fi

# ---- Conky palette ---------------------------------------------------------
# Rewrite the colour fields in configs/conky/conky.conf, then restart conky.
CONKY_CONF="$DOTFILES/configs/conky/conky.conf"
if [[ -f "$CONKY_CONF" ]]; then
    echo "    conky:      palette + panel"
    # Replace the top-of-file config values (KEY = 'HEX'). Leaves the
    # ${colorN} tokens in conky.text untouched — they reference the names.
    sub() {  # sub <key> <hex>
        sed -i -E "s|(^\s*${1}\s*=\s*')[0-9a-fA-F]{6}(')|\1${2}\2|" "$CONKY_CONF"
    }
    sub default_color          "${CONKY_FG:-ebdbb2}"
    sub default_outline_color  "${CONKY_BG:-1d2021}"
    sub default_shade_color    "${CONKY_BG:-1d2021}"
    sub own_window_colour      "${CONKY_BG:-1d2021}"
    sub color1                 "${CONKY_C1:-fe8019}"
    sub color2                 "${CONKY_C2:-b8bb26}"
    sub color3                 "${CONKY_C3:-fabd2f}"
    sub color4                 "${CONKY_C4:-fb4934}"
    sub color5                 "${CONKY_C5:-83a598}"
    sub color6                 "${CONKY_C6:-d3869b}"
    sub color7                 "${CONKY_C7:-8ec07c}"
    sub color8                 "${CONKY_MUTED:-665c54}"
    sub color9                 "${CONKY_FG_MUTED:-a89984}"

    if pgrep -x conky >/dev/null; then
        pkill -x conky
        sleep 0.3
        nohup conky -c "$HOME/.config/conky/conky.conf" >/dev/null 2>&1 & disown
    fi
fi

# ---- Zathura ---------------------------------------------------------------
# Rewrite the colour values in configs/zathura/zathurarc. Zathura reads its
# config at startup, so already-open instances need a restart to see the
# change. PDF recolor is on for dark themes, off for light.
ZATHURARC="$DOTFILES/configs/zathura/zathurarc"
if [[ -f "$ZATHURARC" ]]; then
    echo "    zathura:    palette (restart Zathura to apply)"
    zsub() {  # zsub <setting-key> <hex-without-#>
        sed -i -E "s|(^set $1[[:space:]]+)\"#[0-9a-fA-F]{6}\"|\1\"#$2\"|" "$ZATHURARC"
    }
    zsub default-bg                 "${CONKY_BG:-1d2021}"
    zsub default-fg                 "${CONKY_FG:-ebdbb2}"
    zsub recolor-lightcolor         "${CONKY_BG:-1d2021}"
    zsub recolor-darkcolor          "${CONKY_FG:-ebdbb2}"
    zsub statusbar-fg               "${CONKY_FG:-ebdbb2}"
    zsub statusbar-bg               "${CONKY_MUTED:-665c54}"
    zsub inputbar-fg                "${CONKY_FG:-ebdbb2}"
    zsub inputbar-bg                "${CONKY_BG:-1d2021}"
    zsub highlight-color            "${CONKY_C3:-fabd2f}"
    zsub highlight-fg               "${CONKY_BG:-1d2021}"
    zsub highlight-active-color     "${CONKY_C1:-fe8019}"
    zsub index-fg                   "${CONKY_FG:-ebdbb2}"
    zsub index-bg                   "${CONKY_BG:-1d2021}"
    zsub index-active-fg            "${CONKY_BG:-1d2021}"
    zsub index-active-bg            "${CONKY_C3:-fabd2f}"
    zsub render-loading-fg          "${CONKY_FG:-ebdbb2}"
    zsub render-loading-bg          "${CONKY_BG:-1d2021}"
    zsub completion-fg              "${CONKY_FG:-ebdbb2}"
    zsub completion-bg              "${CONKY_MUTED:-665c54}"
    zsub completion-group-fg        "${CONKY_C3:-fabd2f}"
    zsub completion-group-bg        "${CONKY_MUTED:-665c54}"
    zsub completion-highlight-fg    "${CONKY_BG:-1d2021}"
    zsub completion-highlight-bg    "${CONKY_C3:-fabd2f}"
    zsub notification-fg            "${CONKY_BG:-1d2021}"
    zsub notification-bg            "${CONKY_C2:-b8bb26}"
    zsub notification-error-fg      "${CONKY_BG:-1d2021}"
    zsub notification-error-bg      "${CONKY_C4:-fb4934}"
    zsub notification-warning-fg    "${CONKY_BG:-1d2021}"
    zsub notification-warning-bg    "${CONKY_C3:-fabd2f}"
    # Recolor PDFs only on dark themes — on light themes the page bg is
    # already light, so recoloring would invert it pointlessly.
    case "${GNOME_SCHEME:-prefer-dark}" in
        prefer-light) sed -i -E "s|(^set recolor[[:space:]]+)(true\|false)|\1false|" "$ZATHURARC" ;;
        *)            sed -i -E "s|(^set recolor[[:space:]]+)(true\|false)|\1true|"  "$ZATHURARC" ;;
    esac
fi

echo "==> Done. Open a fresh terminal window for Kitty/Alacritty to pick up the font color change."

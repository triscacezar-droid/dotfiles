#!/usr/bin/env bash
# Ubuntu 24.04 + GNOME 46 ricing installer.
# Idempotent — safe to re-run after partial failures.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS="$DOTFILES/configs"

cyan()  { printf "\033[1;36m==> %s\033[0m\n" "$*"; }
green() { printf "\033[1;32m    %s\033[0m\n" "$*"; }
yellow(){ printf "\033[1;33m    %s\033[0m\n" "$*"; }
red()   { printf "\033[1;31m!!  %s\033[0m\n" "$*" >&2; }

# ------------------------------------------------------------------ precheck
[[ "$(id -u)" -eq 0 ]] && { red "do not run as root; sudo will be invoked as needed"; exit 1; }
command -v apt-get >/dev/null || { red "apt-get not found — this installer targets Debian/Ubuntu"; exit 1; }

need_sudo() {
    if ! sudo -n true 2>/dev/null; then
        yellow "sudo password required for system packages..."
        sudo -v || { red "sudo auth failed"; exit 1; }
    fi
}

# ------------------------------------------------------------------ apt
cyan "Installing apt packages"
need_sudo
# fastfetch is not in 24.04 repos — grab the upstream deb later
# eza is not in 24.04 repos — grab the binary later
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    zsh pipx \
    kitty alacritty \
    zathura zathura-pdf-poppler \
    fzf ripgrep bat fd-find zoxide \
    conky-all \
    papirus-icon-theme \
    sassc \
    python3-nautilus wl-clipboard \
    curl git unzip xz-utils tar \
    gnome-shell-extension-manager

# ------------------------------------------------------------------ fastfetch
if ! command -v fastfetch >/dev/null; then
    cyan "Installing fastfetch (from upstream deb)"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/fastfetch.deb" \
        https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb
    sudo dpkg -i "$tmp/fastfetch.deb"
    rm -rf "$tmp"
else
    green "fastfetch already installed ($(fastfetch --version 2>/dev/null | head -1 || echo present))"
fi

# ------------------------------------------------------------------ user bins
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/fonts"

# --- JetBrainsMono Nerd Font ---
if ! fc-list | grep -q "JetBrainsMono Nerd"; then
    cyan "Installing JetBrainsMono Nerd Font"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/font.zip" \
        https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMono"
    unzip -o -q "$tmp/font.zip" -d "$HOME/.local/share/fonts/JetBrainsMono"
    fc-cache -f >/dev/null
    rm -rf "$tmp"
else
    green "JetBrainsMono Nerd Font already installed"
fi

# --- starship ---
if ! command -v starship >/dev/null && [[ ! -x "$HOME/.local/bin/starship" ]]; then
    cyan "Installing starship"
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
else
    green "starship already installed"
fi

# --- eza ---
if ! command -v eza >/dev/null && [[ ! -x "$HOME/.local/bin/eza" ]]; then
    cyan "Installing eza"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/eza.tar.gz" \
        https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz
    tar -xzf "$tmp/eza.tar.gz" -C "$tmp"
    mv "$tmp/eza" "$HOME/.local/bin/eza"
    chmod +x "$HOME/.local/bin/eza"
    rm -rf "$tmp"
else
    green "eza already installed"
fi

# --- yazi ---
if ! command -v yazi >/dev/null && [[ ! -x "$HOME/.local/bin/yazi" ]]; then
    cyan "Installing yazi"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/yazi.zip" \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip
    unzip -q -o "$tmp/yazi.zip" -d "$tmp"
    mv "$tmp"/yazi-*/yazi "$HOME/.local/bin/yazi"
    mv "$tmp"/yazi-*/ya   "$HOME/.local/bin/ya"
    chmod +x "$HOME/.local/bin/yazi" "$HOME/.local/bin/ya"
    rm -rf "$tmp"
else
    green "yazi already installed"
fi

# --- btop (upstream static musl build) ---
# Ubuntu 24.04 apt ships btop 1.3.0, which segfaults on Ryzen iGPU via its
# ROCm-SMI code path. Upstream 1.4.x ships a static build compiled with
# GPU_SUPPORT=false that avoids the broken code path entirely.
if ! command -v btop >/dev/null || ! btop --version 2>&1 | grep -qE "1\.4\.|1\.[5-9]\."; then
    cyan "Installing btop (upstream v1.4.x static build)"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/btop.tbz" \
        https://github.com/aristocratos/btop/releases/latest/download/btop-x86_64-unknown-linux-musl.tbz
    tar -xf "$tmp/btop.tbz" -C "$tmp"
    find "$tmp" -name 'btop' -executable -type f | head -1 \
        | xargs -I{} cp {} "$HOME/.local/bin/btop"
    chmod +x "$HOME/.local/bin/btop"
    rm -rf "$tmp"
else
    green "btop already at a good version"
fi

# --- lazygit ---
if ! command -v lazygit >/dev/null && [[ ! -x "$HOME/.local/bin/lazygit" ]]; then
    cyan "Installing lazygit"
    tmp=$(mktemp -d)
    LG_VERSION=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
                 | grep -Po '"tag_name": "v\K[^"]*')
    curl -fsSLo "$tmp/lg.tgz" \
        "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LG_VERSION}_Linux_x86_64.tar.gz"
    tar -xzf "$tmp/lg.tgz" -C "$tmp" lazygit
    mv "$tmp/lazygit" "$HOME/.local/bin/lazygit"
    chmod +x "$HOME/.local/bin/lazygit"
    rm -rf "$tmp"
else
    green "lazygit already installed"
fi

# --- atuin ---
if ! command -v atuin >/dev/null && [[ ! -x "$HOME/.atuin/bin/atuin" ]]; then
    cyan "Installing atuin"
    bash <(curl -fsSL https://setup.atuin.sh) </dev/null
else
    green "atuin already installed"
fi

# ------------------------------------------------------------------ oh-my-zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    cyan "Installing oh-my-zsh"
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
else
    green "oh-my-zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]]; then
        cyan "Installing zsh plugin: $plugin"
        git clone --depth=1 "https://github.com/zsh-users/$plugin.git" \
            "$ZSH_CUSTOM/plugins/$plugin"
    else
        green "$plugin already installed"
    fi
done

# ------------------------------------------------------------------ GTK theme
if [[ ! -d "$HOME/.themes/Gruvbox-Orange-Dark" ]]; then
    cyan "Installing Gruvbox-Orange-Dark GTK theme"
    tmp=$(mktemp -d)
    git clone --depth=1 https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git "$tmp/gtk"
    mkdir -p "$HOME/.themes"
    (cd "$tmp/gtk/themes" && bash install.sh -d "$HOME/.themes" -l -t orange -c dark)
    rm -rf "$tmp"
else
    green "GTK theme already installed"
fi

# ------------------------------------------------------------------ Bibata cursor
if [[ ! -d "$HOME/.icons/Bibata-Modern-Classic" ]]; then
    cyan "Installing Bibata-Modern-Classic cursor"
    tmp=$(mktemp -d)
    curl -fsSLo "$tmp/bibata.tar.xz" \
        https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Classic.tar.xz
    mkdir -p "$HOME/.icons"
    tar -xf "$tmp/bibata.tar.xz" -C "$HOME/.icons/"
    rm -rf "$tmp"
else
    green "Bibata cursor already installed"
fi

# ------------------------------------------------------------------ wallpapers
WALL_DIR="$HOME/Pictures/Wallpapers"
if [[ ! -d "$WALL_DIR" ]] || [[ -z "$(ls -A "$WALL_DIR" 2>/dev/null)" ]]; then
    cyan "Downloading gruvbox wallpaper pack"
    mkdir -p "$WALL_DIR"
    for dir in minimalistic scenery pixelart renders photography; do
        urls=$(curl -fsSL "https://api.github.com/repos/AngelJumbo/gruvbox-wallpapers/contents/wallpapers/$dir" 2>/dev/null \
               | grep '"download_url"' | head -3 | sed 's/.*"download_url": "//; s/",$//') || true
        for url in $urls; do
            name="${dir}_$(basename "$url")"
            [[ -f "$WALL_DIR/$name" ]] || curl -fsSLo "$WALL_DIR/$name" "$url" || true
        done
    done
else
    green "Wallpapers already present ($(ls "$WALL_DIR" | wc -l) files)"
fi

# Subtle gruvbox-dark gradient wallpaper that matches conky's panel.
MINIMAL_WP="$WALL_DIR/gruvbox_dark_minimal.png"
if [[ ! -f "$MINIMAL_WP" ]]; then
    cyan "Generating gruvbox-dark minimal wallpaper"
    if python3 -c "from PIL import Image" 2>/dev/null; then
        python3 "$DOTFILES/scripts/gen-wallpaper.py" "$MINIMAL_WP" >/dev/null \
            || yellow "wallpaper generation failed (non-fatal)"
    else
        yellow "python3-pil not installed — skipping wallpaper generation"
    fi
fi

# ------------------------------------------------------------------ symlink configs
cyan "Linking config files (edits in ~/dotfiles/configs/ propagate)"
mkdir -p "$HOME/.config" "$HOME/.local/share/nautilus-python/extensions"

link() {  # link <src-in-configs> <dst-in-home>
    local src="$CONFIGS/$1" dst="$HOME/$2"
    mkdir -p "$(dirname "$dst")"
    # Back up a pre-existing real file (don't overwrite without leaving a trail).
    if [[ -e "$dst" && ! -L "$dst" ]]; then
        mv "$dst" "$dst.pre-dotfiles-$(date +%s)"
        yellow "backed up existing $dst"
    fi
    ln -sfn "$src" "$dst"
}

link conky/conky.conf                 .config/conky/conky.conf
link kitty/kitty.conf                 .config/kitty/kitty.conf
link alacritty/alacritty.toml         .config/alacritty/alacritty.toml
mkdir -p "$HOME/.config/alacritty/themes"
for t in "$CONFIGS/alacritty/themes/"*.toml; do
    ln -sfn "$t" "$HOME/.config/alacritty/themes/$(basename "$t")"
done
link starship/starship.toml           .config/starship.toml
link zathura/zathurarc                .config/zathura/zathurarc
link yazi/theme.toml                  .config/yazi/theme.toml
link lazygit/config.yml               .config/lazygit/config.yml
link nautilus-python/copy_path.py     .local/share/nautilus-python/extensions/copy_path.py
link zshrc                            .zshrc

# ------------------------------------------------------------------ Conky widget
cyan "Installing conky weather fetcher and autostart"
ln -sfn "$CONFIGS/conky/weather.sh" "$HOME/.local/bin/conky-weather"
chmod +x "$CONFIGS/conky/weather.sh"
mkdir -p "$HOME/.config/autostart"
ln -sfn "$CONFIGS/conky/conky.desktop" "$HOME/.config/autostart/conky.desktop"

# ------------------------------------------------------------------ Kitty surface shortcut
cyan "Installing kitty-surface helper"
ln -sfn "$DOTFILES/scripts/kitty-surface.sh" "$HOME/.local/bin/kitty-surface"
chmod +x "$DOTFILES/scripts/kitty-surface.sh"

# ------------------------------------------------------------------ papirus-folders (orange)
# Recolor Papirus-Dark folder icons to gruvbox orange.
if [[ ! -x "$HOME/.local/bin/papirus-folders" ]]; then
    cyan "Installing papirus-folders"
    curl -fsSL https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders \
        -o "$HOME/.local/bin/papirus-folders"
    chmod +x "$HOME/.local/bin/papirus-folders"
else
    green "papirus-folders already installed"
fi
# papirus-folders modifies /usr/share/icons — needs root.
if [[ -r /usr/share/icons/Papirus-Dark/index.theme ]]; then
    cyan "Recoloring Papirus-Dark folders to orange (needs sudo)"
    sudo "$HOME/.local/bin/papirus-folders" -C orange -t Papirus-Dark >/dev/null \
        || yellow "papirus-folders run failed — re-run ~/.local/bin/papirus-folders -C orange -t Papirus-Dark"
fi

# ------------------------------------------------------------------ Kitty theme
# The theme kitten writes current-theme.conf & edits kitty.conf's BEGIN/END
# block; our kitty.conf already has a placeholder include for it.
if [[ ! -f "$HOME/.config/kitty/current-theme.conf" ]]; then
    cyan "Installing Kitty Gruvbox Dark theme"
    kitten themes --reload-in=none "Gruvbox Dark" || yellow "kitty theme install failed (non-fatal)"
fi

# ------------------------------------------------------------------ GNOME extensions
if command -v gnome-shell >/dev/null; then
    cyan "Installing GNOME extensions"
    if ! command -v gext >/dev/null; then
        pipx install gnome-extensions-cli --system-site-packages >/dev/null || \
            yellow "pipx gnome-extensions-cli install failed (non-fatal)"
    fi
    export PATH="$HOME/.local/bin:$PATH"
    if command -v gext >/dev/null; then
        gext install \
            Vitals@CoreCoding.com \
            blur-my-shell@aunetx \
            clipboard-indicator@tudmotu.com \
            caffeine@patapon.info 2>/dev/null || true
        gext enable \
            Vitals@CoreCoding.com \
            blur-my-shell@aunetx \
            clipboard-indicator@tudmotu.com \
            caffeine@patapon.info 2>/dev/null || true
        yellow "GNOME extensions activate after logout/login on Wayland"
    fi

    # ------------------------------------------------------------ gsettings
    cyan "Applying theme & cursor settings"
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
    gsettings set org.gnome.desktop.interface gtk-theme  "Gruvbox-Orange-Dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic"

    # Prefer the gruvbox gradient wallpaper (complements the conky panel).
    # Fall back to the first wallpaper we find. Only overwrite if the user
    # hasn't already set something from ~/Pictures/Wallpapers.
    if current=$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null); then
        if [[ "$current" != *"Pictures/Wallpapers"* ]]; then
            wall="$WALL_DIR/gruvbox_dark_minimal.png"
            [[ -f "$wall" ]] || wall=$(find "$WALL_DIR" -maxdepth 1 -type f 2>/dev/null | sort | head -1)
            if [[ -n "$wall" ]]; then
                gsettings set org.gnome.desktop.background picture-uri      "file://$wall"
                gsettings set org.gnome.desktop.background picture-uri-dark "file://$wall"
                gsettings set org.gnome.desktop.background picture-options  "zoom"
            fi
        fi
    fi

    # ------------------------------------------------------------ tiling-assistant
    # "Nice Maximize" — Super+Shift+M fills the screen but leaves 20px gaps
    # on all sides, showing the wallpaper and conky through. Uses the
    # tiling-assistant extension that ships with Ubuntu GNOME.
    cyan "Configuring tiling-assistant gaps + Super+Shift+M maximize"
    TA=org.gnome.shell.extensions.tiling-assistant
    gsettings set $TA maximize-with-gap true   2>/dev/null || true
    gsettings set $TA single-screen-gap 20     2>/dev/null || true
    gsettings set $TA window-gap        16     2>/dev/null || true
    gsettings set $TA screen-top-gap    20     2>/dev/null || true
    gsettings set $TA screen-bottom-gap 20     2>/dev/null || true
    gsettings set $TA screen-left-gap   20     2>/dev/null || true
    gsettings set $TA screen-right-gap  20     2>/dev/null || true
    gsettings set $TA tile-maximize "['<Super><Shift>m']" 2>/dev/null || true

    # ------------------------------------------------------------ custom keybindings
    # Super+K surfaces / cycles kitty windows via its remote-control socket.
    cyan "Binding Super+K to kitty-surface"
    KB_BASE=org.gnome.settings-daemon.plugins.media-keys
    KB_PATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kitty-surface/
    KB_SCHEMA=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
    current=$(gsettings get $KB_BASE custom-keybindings 2>/dev/null || echo "@as []")
    case "$current" in
        *"$KB_PATH"*)   ;;
        "@as []"|"[]")  gsettings set $KB_BASE custom-keybindings "['$KB_PATH']" ;;
        *)              gsettings set $KB_BASE custom-keybindings "${current%]*}, '$KB_PATH']" ;;
    esac
    gsettings set $KB_SCHEMA:$KB_PATH name    'Surface Kitty'
    gsettings set $KB_SCHEMA:$KB_PATH command "$HOME/.local/bin/kitty-surface"
    gsettings set $KB_SCHEMA:$KB_PATH binding '<Super>k'
fi

# ------------------------------------------------------------------ Cursor IDE
if command -v cursor >/dev/null; then
    cyan "Configuring Cursor IDE"
    cursor --install-extension jdinhlife.gruvbox 2>/dev/null || true
    # Don't auto-overwrite settings.json — the user may have personal settings.
    yellow "To switch Cursor to Gruvbox Dark Medium: Ctrl+K Ctrl+T → pick it"
fi

# ------------------------------------------------------------------ PDF handler
if command -v xdg-mime >/dev/null; then
    xdg-mime default org.pwmt.zathura.desktop application/pdf 2>/dev/null || true
fi

# ------------------------------------------------------------------ wrap up
cat <<'EOF'

-----------------------------------------------------------------------------
Install complete. Remaining manual steps:

 1. chsh -s $(which zsh)     # change default shell (asks your user password)
 2. Log out and back in      # GNOME extensions load; starship/fastfetch live
 3. (Optional) Install Vencord — Discord theming mod:
      sh -c "$(curl -sS https://raw.githubusercontent.com/Vencord/Installer/main/install.sh)"
 4. (Optional) Firefox gruvbox theme + Dark Reader from addons.mozilla.org
-----------------------------------------------------------------------------
EOF

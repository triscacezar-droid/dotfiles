# rice — Ubuntu + GNOME rice

Everything installed and configured during the 2026-04-23 ricing session.
Target: Ubuntu 24.04 LTS with GNOME 46 on Wayland.
Theme: **Gruvbox Dark** throughout.

## One-command install on a fresh machine

```bash
curl -fsSL https://raw.githubusercontent.com/triscacezar-droid/rice/main/bootstrap.sh | bash
```

That clones this repo into `~/rice`, runs `install.sh`, and drops the `rice`
CLI into `~/.local/bin/rice`. Both are idempotent — safe to re-run after
partial failures or to pick up changes.

Prefer to clone by hand? Same result:

```bash
git clone https://github.com/triscacezar-droid/rice.git ~/rice
~/rice/install.sh
```

## The `rice` CLI

After install, everything is driven by `rice`:

```
rice install              install / refresh everything
rice update               git pull in $RICE_HOME, then reinstall
rice theme                show current theme + list available
rice theme <name>         switch theme (terminal / cursor / gnome / folders / wallpaper / conky)
rice theme list           list themes
rice theme current        print the current theme
rice doctor               sanity-check the install
rice edit                 open the repo in Cursor
rice where                print $RICE_HOME
rice --help
```

Clone location is `$HOME/rice` by default — override with `RICE_HOME=/other/path`.

## What this setup gives you

### Shell & terminal
- **Kitty** 0.46 and **Alacritty** 0.13 — both themed Gruvbox Dark with
  JetBrainsMono Nerd Font 11pt. Kitty is the primary terminal (supports inline
  images via graphics protocol, tabs, splits). Alacritty is the minimal
  alternative with 5 other preloaded themes you can swap via one-line edit.
- **Zsh** + **oh-my-zsh** + `zsh-autosuggestions` + `zsh-syntax-highlighting`.
- **Starship prompt** with the `gruvbox-rainbow` preset — shows git branch,
  Python venv, exit codes, language versions.
- **Fastfetch** runs on each interactive shell open — custom gruvbox-orange
  config at `~/.config/fastfetch/config.jsonc` with Nerd-Font key icons,
  green title, orange accents, and a compact module layout.
- **Atuin** replaces `Ctrl+R` history search with fuzzy TUI + SQLite-backed
  history.
- **CLI replacements**: `eza` (ls), `bat` (cat), `fzf` (fuzzy), `fd` (find),
  `rg` (grep), `zoxide` (smarter cd, `z <partial>` jumps to frequently-visited
  dirs), `lazygit` (terminal git UI), `btop` (system monitor), `yazi` (TUI
  file manager with inline image preview in Kitty).

### Editors / PDF
- **Cursor** IDE with the `jdinhlife.gruvbox` extension set to Gruvbox Dark
  Medium.
- **Zathura** for PDFs with gruvbox recolor — keyboard-driven, `Ctrl+r` toggles
  between themed and original colors.

### GUI (GNOME 46)
- **Papirus-Dark** icon theme.
- **Gruvbox-Orange-Dark** GTK theme.
- **Bibata-Modern-Classic** cursor theme.
- Gruvbox wallpaper pool in `~/Pictures/Wallpapers/`.
- GNOME extensions: **Vitals** (CPU/RAM/GPU/temps in top bar), **Blur My Shell**,
  **Clipboard Indicator**, **Caffeine**.
- **Nautilus Copy Path** right-click extension (custom Python extension,
  uses Gdk.Clipboard directly — no `wl-copy` subprocess because that hangs
  from inside GTK apps).

### Login + lock screen
- **GDM** (login) uses the gruvbox gradient wallpaper plus Bibata cursor /
  Papirus icons on the greeter. Ubuntu's GDM ignores plain dconf overrides —
  the background is baked into `/usr/share/gnome-shell/gnome-shell-theme.gresource`.
  We install the `gdm-settings` apt package and drive its Python API from
  `install.sh` to patch the gresource (a `.default` backup is saved next to
  it). Plain dconf overrides are installed as a fallback for vanilla GDM.
  Sources live in `configs/gdm/`.
- **Lock screen** (`Super+L`) uses the same wallpaper via
  `org.gnome.desktop.screensaver picture-uri`. Kept in sync with the desktop
  wallpaper by both `install.sh` and `scripts/set-theme.sh`, so theme
  switching updates the lock screen too.

### Desktop widget
- **Conky** — gruvbox-themed translucent overlay in the top-left of the
  desktop. Shows hostname/kernel, clock, CPU (total + 16-thread grid + temp),
  GPU (busy% + temp + VRAM, from `/sys/class/drm/card*` and `sensors`), RAM,
  swap, disk, network (IP + up/down), Dublin weather (via `wttr.in`, cached
  30 min in `~/.cache/conky/weather.txt`), and top 5 processes by CPU / RAM.
  Autostarts on login via `~/.config/autostart/conky.desktop`. Change weather
  location by setting `WTTR_LOCATION` in `configs/conky/weather.sh`. The
  network iface is hardcoded to `enp2s0` — edit the `${… enp2s0}` tokens in
  `conky.conf` to match your machine.

### Keyboard shortcuts
- **Super+Shift+M — Nice Maximize**: expands the focused window to fill the
  screen but leaves 20px gaps on all sides so the wallpaper and conky peek
  through. Powered by the `tiling-assistant` GNOME extension (ships with
  Ubuntu) with `maximize-with-gap` enabled; same gap value used everywhere
  it tiles (left/right/quarter/etc).
- **Super+K — Surface Kitty**: cycles focus across all running kitty OS
  windows. Uses kitty's remote-control socket (`unix:@kitty`), so it works
  under native Wayland. If no kitty is running, it **restores the saved
  session** (see below) or launches a plain kitty if no session exists.
  Requires `allow_remote_control yes` + `listen_on unix:@kitty` in
  `kitty.conf` (already set by our config); kittys started before those
  lines existed don't expose a socket and won't participate.

### Kitty session persistence
- `kitty-save-session` snapshots every running kitty OS window / tab /
  window (with cwd + layout) into `~/.cache/kitty/session.conf` that
  `kitty --session` can replay. A systemd user timer
  (`kitty-session-save.timer`, every 60 s) runs it automatically.
- **Pre-socket kittys are captured via `/proc` fallback.** kitty's remote
  control is startup-time only, so kittys launched before `listen_on
  unix:@kitty` existed aren't reachable via IPC. The save script scans
  `/proc` for `kitty` master processes, walks their descendants to find
  child shells (and claude processes), and emits one OS window per shell.
  Tabs/splits are flattened in this fallback mode; the IPC path preserves
  them. The two paths are unioned, deduping via shell PIDs so the same
  window isn't captured twice.
- `kitty-restore-session` launches `kitty --session <file>` against that
  snapshot; Super+K also uses it as the first-launch path when no kitty is
  running.
- **Claude Code windows resume their exact conversation**, even when
  multiple claude processes share the same cwd (e.g. three splits in one
  kitty). The save script reads each claude foreground process's PID,
  looks up `~/.claude/sessions/<pid>.json`, and pulls `sessionId` — a
  per-process resume token that Claude Code writes on startup. The
  restore command becomes
  `zsh -ic 'claude --dangerously-skip-permissions -r <sessionId>; exec zsh -i'`
  so the shell stays alive after you exit claude.

### Not covered by the installer (do manually)
- **Discord → Vencord** mod — run the interactive installer:
  `sh -c "$(curl -sS https://raw.githubusercontent.com/Vencord/Installer/main/install.sh)"`
- **Firefox** gruvbox — install the "Gruvbox" theme addon and Dark Reader,
  or apply gruvbox userChrome CSS.

## Post-install manual steps

1. **Log out and back in** — required on Wayland for new GNOME extensions to
   load (Vitals etc.).
2. **Change default shell**:
   ```
   chsh -s $(which zsh)
   ```
   Asks for your user password (not sudo). Logout/login to pick up.

## Changing the color theme

```bash
# Stock / system defaults
rice theme ubuntu              # Yaru-dark + classic GNOME aubergine terminal
rice theme ubuntu_light        # Yaru + light terminal
rice theme adwaita             # vanilla GNOME, dark
rice theme adwaita_light       # vanilla GNOME, light
# Dark
rice theme gruvbox_dark        # default
rice theme catppuccin_mocha
rice theme tokyo_night
rice theme tokyo_night_storm
rice theme dracula
rice theme nord
rice theme rose_pine
rice theme everforest
rice theme kanagawa
# Light
rice theme gruvbox_light
rice theme solarized_light
rice theme github_light
rice theme catppuccin_latte
rice theme rose_pine_dawn
```

`rice theme` with no args shows the current theme plus the full list.
`rice theme` is a thin wrapper over `scripts/set-theme.sh` — calling the
script directly still works.

**What the script changes:**
- Alacritty — rewrites the `import = [...]` line to point at the chosen theme.
- Kitty — `kitten themes --reload-in=all "<Theme Name>"` (live reload, all windows).
- Cursor IDE — edits `workbench.colorTheme` in `settings.json`.
- GNOME — switches `color-scheme` to `prefer-dark` / `prefer-light`.
- GTK theme — `org.gnome.desktop.interface gtk-theme` (only if the matching
  theme is installed in `~/.themes` or `/usr/share/themes`; silently skipped
  otherwise).
- **Papirus folders** — re-colors folder icons via `papirus-folders -C <color>`
  (needs one `pkexec` auth prompt per switch; caches nothing).
- **Wallpaper** — regenerates a 3840x2160 gradient using
  `scripts/gen-wallpaper.py --top ... --bottom ...` and applies it.
- **Conky widget** — rewrites the palette fields (`color1..9`,
  `default_color`, `own_window_colour`) in-place in
  `configs/conky/conky.conf` and restarts conky so the change is live.

Each theme has a file in `scripts/themes/<name>.sh` that declares the
palette, accent, Papirus folder color, wallpaper gradient, and GTK theme
name. To tweak a theme or add a new one, edit/create a file there — no
changes to `set-theme.sh` needed.

**What the script does NOT change** (hand-themed, low visual impact):
- Yazi (`configs/yazi/theme.toml`)
- Lazygit (`configs/lazygit/config.yml`)
- Starship (`configs/starship/starship.toml`)

**Zathura caveat**: it reads its config at startup, so already-open windows
keep the old colors. Quit and relaunch to pick up a theme switch. PDF
recolor is auto-enabled for dark themes and disabled for light ones.

**Cursor IDE caveat:** switching to a non-gruvbox theme assumes the matching
Cursor extension is installed. Solarized Light ships built-in. Install the
others with:
```bash
cursor --install-extension Catppuccin.catppuccin-vsc       # mocha + latte
cursor --install-extension enkia.tokyo-night
cursor --install-extension dracula-theme.theme-dracula
cursor --install-extension arcticicestudio.nord-visual-studio-code
cursor --install-extension mvllow.rose-pine                # rose_pine + dawn
cursor --install-extension sainnhe.everforest
cursor --install-extension metaphore.kanagawa
cursor --install-extension github.github-vscode-theme       # github_light
```

**GTK theme caveat:** only the `Gruvbox-Orange-Dark/Light` variants are
installed by `install.sh`. For other themes the switcher silently skips
the GTK step. To get full GTK theming for a non-gruvbox theme, clone the
matching repo from [Fausto-Korpsvart](https://github.com/Fausto-Korpsvart)
(Catppuccin-GTK-Theme, Tokyonight-GTK-Theme, Nordic, RosePine-GTK-Theme,
Dracula-GTK-Theme, Everforest-GTK-Theme, Kanagawa-GTK-Theme) and run its
install script into `~/.themes`.

## Directory layout

```
~/rice/
├── README.md              # this file
├── bootstrap.sh           # curl | bash entrypoint — clones + runs install.sh
├── install.sh             # idempotent installer
├── bin/
│   └── rice               # CLI (symlinked to ~/.local/bin/rice by install.sh)
├── scripts/
│   ├── set-theme.sh       # full-rice system-wide theme switcher
│   ├── gen-wallpaper.py   # gradient wallpaper generator (--top / --bottom)
│   ├── kitty-surface.sh           # Super+K window cycler / first-launch session restore
│   ├── kitty-save-session.sh      # snapshot kitty layout (systemd timer runs it)
│   ├── kitty-restore-session.sh   # replay the snapshot via `kitty --session`
│   └── themes/            # per-theme palette files sourced by set-theme.sh
│       ├── gruvbox_dark.sh
│       ├── catppuccin_mocha.sh
│       └── …
├── configs/               # canonical config files (symlinked to ~/.config/*)
│   ├── kitty/kitty.conf
│   ├── alacritty/alacritty.toml
│   ├── alacritty/themes/*.toml
│   ├── starship/starship.toml
│   ├── zathura/zathurarc
│   ├── yazi/theme.toml
│   ├── lazygit/config.yml
│   ├── conky/conky.conf       # desktop widget layout
│   ├── conky/weather.sh       # wttr.in fetcher (symlinked to ~/.local/bin/conky-weather)
│   ├── conky/conky.desktop    # GNOME autostart entry
│   ├── fastfetch/config.jsonc # shell splash config
│   ├── gdm/profile-gdm        # login-screen dconf profile (→ /etc/dconf/profile/gdm)
│   ├── gdm/00-theme           # login-screen theme override (→ /etc/dconf/db/gdm.d/)
│   ├── nautilus-python/copy_path.py
│   └── zshrc
```

Editing a config in `~/rice/configs/` propagates to the live location
because the installer creates symlinks (not copies).

Personal aliases and anything machine-specific (API tokens, local paths,
workflow shortcuts) belong in `~/.zshrc.local` — sourced automatically by
this `zshrc` and gitignored so it never leaks into the public repo.

## Gotchas discovered during setup

- **Nautilus + `wl-copy`**: a Python Nautilus extension that shells out to
  `wl-copy` will hang for seconds (freezing the file manager) because of
  pipe-handling edge cases from inside GTK. Use `Gdk.Display.get_default().get_clipboard().set(text)`
  instead — zero subprocess, instant.
- **Gruvbox-GTK-Theme needs `sassc`**: the install script compiles SCSS
  on first run. `sudo apt install sassc` or it silently ships a broken link.
- **GNOME extensions on Wayland**: newly installed extensions don't load
  until logout/login. No `Alt+F2 r` shortcut like on X11.
- **Kitty font changes** need a full process restart, not just `Ctrl+Shift+F5`
  config reload.
- **libadwaita 1.5 vs 1.6**: the Gruvbox GTK theme uses `--accent-color` CSS
  custom properties that are only in libadwaita 1.6 (GNOME 47+). On 24.04 /
  GNOME 46 / libadwaita 1.5, these log harmless CSS parse warnings.
- **gnome-extensions-cli** UUIDs are case-sensitive. `Vitals@CoreCoding.com`
  works; `vitals@CoreCoding.com` errors "not found".
- **fastfetch is not in Ubuntu 24.04 apt** — install from upstream deb.
- **eza is not in Ubuntu 24.04 apt** — install the static binary from
  GitHub releases.
- **btop in Ubuntu 24.04 apt (v1.3.0) segfaults on Ryzen iGPU** through the
  ROCm-SMI code path. Install the upstream v1.4.x static musl binary
  (`GPU_SUPPORT=false`) into `~/.local/bin`. GPU info is handled by conky
  anyway, so no loss.

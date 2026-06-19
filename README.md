# i3lock-style Dial for the KDE Plasma Lock Screen

Replace the boring password text field on the **KDE Plasma 6** lock screen with an
**i3lock-style reactive ring "dial"** — without leaving the real KDE locker.

[![KDE Plasma 6](https://img.shields.io/badge/KDE%20Plasma-6.6-1d99f3?logo=kde&logoColor=white)](https://kde.org/plasma-desktop/)
[![Wayland & X11](https://img.shields.io/badge/Wayland%20%26%20X11-supported-green)](#requirements)
[![No build step](https://img.shields.io/badge/build-none%20(just%20QML)-lightgrey)](#what-it-changes)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](#license)

The ring lights up as you type, runs a segmented spinner while it checks your
password, then flashes **dark-red on failure** / **dark-green on success**.
Everything else stays stock — clock, wallpaper, user avatar, virtual keyboard,
fingerprint/smartcard. The power-button row becomes **Sleep · Restart · Shut Down
· Switch User**.

It’s the *look* of i3lock, but it’s the **real KDE locker** — so Super+L, lock on
suspend/resume, idle lock and lock-after-reboot all work with no extra setup.

<!-- TODO: add a screenshot/GIF here, e.g.:
     ![the dial reacting as you type, then the power-button row](docs/screenshot.png)
     A short GIF of typing → spinner → green/red is the single most useful addition. -->

## Features

- **Reactive ring** — flashes on every keystroke and backspace (characters are never shown).
- **Live auth states** — idle (blue) → spinner (verifying) → red (wrong) / green (success).
- **Real locker, zero compromises** — `PasswordSync`, grace lock, virtual keyboard,
  clear, fingerprint and smartcard all keep working; the dial is purely visual.
- **Power row** — Sleep · Restart · Shut Down · Switch User.
- **No build step** — three QML files; nothing to compile.
- **Safe & reversible** — full timestamped backup before any write, with `uninstall` /
  `apply`, plus auto-revert if an install fails midway.
- **Try before you touch anything** — `./preview.sh` runs it sandboxed, no root, no real lock.

## Quick start

```sh
git clone https://github.com/Yosh145/KDE-Dial-Lockscreen.git
cd KDE-Dial-Lockscreen
./preview.sh          # sandboxed preview — no root, your real lock screen is untouched
sudo ./install.sh     # back up the originals, then install the dial system-wide
```

## Why it installs into a system file

On Plasma 6 the lock screen UI is **QML that lives inside the system Plasma shell
package** (`org.kde.plasma.desktop`), not in any user-level "theme" you can switch
(the `kscreenlockerrc` *Theme* key only changes wallpaper/colors, not this QML).
So the dial has to be installed into:

```
/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/
```

That needs `root`, and a Plasma update can reset it — so the installer takes a
**full backup** first and is **fully reversible** (`uninstall` / `apply`).

## What it changes

| File | Action |
|------|--------|
| `DialIndicator.qml` | **added** — the i3lock ring (self-contained `Canvas`, version-agnostic) |
| `MainBlock.qml` | **replaced** — hides the password field, mounts the dial over it |
| `LockScreenUi.qml` | **replaced** — adds Restart + Shut Down to the button row |

The original of every touched file is saved to
`/usr/local/share/betterlockscreen-dial/backups/` as a timestamped tarball.

## Requirements

- **KDE Plasma 6** (X11 or Wayland). Built and tested on **Plasma 6.6**.
- `bash`, `tar`, `python3` (preview only), and `sudo` for install/uninstall.

## Try it first (no changes, no root)

```sh
./preview.sh
```

This builds a throwaway copy of the shell under a *different* name (your real
desktop and lock screen are untouched) and opens the dial in KDE’s `--testing`
window. Type to see the ring react; submit a password to see the spinner; press
**Enter** in the terminal to close and clean up.

## Install

```sh
sudo ./install.sh           # back up the originals, then install the dial
```

Then test without logging out:

```sh
loginctl lock-session       # or press Super+L
```

Set the lock wallpaper (any image, PNG or JPG) in **System Settings → Screen
Locking → Appearance**.

> **Scope:** this covers **kscreenlocker** only — Super+L, idle lock, and
> suspend/resume. The screen shown after a full reboot or *Switch User* is a
> separate program (the Plasma Login Manager) and is intentionally left stock.

## Revert / manage

```sh
sudo ./install.sh uninstall   # restore the original lock screen from backup
     ./install.sh status      # show install state, Plasma version, backups (no root)
sudo ./install.sh apply       # re-install after a Plasma update reset the file
```

If an install ever fails midway it **auto-reverts** to the backup. You can also
always restore by hand: extract the latest tarball from
`/usr/local/share/betterlockscreen-dial/backups/` over the lockscreen dir.

### After a Plasma upgrade

A system update overwrites the lock screen file with the new stock version, so
the dial disappears (your machine is back to normal — nothing breaks). Run
`sudo ./install.sh apply` to put it back. `apply` re-snapshots the *new* stock
first, so `uninstall` always restores the version matching your current Plasma.

## Different distro or Plasma version

- The path above is the standard KDE location on Fedora, Arch, openSUSE, Debian,
  Kubuntu/KDE neon, etc. If your distro differs, point the installer at it:
  ```sh
  BLS_LOCKDIR=/custom/path/to/contents/lockscreen sudo ./install.sh
  ```
- `DialIndicator.qml` is self-contained and works on any Plasma 6.
- `MainBlock.qml` and `LockScreenUi.qml` are clones of **Plasma 6.6** stock with
  the dial edits applied. On a noticeably different Plasma version they may drift.
  If the lock screen looks wrong after installing, re-derive them:
  1. Copy your system’s stock `MainBlock.qml` and `LockScreenUi.qml` from the
     lockscreen dir into `lockscreen/`.
  2. Re-apply the two edits: in `MainBlock.qml` hide the `PasswordField` + login
     button and mount `DialIndicator { passwordField: passwordBox }`; in
     `LockScreenUi.qml` add the Restart/Shut Down `ActionButton`s. (Diff against
     the shipped copies here as a guide.)
  3. `sudo ./install.sh`.

## Customizing the dial

All knobs are at the top of `lockscreen/DialIndicator.qml`:

- Colors: `colIdleRing` (`#003366`), `colWrongRing`, `colSuccessRing`,
  `keyhlColor`, `bshlColor`, `spinnerColor`.
- Size: `dialUnits` (in grid units), `ringWidth`.
- Spinner: `segmentCount`, `spinTrail` (bright head length), `segmentGapFrac`.

Edit, then `./preview.sh` to check, then `sudo ./install.sh apply`.

## License

MIT.

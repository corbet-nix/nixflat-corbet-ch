# nixflat

Flatpak as a declarative delivery channel, owned in one place instead of copied per catalogue.

## Why this exists

Package delivery already has two owners: pacman/AUR belongs to
[nixarch](https://github.com/julian-corbet/nixarch-corbet-ch), nixpkgs belongs to the NixOS
module system. **Flatpak had none** — every catalogue with a Flatpak-only entry reimplemented the
installer itself. [nixmsg](https://github.com/julian-corbet/nixmsg-corbet-ch)'s
`modules/flatpak-install.nix` was the first; the second was about to be written verbatim for
[nixoffice](https://github.com/julian-corbet/nixoffice-corbet-ch), which had just declared a
Flatpak-only app of its own. Extracting at that point rather than after the copy is the only
reason there is one implementation to fix when the next remote-handling bug turns up — and there
has already been one. nixflat is that one place.

## What this is

- **`modules/nixflat.nix`** — the policy layer. `nixflat.apps` and the dedup + conflict logic
  behind it, plus `nixflat.archPackages` (the `flatpak` runtime, as a pacman name, for whatever
  Arch reconciler picks it up). Importable on its own if you want the shape without the installer.
- **`modules/install.nix`** — the installer: a systemd oneshot that `remote-add`s every distinct
  remote the declared apps need and installs each app from *its own* remote. One file, imported
  unmodified by both platform backends below — Flatpak APP install has no platform divergence to
  backend around, unlike a repo/AUR/nixpkgs catalogue.
- **`modules/nixos.nix`**, **`modules/arch.nix`** — per-plane wrappers around `install.nix`, kept
  as separate files so the flake's `nixosModules.default` / `systemManagerModules.default` outputs
  stay independently stable when a genuinely platform-specific need shows up — which happened:
  `nixos.nix` now also wires `services.flatpak.enable`, the `flatpak` RUNTIME's NixOS-side
  counterpart to `archPackages` above (see "Does nixflat declare the `flatpak` package itself?"
  below).

## The option surface

```nix
nixflat.apps = [
  { id = "com.discordapp.Discord"; remoteName = "flathub"; remoteUrl = "https://flathub.org/repo/flathub.flatpakrepo"; }
  { id = "ch.threema.threema-desktop"; remoteName = "threema-desktop"; remoteUrl = "https://releases.threema.ch/flatpak/threema-desktop/"; }
];
```

Id and remote travel **together**, never as a bare id list plus a second lookup — a bare id list
can only ever assume Flathub, which is exactly wrong for an app like Threema's desktop client
that Flathub does not carry at all (Flathub's own Threema listing,
`ch.threema.threema-web-desktop`, is a *different app*; the real client is Threema GmbH's own
build, `releases.threema.ch`).

Two catalogues in this family already emit precisely this shape, read-only —
[nixmsg](https://github.com/julian-corbet/nixmsg-corbet-ch)'s `nixmsg.flatpakApps` and
[nixoffice](https://github.com/julian-corbet/nixoffice-corbet-ch)'s `nixoffice.flatpakApps` — so
wiring both into nixflat is one line:

```nix
nixflat.apps = config.nixmsg.flatpakApps ++ config.nixoffice.flatpakApps;
```

`nixflat.apps` deduplicates by exact `(id, remoteName, remoteUrl)` match: an app both catalogues
happen to agree on collapses to one install, and a remote both catalogues name collapses to one
`remote-add`. An app declared with two *different* remotes, or a remote name pointing at two
*different* urls, is not deduplicated — it is a build-time assertion failure, because
`remote-add --if-not-exists` would otherwise let whichever declaration rendered first win while
the other silently never gets its remote added. `nixflat.resolvedApps` / `nixflat.remotes` are
the read-only, already-deduplicated values `modules/install.nix` actually renders from.

## Does nixflat declare the `flatpak` package itself?

**Yes, now — on every plane, gated on the same signal the installer itself uses.**
`modules/install.nix` still puts `pkgs.flatpak` on its *own* systemd unit's `path` regardless (the
oneshot needs it on its PATH whether or not anything else on the host also provides it), but that
used to be the whole story, and it stopped being one place too many: the `flatpak` package itself
was hand-written as an identical raw pacman string in two separate consumer host files, with no
repo owning it — the same duplication this project exists to end for apps and remotes. Now:

- **`nixflat.archPackages`** (`modules/nixflat.nix`) — `[ "flatpak" ]` when this host has resolved
  at least one app (`nixflat.resolvedApps != [ ]`), `[ ]` otherwise. A plain pacman-name list,
  published read-only for whatever reconciler a system-manager consumer runs, the same
  "publish a list, the consumer wires it in" boundary nixbmc's own `archPackages` draws for
  itself:

  ```nix
  nixarch.packages.pacman = config.nixflat.archPackages;
  ```

- **`services.flatpak.enable`** (`modules/nixos.nix`) — set to `true` under the identical
  `resolvedApps != [ ]` gate. This is an upstream nixpkgs module, not a bare package name: it
  installs `flatpak` **and** registers it with D-Bus and systemd in one step, so there is no
  second line to add for the package itself on this plane. Asking for `pkgs.flatpak` in
  `environment.systemPackages` directly would be the same category of gap this project's own
  `portals`-role sibling in nixdesktop already documents for a different package — present, but
  never actually registered with anything.

**Both gated on `resolvedApps`, no new toggle.** A consumer who imports this flake but declares no
apps in `nixflat.apps` gains nothing extra on either plane — exactly the same behaviour as before
this option existed, just now stated as a real value instead of an absence.

**What this still does NOT decide** is the layer above the runtime's mere presence: whether an
operator gets an interactive `flatpak` CLI wired into their own shell beyond what the package
already puts on `$PATH`, which portal *backend* (gtk, gnome, kde...) a desktop registers, autostart
commands, workspace-pin window rules, or compositor wiring. Those stay host-level desktop-policy
decisions, the same boundary nixmsg's own installer draws for the identical reason.

**A working file picker needs more than the package, on at least one real deployment of this
family.** Flatpak's sandboxed file chooser goes through `xdg-document-portal`, which needs real
userspace FUSE — on a privileged LXC container running this flake's Arch backend, `/dev/fuse` was
simply absent (the container's `/dev` is rebuilt from scratch every start) until the *host* bound
it in and cgroup-allowed it; an ordinary bare-metal box needed nothing extra, its `/dev/fuse`
already being present as an ordinary device node. That is not something this module can detect or
fix at eval time — a container's device visibility is a fact about the container runtime, not
about anything `nixflat.apps` or `resolvedApps` could ever express — so it stays a note for
whoever composes this flake onto a container, not a gate this repo adds for itself.

## Non-vacuity: the checks fail on the bug they exist to catch

`checks/default.nix` is written against a REAL regression: an earlier nixmsg installer hardcoded
Flathub as the only remote it would ever add or install from, which could not install Threema's
own catalogue entry at all (see that file's own header for the live-confirmed detail). To prove
the suite here would actually have caught it — not just that it currently passes — the fix was
reverted in `modules/install.nix` (both `remote-add` and `install` lines hardcoded back to
`flathub`) and `nix flake check` was run against that broken version before being restored. It
failed, then passed once restored — which is what "non-vacuous" actually means here, since a
suite that passes on both versions is proving nothing. Reproduce it the same way: hardcode
`flathub` into either rendered line and re-run `nix flake check`.

## Platform support

**NixOS:** Full — `nixosModules.default` (== `nixosModules.install`). App install: the shared
oneshot. Runtime: `services.flatpak.enable`, wired directly by this module — nothing left for a
consumer host to add.

**Arch / CachyOS (via system-manager):** Full — `systemManagerModules.default`. App install has no
platform divergence, so this is not a reduced backend the way nixmsg's/nixoffice's Arch side is
(those publish package-name lists for a host reconciler because pacman itself does the installing
for apps; nixflat's Arch backend installs apps directly, exactly like its NixOS backend). The
runtime package is the one place this backend genuinely IS reduced, the same way nixmsg's/
nixoffice's Arch side is for their own packages: `archPackages` publishes the pacman name, and a
consumer host wires it into its own reconciler (`nixarch.packages.pacman = config.nixflat.archPackages;`)
— this backend has no reconciler of its own to install it with directly.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `nixosModules`/`systemManagerModules` outputs. |
| `modules/nixflat.nix` | Platform-neutral policy: the `apps` option, dedup, conflict guards, and `archPackages` (the `flatpak` runtime as a pacman name). |
| `modules/install.nix` | The shared APP installer (systemd oneshot). One file, both planes. |
| `modules/nixos.nix` | NixOS backend: imports the installer, wires `services.flatpak.enable` (the runtime). |
| `modules/arch.nix` | Arch/system-manager backend: imports the installer; the runtime is `archPackages`, for a consumer to wire in itself. |
| `checks/` | `nix flake check` — eval-time proof of the dedup/conflict logic, the rendered script, and the runtime-package gating on both planes, including the non-Flathub regression this repo exists to prevent. |

## Related projects

Part of the same independently-usable NixOS module family:
[nixmsg](https://github.com/julian-corbet/nixmsg-corbet-ch) and
[nixoffice](https://github.com/julian-corbet/nixoffice-corbet-ch) (the two catalogues that feed
`nixflat.apps` today), [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (the
pacman/AUR equivalent of this repo's job, for the channel nixflat does not own), and
[nixmedia](https://github.com/julian-corbet/nixmedia-corbet-ch) (a third catalogue shaped the
same way, currently Flatpak-free — a future Flatpak-only entry there wires in with the same `++`
shown above).

## License

MIT License &copy; 2026 Julian Corbet

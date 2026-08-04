# nixflat

Flatpak as a declarative delivery channel, owned in one place instead of copied per catalogue.

## Why this exists

Package delivery already has two owners: pacman/AUR belongs to
[nixarch](https://github.com/julian-corbet/nixarch-corbet-ch), nixpkgs belongs to the NixOS
module system. **Flatpak had none** — every catalogue with a Flatpak-only entry reimplemented the
installer itself. Two copies existed before this repo:
[nixmsg](https://github.com/julian-corbet/nixmsg-corbet-ch)'s `modules/flatpak-install.nix` and a
second one about to be written for a second catalogue — exactly the duplication this project
family has spent effort deleting everywhere else. nixflat is that one place.

## What this is

- **`modules/nixflat.nix`** — the policy layer. One option, `nixflat.apps`, and the dedup +
  conflict logic behind it. Importable on its own if you want the shape without the installer.
- **`modules/install.nix`** — the installer: a systemd oneshot that `remote-add`s every distinct
  remote the declared apps need and installs each app from *its own* remote. One file, imported
  unmodified by both platform backends below — Flatpak install has no platform divergence to
  backend around, unlike a repo/AUR/nixpkgs catalogue.
- **`modules/nixos.nix`**, **`modules/arch.nix`** — thin per-plane wrappers around
  `install.nix`, kept as separate files only so the flake's `nixosModules.default` /
  `systemManagerModules.default` outputs stay independently stable if a genuinely
  platform-specific need ever shows up (see `install.nix`'s own header).

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

**No — not onto the host at large.** `modules/install.nix` puts `pkgs.flatpak` on its *own*
systemd unit's `path`, so the oneshot needs no separate host-level package declaration to run —
composing this flake is self-contained. It stops there deliberately: it does not add `flatpak` to
`environment.systemPackages`, does not enable NixOS's `services.flatpak` (the D-Bus/portal
integration service used for desktop-launcher and sandboxed-file-access integration), and does
not add `flatpak` to an Arch reconciler's package list.

Those three are **desktop-integration policy**, not installer plumbing: whether an operator gets
an interactive `flatpak` CLI on their own `$PATH`, whether installed apps get full portal
integration (file choosers, launcher entries beyond what the app itself ships), and how a host's
own package reconciler is shaped are all host-level decisions this module has no basis to make
for every consumer. This is the same boundary nixmsg's own installer already drew for itself —
autostart commands, workspace-pin window rules, and compositor wiring all live *outside* its
installer for the identical reason: the installer's job is "the declared thing exists", not "the
declared thing is nicely integrated into this particular desktop." A host that wants the
interactive CLI or portal integration adds it itself, same as any other desktop-policy choice.

## Non-vacuity: the checks fail on the bug they exist to catch

`checks/default.nix` is written against a REAL regression: an earlier nixmsg installer hardcoded
Flathub as the only remote it would ever add or install from, which could not install Threema's
own catalogue entry at all (see that file's own header for the live-confirmed detail). To prove
the suite here would actually have caught it — not just that it currently passes — the fix was
reverted in `modules/install.nix` (both `remote-add` and `install` lines hardcoded back to
`flathub`) and `nix flake check` was run against that broken version before being restored. The
real output of both runs is recorded in this repo's commit history / the migration report; the
suite fails on the broken version and passes once restored, which is the property "non-vacuous"
actually means here — a suite that passes on both versions is proving nothing.

## Platform support

**NixOS:** Full — `nixosModules.default` (== `nixosModules.install`).

**Arch / CachyOS (via system-manager):** Full — `systemManagerModules.default`. Flatpak install
has no platform divergence, so this is not a reduced backend the way nixmsg's/nixoffice's Arch
side is (those publish package-name lists for a host reconciler because pacman itself does the
installing; nixflat's Arch backend installs directly, exactly like its NixOS backend).

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `nixosModules`/`systemManagerModules` outputs. |
| `modules/nixflat.nix` | Platform-neutral policy: the `apps` option, dedup, conflict guards. |
| `modules/install.nix` | The shared installer (systemd oneshot). One file, both planes. |
| `modules/nixos.nix`, `modules/arch.nix` | Thin per-plane wrappers around `install.nix`. |
| `checks/` | `nix flake check` — eval-time proof of the dedup/conflict logic and the rendered script, including the non-Flathub regression this repo exists to prevent. |

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

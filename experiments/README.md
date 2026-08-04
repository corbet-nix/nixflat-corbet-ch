# experiments

Throwaway trials and the open-questions ledger — every entry below is a default or an inference in
the modules that is reasoned, not measured against a real running host. Results feed back into the
modules as they close; a fully-closed question moves out of this file into
[`../studies/`](../studies/README.md) rather than lingering here answered.

## Table of contents

001. `--system` Flatpak scope is asserted, not tested against a `--user`-only host

## 001 — `--system` Flatpak scope is asserted, not tested against every shape

**Question:** `modules/install.nix` installs every declared app at `--system` scope
unconditionally, reasoned (see that file's own header) as the right default for a single-operator
workstation with no per-user Flatpak wiring. Never tested against a host that only has
`flatpak --user` available (no root, or a shared multi-user box where `--system` isn't wanted).

Inherited open, not opened here: this question arrived with the installer when it was extracted
out of nixmsg, where it was that repo's experiment 003. It is a property of the installer, so it
followed the installer rather than staying with the catalogue.

**Status:** open; not a blocker for any host this module currently targets.

See the main [README](../README.md) for the project itself.

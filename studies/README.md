# studies

Written-up findings: things that were tried in [`../experiments/`](../experiments/README.md),
worked (or failed instructively), and are worth recording properly — with the reasoning, not just
the result.

A study earns its place here once it changed a decision in the main project. No entries yet: the
one real design question this repo faced — whether nixflat should declare the `flatpak` package
itself — was settled directly in `modules/install.nix`'s own header and `../README.md`, without
needing a spike to decide it.

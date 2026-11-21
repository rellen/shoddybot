# ShoddyBot

ShoddyBot is a self-hosted application for managing software repositories and
the live applications running from them. This repository is a monorepo: each
top-level directory is a separate project with its own toolchain, dependencies
and agent instructions.

## Projects

| Directory | What it is | Stack | Instructions |
| --- | --- | --- | --- |
| [`bot/`](bot/) | The ShoddyBot server and web UI | Elixir, Ash, Phoenix, PostgreSQL | [`bot/AGENTS.md`](bot/AGENTS.md) |

Other clients, such as mobile apps, will be added as further top-level
directories.

## How to work in this repository

- Before changing a project, read its `AGENTS.md`. It has the commands,
  conventions and definition of done. Where it conflicts with this file, the
  project's file wins inside that project.
- Run build, test and generator commands from inside the project directory
  (for example `cd bot && mix test`). Nothing builds from the repository root.
- Keep each change inside one project where you can. If a change crosses
  projects (for example an API the server exposes and a client consumes),
  update both sides in the same change, and update the server's tests for the
  contract.
- Each project owns its own `.gitignore`, lockfile and formatter config. Keep
  build output and dependencies out of git, and do not add tooling at the root
  that only one project needs.
- A new project gets its own top-level directory and its own `AGENTS.md`, and
  a row in the table above.

## Languages and tooling

- Server code is Elixir. Server data lives in PostgreSQL and is accessed
  through Ash and AshPostgres.
- Client-side web code is TypeScript. Do not add plain JavaScript beyond what
  the generators produce.
- Repository scripts are Bash (`#!/usr/bin/env bash` with `set -euo pipefail`),
  not Python or Node.js.
- Do not add dependencies casually. Prefer what the project already uses, and
  say why in the commit message when you add one.

## Toolchain

| Tool | Version |
| --- | --- |
| Elixir | 1.20 |
| Erlang/OTP | 29 |
| PostgreSQL | 17 or later |

The root `flake.nix` pins these versions. With Nix (flakes enabled), run
`nix develop .#bot` from the repository root for a shell with the `bot/`
toolchain, or install the versions above with your system's package manager.

## Nix

`flake.nix` is the one piece of root tooling, because it serves every
project. Each project keeps its Nix expressions in its own `nix/` directory
(`bot/nix/`), and the flake wires them together:

| Output | What it is |
| --- | --- |
| `packages.<system>.shoddybot` (`default`) | The `bot/` Mix release |
| `packages.<linux>.container` | OCI image of the release |
| `nixosModules.shoddybot` (`default`) | `services.shoddybot` |
| `devShells.<system>.bot` (`default`) | Toolchain for `bot/` |
| `checks.<system>.*` | Package and image builds, Nix formatting, and a NixOS VM test of the module |

- Run `nix flake check` after changing anything under `nix/`, `flake.nix`
  or `flake.lock`, and `nix fmt` to format Nix files.
- When `bot/mix.lock` changes, update the `hash` of `mixFodDeps` in
  `bot/nix/package.nix`: set it to `lib.fakeHash`, run
  `nix build .#shoddybot`, and copy the hash Nix reports.
- A new project adds `<project>/nix/shell.nix` and a `devShells` entry.

## Commits

- Write the subject in the imperative mood, in 72 characters or fewer. Prefix
  it with the project directory when the change is confined to one project:
  `bot: add repository resource`.
- In the body, explain why the change was made. The diff already shows what
  changed.
- Never commit secrets, credentials or `.env` files. A deployment supplies a
  few bootstrap environment variables (see `bot/README.md`); everything else
  is configured in the app and stored encrypted in its database.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).

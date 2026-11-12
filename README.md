# LapisMD workspace bootstrap

Bootstrap the active LapisMD development repositories as sibling SSH clones,
install the shared Codex/Cursor workspace guidance, and conservatively clean up
integrated Jujutsu workspaces.

The repository is licensed under [Apache-2.0](LICENSE). It does not install
dependencies, build projects, fetch existing checkouts, or alter remotes.

## Prerequisites

- macOS or Linux with POSIX `sh`
- Git with GitHub SSH access
- Jujutsu 0.45.1 or newer

Place this repository inside the directory that should contain the LapisMD
siblings:

```text
lapismd/
  workspace-bootstrap/
  lapis-notes/
  design-core/
  ...
```

Run every command below from `workspace-bootstrap`.

## Bootstrap

```sh
./bootstrap.sh --dry-run
./bootstrap.sh
```

The default `active` profile contains 24 application, maintenance, framework,
plugin, agent, and JJ repositories. The `all` profile contains 32 repositories,
adding the organization, automation, CI, Homebrew, Nostr, sandbox, and deprecated
Terminal Host repositories:

```sh
./bootstrap.sh --profile all
```

Useful inspection and configuration commands:

```sh
./bootstrap.sh --list
./bootstrap.sh --config-only
./bootstrap.sh --target-root /absolute/existing/directory --dry-run
```

The checked-in `repositories.tsv` is authoritative. New repositories are not
discovered implicitly. Existing checkouts are accepted when any configured
GitHub remote identifies the expected repository, whether that remote uses SSH
or HTTPS and regardless of its name. Existing remotes are never rewritten.

Both profiles include `lapis-maintenance` and `lapis-plugin-terminal`. The
bootstrap repository itself is the checkout these commands run from and is not
repeated in the manifest.

Bootstrap installs the portable root templates at `../AGENTS.md` and
`../.cursor/rules/commit-after-change.mdc`. An existing identical file is
accepted; a difference fails before any installation or clone. There is no
tracked `.codex` configuration in the source workspace: the root `AGENTS.md` is
the Codex configuration, and app-managed workspace directories are not created.

The following local projects are documented but deliberately excluded because
they have no hosted clone remote: `jj-desktop`, `jj-checkpoint`, `jj-nostr`,
`lapis-plugin-nostr-sync`, `lapis-website`, and `nostr-agent-controller`.

## Clean integrated JJ workspaces

Cleanup is preview-only unless `--apply` is present:

```sh
./cleanup-workspaces.sh
./cleanup-workspaces.sh --apply
```

Only recorded workspaces that are direct siblings of the canonical checkouts
are candidates. A candidate must have a clean live working copy, no conflict or
protecting local bookmark, and no non-empty commit outside the fetched remote
`main` ancestry. Cleanup does not fetch. A stale remote can therefore retain a
workspace, but cannot make an unintegrated workspace eligible. Squash-equivalent
changes are not inferred.

`--apply` atomically moves eligible directories, including ignored outputs,
into a batch below `../.workspace-quarantine`. It retains each JJ workspace
registration so the batch can be restored:

```sh
./cleanup-workspaces.sh --restore 20261102T120000Z-12345
./cleanup-workspaces.sh --restore 20261102T120000Z-12345 --apply
```

Permanent deletion requires the exact batch ID and a second explicit apply:

```sh
./cleanup-workspaces.sh --purge 20261102T120000Z-12345
./cleanup-workspaces.sh --purge 20261102T120000Z-12345 --apply
```

Purge revalidates every manifest entry, forgets its JJ registration, and then
deletes only the recorded quarantined directory. Stale, external, dirty,
conflicted, bookmarked, path-escaped, or changed registrations require manual
review.

## Development

```sh
./scripts/verify.sh
```

Verification checks shell syntax, ShellCheck when installed, manifest shape and
profile counts, deterministic command simulations, and real temporary Git/JJ
behavior. It never contacts GitHub.

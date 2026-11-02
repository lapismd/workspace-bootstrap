# Workspace bootstrap agent guide

This repository owns clone inventory, portable workspace guidance installation,
and conservative Jujutsu workspace cleanup. It does not own application source,
dependency installation, builds, publication, or deployment.

- Use Jujutsu and preserve unrelated work. Commit every verified slice.
- Keep scripts POSIX `sh`; support macOS and Linux without Bash-only features.
- Bootstrap may clone and initialize colocated JJ repositories, but must never
  fetch, pull, reset, rewrite remotes, install dependencies, or overwrite
  differing root configuration.
- Cleanup defaults to preview. Only direct sibling workspaces with exact native
  ancestry may be quarantined. Never infer squash-merge equivalence.
- Quarantine preserves complete directories and workspace registrations.
  Permanent deletion requires an exact batch ID and explicit `--apply`.
- Run `./scripts/verify.sh` before committing. Keep workflow actions pinned.
- Do not add secrets, credential-bearing URLs, publishing, or deployment.

# Good Day development workflow

- Treat `https://github.com/MonkeyStar7/Good_Day.git` as the canonical repository.
- After every code, asset, dependency, or configuration change, run the relevant formatting, analysis, and tests.
- Commit each completed development change locally with a descriptive Git commit.
- Keep development changes local by default. Do not push code, tags, packages, or releases to GitHub or any other cloud service unless the user explicitly requests that synchronization or publication. Authorization applies only to the requested update; it does not authorize automatic uploads of future versions.
- Update the installed Windows app in `E:\Apps\Good Day` after the relevant local checks and local commit succeed. Installation does not require a remote push.
- Do not accumulate versioned backup installation directories. Prefer an in-place deployment; if Windows file locking requires a temporary rollback directory, keep it temporary and clearly report it instead of leaving multiple permanent backups.
- Never overwrite or force-push remote history. When the user explicitly requests a push, fetch first and resolve divergence safely.

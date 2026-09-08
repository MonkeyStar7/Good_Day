# Good Day development workflow

- Treat `https://github.com/MonkeyStar7/Good_Day.git` as the canonical repository.
- After every code, asset, dependency, or configuration change, run the relevant formatting, analysis, and tests.
- Commit each completed development change with a descriptive Git commit and push it to `origin/main` before considering the work complete.
- Update the installed Windows app in `E:\Apps\Good Day` only after the commit has been pushed successfully.
- Do not accumulate versioned backup installation directories. Prefer an in-place deployment; if Windows file locking requires a temporary rollback directory, keep it temporary and clearly report it instead of leaving multiple permanent backups.
- Never overwrite or force-push remote history. Fetch first and resolve divergence safely.

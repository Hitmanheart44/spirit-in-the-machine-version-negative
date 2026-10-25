# Recovery backup

Unverified work is preserved as snapshot commits referenced in manifest.json and reachable through this commit parents. Do not merge this branch into main. Restore a snapshot in a separate worktree. The staged snapshot, when present, preserves the original index content separately. Active checkouts and indexes were not changed.

For the desktop archive, concatenate the numbered parts in order, verify their SHA-256 values from the manifest, then extract the resulting tar.gz into a separate directory.

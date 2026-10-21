---
name: opensearch-index-migration
description: >-
  Migrates legacy OpenSearch indices via async reindex + watermark catchup +
  atomic alias cutover (second-level write-block). Use when the user asks to
  migrate/reindex/cutover OpenSearch indices, run opensearch_index_migration.sh,
  upgrade legacy indices, or mentions 秒級切換, fast-switch, reidx, or
  migration.env.
---

# OpenSearch index migration

Live indices: **background full reindex → catchup until gap is seconds-small → write-block → final-delta → atomic `_aliases`**. Do **not** local-backup docs as the standard path (`op_type=create` reindex is resumable).

## Skill layout

| Role | Path (under this skill) |
|------|-------------------------|
| Script | `scripts/opensearch_index_migration.sh` |
| Env template | `scripts/migration.env.example` |
| Env (secrets) | `scripts/migration.env` (gitignored; copy from example) |
| State / dumps | default `.migration_work/` next to the script, or `WORK_DIR` in env |

Also accepts `./scripts/migration.env` or `./migration.env` from the caller’s cwd (compat).

## Prerequisites

1. **`jq`** — used to **parse and build JSON** (OpenSearch request bodies, task/status responses, state file). Must be on `PATH`. If missing:
   ```bash
   if [[ ! -x /tmp/jq ]]; then
     curl -sSL -o /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 && chmod +x /tmp/jq
   fi
   export PATH="/tmp:$PATH"
   ```
   Do **not** invent a Python jq shim or sudo-install unless the user asks.
2. **`curl`** + network access to the OpenSearch endpoint.
3. **Clear CLI overrides** before targeting a new index (env file does not clobber existing vars):
   ```bash
   unset SOURCE_INDEX DEST_INDEX ALIAS_NAME REQUESTS_PER_SECOND REINDEX_SLICES MIGRATE_LARGE_KEEP_RPS
   ```

## Standard run (one index)

From a directory that can resolve env (skill `scripts/` or project with `scripts/migration.env`):

```bash
MIG=".cursor/skills/opensearch-index-migration/scripts"
# or: MIG=path/to/this/skill/scripts
cp -n "$MIG/migration.env.example" "$MIG/migration.env"   # first time
# edit SOURCE_INDEX / DEST_INDEX / ALIAS_NAME / OS_* in migration.env

"$MIG/opensearch_index_migration.sh" inspect
CONFIRM=yes "$MIG/opensearch_index_migration.sh" migrate
```

Large indexes: allow a long shell wait (often 30–90+ minutes for multi-million docs).

Verify: `inspect` → alias resolves to `*_reidx`, `_count` matches.

Step-by-step: `dump-source` → `create-dest` → `reindex-full` → `wait-task` → `catchup` → `CONFIRM=yes fast-switch`.

## Design rules (do not regress)

| Rule | Detail |
|------|--------|
| No doc backup by default | Resumable reindex + compare |
| `slices` as query param only | Body `slices` may return HTTP 400 |
| Watermark | Producer sortable field via `WATERMARK_FIELD` (example format `%Y/%m/%d %H:%M:%S`) |
| Catchup goal | Time proximity (`DELTA_TARGET_SECONDS`, `created→0`), not absolute doc equality |
| Cutover | `POST /_aliases` with `remove_index` + `add` (atomic) |
| Snapshot | Pre-lock wait; under lock retry but **abort+unblock** if `WRITE_BLOCK_MAX_SECONDS` exceeded |
| Live writers | `COMPARE_MAX_DIFF` allows small source>dest gap; final-delta drains under lock |

## Auto-tune (migrate)

- **&lt;250k**: RPS off, slices off  
- **&lt;500k**: RPS off, keep slices  
- **≥500k**: RPS off; slices off if 1 primary shard; bump `REINDEX_SIZE` 1000→2500  
- Keep env RPS: `MIGRATE_LARGE_KEEP_RPS=yes`

## After each successful migrate

If the user asks to refine: improve **this skill’s** `scripts/opensearch_index_migration.sh` based on the run; update `migration.env.example` when adding knobs.

## Abort / resume

| Situation | Action |
|-----------|--------|
| Snapshot blocks pre-lock | `wait-snapshots` then `CONFIRM=yes fast-switch` |
| Write-block budget exceeded | Script unblocks; re-run `catchup` then `fast-switch` |
| Producer recreated physical index after failed DELETE | Block-write → reindex into `*_reidx` → atomic cutover |
| Died mid-fast-switch | Check write-block; unblock only if aborting |

## Do not

- Commit `migration.env` or put secrets in the skill docs
- Skip `CONFIRM=yes` for cutover / fast-switch / migrate

## Reference

- [reference.md](reference.md)
- `scripts/opensearch_index_migration.sh` (`help`)

# OpenSearch migration — reference

## Commands

| Command | Purpose |
|---------|---------|
| `ping` | Cluster root |
| `inspect` | Meta + counts (resolves alias → physical) |
| `dump-source` / `create-dest` | Mapping/settings dump + create `*_reidx` |
| `reindex-full` / `wait-task` | Async full reindex + poll |
| `catchup` | Multi-round watermark delta |
| `fast-switch` | Snapshot wait → compare → block-write → final-delta → cutover |
| `migrate` | One-shot: inspect → auto-tune → dump → create → full → wait → catchup → fast-switch |
| `wait-snapshots` | Pre-lock snapshot clear only |
| `block-write` / `unblock-write` | Manual write block |
| `compare` / `cutover` / `status` | Counts / atomic alias / state dump |

## Dependencies

| Tool | Role |
|------|------|
| `curl` | HTTP to OpenSearch |
| `jq` | Parse and build JSON (bodies, responses, state file) |

## Key env overrides

| Var | Default | Role |
|-----|---------|------|
| `CONFIRM` | — | Required `yes` for migrate / fast-switch / cutover |
| `REQUESTS_PER_SECOND` | from env | `off` / empty = no throttle |
| `REINDEX_SLICES` | `auto` | Query param; `off` for 1-shard clarity |
| `DELTA_TARGET_SECONDS` | `60` | Catchup “took small enough” |
| `DELTA_MAX_ROUNDS` | `10` | Catchup cap |
| `COMPARE_MAX_DIFF` | `100` | Max source−dest before lock |
| `SNAPSHOT_PRECHECK` | `yes` | Wait before write-block |
| `SNAPSHOT_WAIT_BEFORE_LOCK_SECONDS` | `300` | Pre-lock max wait |
| `WRITE_BLOCK_MAX_SECONDS` | `120` | Abort+unblock under lock (`0`=off) |
| `FINAL_DELTA_SYNC` | `yes` | Sync reindex under write-block |
| `MIGRATE_LARGE_REINDEX_SIZE` | `2500` | Auto bump scroll size on large |
| `MIGRATE_LARGE_KEEP_RPS` | — | Keep throttled RPS on large |
| `SKIP_ALIAS_VERIFY` | migrate: yes | Skip GET after cutover |
| `QUIET` | migrate: yes | Less dump chatter |

CLI exports beat `migration.env` (no-clobber load).

## Metrics to report

- Full reindex `took` / docs/s  
- `write_block_window_ms` (403 for producers)  
- `reader_cutover_ms` / atomic aliases  
- `migrate_wall_ms`  
- `snapshot_precheck`  

Healthy cutover is often a few seconds; **≤5s** is a reasonable target when snapshots/API are calm. Large wall time is almost always **full reindex**, not cutover.

## Watermark

Producers write a sortable field before index; set `WATERMARK_FIELD` to match mapping (example name `EventTimestamp`, format e.g. `%Y/%m/%d %H:%M:%S`).  
Catchup advances `watermark_gte`; final-delta uses last delta start − `FINAL_DELTA_MARGIN_MINUTES` and does not advance.

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
| `MIGRATE_RPS_LOAD_FRACTION` | `2/3` | Mid/large: RPS = full × fraction (CPU guard) |
| `MIGRATE_RPS_ESTIMATE_FROM_STORE` | `yes` | Derive FULL from `pri.store / docs` |
| `MIGRATE_RPS_REF_BYTES_PER_DOC` | `5700` | Calibration bytes/doc (~east_run) |
| `MIGRATE_RPS_REF_FULL_DOCS_S` | `900` | Calibration unthrottled docs/s |
| `MIGRATE_RPS_ESTIMATE_MIN` / `MAX` | `400` / `8000` | Clamp for estimated FULL |
| `MIGRATE_RPS_FULL` | (unset) | Explicit FULL skips store estimate; else estimate → env RPS → `900` |
| `MIGRATE_LARGE_KEEP_RPS` | — | Keep env RPS as-is (skip fraction) |
| `MIGRATE_RPS_ADAPTIVE` | `yes` | wait-task: rethrottle via CPU EMA |
| `MIGRATE_CPU_TARGET_LOW` / `HIGH` | `75` / `85` | EMA band for raise / cut |
| `MIGRATE_CPU_PANIC` | `95` | Instant cut on now-CPU |
| `MIGRATE_CPU_EMA_ALPHA` | `35` | EMA new-sample weight (%) |
| `MIGRATE_CPU_EMA_WARMUP` | `2` | Samples before raise/cut |
| `MIGRATE_RPS_ADAPTIVE_START` | (unset) | If set: wait-task start when RPS off; else store estimate × fraction (fallback 4000) |
| `MIGRATE_RPS_MIN` / `MAX` | `500` / `8000` | Adaptive clamp |
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

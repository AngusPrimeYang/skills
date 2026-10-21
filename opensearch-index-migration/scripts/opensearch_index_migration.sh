#!/usr/bin/env bash
# OpenSearch index migration (curl) for upgrading away from legacy indices.
#
# Credentials / URL are NOT hardcoded. Load from an env file (gitignored):
#   cp <this-dir>/migration.env.example <this-dir>/migration.env
#   # edit migration.env
#   ./opensearch_index_migration.sh ping
#
# Or:
#   MIGRATION_ENV=/secure/path/migration.env ./opensearch_index_migration.sh inspect
#
# Recommended flow (no local doc backup — reindex is resumable via op_type=create;
# compare / catchup verify completeness):
#   CONFIRM=yes ./opensearch_index_migration.sh migrate
# Or step-by-step:
#   inspect → dump-source → create-dest → reindex-full → wait-task
#   → catchup → CONFIRM=yes fast-switch
#
# Each reindex-delta advances watermark_gte to (now - margin) for the next round.
# final-delta uses (last delta start - FINAL_DELTA_MARGIN_MINUTES) and does not advance.
# fast-switch keeps the 403 window in one process (aim: seconds after catchup).
# Snapshot / cluster-latency strategy:
#   1) Before write-block: wait until SOURCE is not in an in-progress snapshot
#   2) Cutover uses atomic POST /_aliases {remove_index, add}
#   3) If snapshot still blocks after lock: retry, but abort+unblock when
#      WRITE_BLOCK_MAX_SECONDS exceeded (prefer late cutover over long 403)
# Rollback aid: unblock-write (only works while SOURCE_INDEX still exists)
#
# Requires: curl + jq (jq parses / builds JSON for OpenSearch request/response bodies).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Prefer caller cwd for relative WORK_DIR / project-local env.
REPO_ROOT="${PWD}"

# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------
# Apply KEY=VALUE from env file only when KEY is not already set in the environment
# (so REQUESTS_PER_SECOND=off ./script ... beats migration.env).
load_env_file_no_clobber() {
  local file="$1"
  local line key val
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # trim CR, skip blanks/comments
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" == *"="* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # already set (including empty) → keep CLI / parent value
    if [[ -n "${key}" ]] && declare -p "${key}" &>/dev/null; then
      continue
    fi
    # strip optional surrounding quotes
    if [[ "${val}" =~ ^\".*\"$ ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "${val}" =~ ^\'.*\'$ ]]; then
      val="${val:1:${#val}-2}"
    fi
    printf -v "${key}" '%s' "${val}"
    export "${key}"
  done <"${file}"
}

load_env() {
  local candidates=()
  if [[ -n "${MIGRATION_ENV:-}" ]]; then
    candidates+=("${MIGRATION_ENV}")
  fi
  # Skill-local first, then common project layouts relative to cwd
  candidates+=(
    "${SCRIPT_DIR}/migration.env"
    "${PWD}/scripts/migration.env"
    "${PWD}/migration.env"
    "${SKILL_ROOT}/migration.env"
  )

  local loaded=""
  local f
  for f in "${candidates[@]}"; do
    if [[ -f "${f}" ]]; then
      load_env_file_no_clobber "${f}"
      loaded="${f}"
      break
    fi
  done

  if [[ -z "${loaded}" ]]; then
    echo "ERROR: env file not found." >&2
    echo "  Copy ${SCRIPT_DIR}/migration.env.example -> ${SCRIPT_DIR}/migration.env" >&2
    echo "  Or set MIGRATION_ENV=/path/to/migration.env" >&2
    exit 1
  fi
  echo "Loaded env: ${loaded} (existing env vars not overwritten)"
}

require_cmds() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  # jq: parse/build JSON for API bodies, responses, and state files
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: missing commands: ${missing[*]}" >&2
    echo "  curl = HTTP; jq = parse/build JSON for OpenSearch requests and responses" >&2
    exit 1
  fi
}

require_vars() {
  local key
  for key in "$@"; do
    if [[ -z "${!key:-}" ]]; then
      echo "ERROR: required variable ${key} is empty (set in migration.env)" >&2
      exit 1
    fi
  done
}

init_paths() {
  require_vars OS_BASE_URL SOURCE_INDEX
  OS_BASE_URL="${OS_BASE_URL%/}"
  # Physical dest name: {source}_reidx (override with DEST_INDEX or DEST_SUFFIX)
  DEST_SUFFIX="${DEST_SUFFIX:-_reidx}"
  DEST_INDEX="${DEST_INDEX:-${SOURCE_INDEX}${DEST_SUFFIX}}"
  ALIAS_NAME="${ALIAS_NAME:-${SOURCE_INDEX}}"
  WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/.migration_work}"
  if [[ "${WORK_DIR}" != /* ]]; then
    WORK_DIR="${REPO_ROOT}/${WORK_DIR}"
  fi
  mkdir -p "${WORK_DIR}"
  STATE_FILE="${WORK_DIR}/${SOURCE_INDEX}.state.json"
  SOURCE_DUMP="${WORK_DIR}/${SOURCE_INDEX}.source.json"
  CREATE_BODY="${WORK_DIR}/${DEST_INDEX}.create.json"
  WATERMARK_FIELD="${WATERMARK_FIELD:-EventTimestamp}"
  DELTA_MARGIN_MINUTES="${DELTA_MARGIN_MINUTES:-5}"
  # final-delta only: minutes before last delta start (keep small to minimize lock window)
  FINAL_DELTA_MARGIN_MINUTES="${FINAL_DELTA_MARGIN_MINUTES:-1}"
  # catchup loop: stop when last delta took <= this many seconds (default 60)
  DELTA_TARGET_SECONDS="${DELTA_TARGET_SECONDS:-60}"
  # catchup loop: max delta rounds before giving up
  DELTA_MAX_ROUNDS="${DELTA_MAX_ROUNDS:-10}"
  # catchup loop: also stop if created <= this (default 0 = empty catch-up)
  DELTA_STOP_CREATED="${DELTA_STOP_CREATED:-0}"
  REINDEX_SIZE="${REINDEX_SIZE:-1000}"
  REINDEX_SLICES="${REINDEX_SLICES:-auto}"
}

# ---------------------------------------------------------------------------
# HTTP helper (curl + optional basic auth)
# ---------------------------------------------------------------------------
curl_opts=()
auth_args=()

setup_curl() {
  curl_opts=(-sS -H "Content-Type: application/json")
  if [[ "${OS_INSECURE:-false}" == "true" ]]; then
    curl_opts+=(-k)
  fi

  case "${OS_AUTH:-basic}" in
    basic)
      require_vars OS_USERNAME OS_PASSWORD
      auth_args=(-u "${OS_USERNAME}:${OS_PASSWORD}")
      ;;
    none)
      auth_args=()
      ;;
    *)
      echo "ERROR: OS_AUTH must be 'basic' or 'none' (got: ${OS_AUTH})" >&2
      echo "  IAM SigV4 domains: create an FGAC user for curl, or use awscurl." >&2
      exit 1
      ;;
  esac
}

# os_curl METHOD PATH [json_body]
# Prints response body; writes HTTP code to last line of stderr via wrapper below.
os_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url="${OS_BASE_URL}${path}"
  local tmp_body http_code

  tmp_body="$(mktemp)"
  if [[ -n "${body}" ]]; then
    http_code="$(
      curl "${curl_opts[@]}" "${auth_args[@]}" \
        -o "${tmp_body}" -w "%{http_code}" \
        -X "${method}" "${url}" \
        -d "${body}"
    )"
  else
    http_code="$(
      curl "${curl_opts[@]}" "${auth_args[@]}" \
        -o "${tmp_body}" -w "%{http_code}" \
        -X "${method}" "${url}"
    )"
  fi

  cat "${tmp_body}"
  rm -f "${tmp_body}"

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo >&2
    echo "ERROR: HTTP ${http_code} ${method} ${path}" >&2
    return 1
  fi
}

os_request_allow() {
  # Like os_request but allow a list of OK codes (e.g. 404 on delete).
  local method="$1"
  local path="$2"
  local body="$3"
  shift 3
  local ok_codes=("$@")
  local url="${OS_BASE_URL}${path}"
  local tmp_body http_code code_ok=0

  tmp_body="$(mktemp)"
  if [[ -n "${body}" ]]; then
    http_code="$(
      curl "${curl_opts[@]}" "${auth_args[@]}" \
        -o "${tmp_body}" -w "%{http_code}" \
        -X "${method}" "${url}" \
        -d "${body}"
    )"
  else
    http_code="$(
      curl "${curl_opts[@]}" "${auth_args[@]}" \
        -o "${tmp_body}" -w "%{http_code}" \
        -X "${method}" "${url}"
    )"
  fi

  cat "${tmp_body}"
  local c
  for c in "${ok_codes[@]}"; do
    if [[ "${http_code}" == "${c}" ]]; then
      code_ok=1
      break
    fi
  done
  rm -f "${tmp_body}"
  if [[ "${code_ok}" -ne 1 ]]; then
    echo >&2
    echo "ERROR: HTTP ${http_code} ${method} ${path} (allowed: ${ok_codes[*]})" >&2
    return 1
  fi
}

pretty() {
  if [[ -t 1 ]]; then
    jq .
  else
    cat
  fi
}

state_get() {
  local key="$1"
  if [[ ! -f "${STATE_FILE}" ]]; then
    echo ""
    return 0
  fi
  jq -r --arg k "${key}" '.[$k] // empty' "${STATE_FILE}"
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "${STATE_FILE}" ]]; then
    jq --arg k "${key}" --arg v "${value}" '.[$k]=$v' "${STATE_FILE}" >"${tmp}"
  else
    jq -n --arg k "${key}" --arg v "${value}" '{($k):$v}' >"${tmp}"
  fi
  mv "${tmp}" "${STATE_FILE}"
}

utc_now_watermark_format() {
  # Watermark wall-clock string; default TIME_FORMAT=%Y/%m/%d %H:%M:%S (UTC)
  date -u '+%Y/%m/%d %H:%M:%S'
}

utc_minus_minutes_watermark_format() {
  local minutes="$1"
  if date -u -d "now - ${minutes} minutes" '+%Y/%m/%d %H:%M:%S' >/dev/null 2>&1; then
    date -u -d "now - ${minutes} minutes" '+%Y/%m/%d %H:%M:%S'
  else
    # BSD/macOS
    date -u -v-"${minutes}"M '+%Y/%m/%d %H:%M:%S'
  fi
}

# Subtract minutes from an ISO-8601 UTC timestamp -> watermark string format.
utc_iso_minus_minutes_watermark_format() {
  local iso="$1"
  local minutes="$2"
  if date -u -d "${iso} - ${minutes} minutes" '+%Y/%m/%d %H:%M:%S' >/dev/null 2>&1; then
    date -u -d "${iso} - ${minutes} minutes" '+%Y/%m/%d %H:%M:%S'
  else
    # BSD/macOS: parse then subtract
    local epoch
    epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "${iso}" '+%s')"
    date -u -r "$((epoch - minutes * 60))" '+%Y/%m/%d %H:%M:%S'
  fi
}

now_ms() {
  date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))'
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
cmd_ping() {
  echo "==> GET /"
  os_request GET "/" | pretty
}

cmd_inspect() {
  echo "==> Index meta: ${SOURCE_INDEX}"
  # After cutover, GET /alias resolves to the physical index key (*_reidx), not the alias name.
  os_request GET "/${SOURCE_INDEX}" | jq --arg src "${SOURCE_INDEX}" '
    (.[$src] // .[keys_unsorted[0]]) as $idx
    | {
        resolved_index: (if .[$src] then $src else keys_unsorted[0] end),
        aliases: $idx.aliases,
        settings_index: ($idx.settings.index | {
          creation_date,
          provided_name,
          number_of_shards,
          number_of_replicas,
          version
        })
      }
  '

  echo
  echo "==> _count source"
  os_request GET "/${SOURCE_INDEX}/_count" | pretty

  local dest_code tmp
  tmp="$(mktemp)"
  dest_code="$(
    curl "${curl_opts[@]}" "${auth_args[@]}" \
      -o "${tmp}" -w "%{http_code}" \
      -X GET "${OS_BASE_URL}/${DEST_INDEX}"
  )"
  rm -f "${tmp}"
  if [[ "${dest_code}" == "200" ]]; then
    echo
    echo "==> _count dest (${DEST_INDEX})"
    os_request GET "/${DEST_INDEX}/_count" | pretty
  else
    echo
    echo "(dest ${DEST_INDEX} does not exist yet; HTTP ${dest_code})"
  fi
}

cmd_dump_source() {
  echo "==> Dump ${SOURCE_INDEX} -> ${SOURCE_DUMP}"
  os_request GET "/${SOURCE_INDEX}" | jq . >"${SOURCE_DUMP}"

  # Build create body: mappings + whitelisted settings only
  jq --arg src "${SOURCE_INDEX}" '
    .[$src] as $idx |
    {
      settings: {
        index: (
          ($idx.settings.index // {})
          | del(
              .uuid,
              .version,
              .creation_date,
              .creation_date_string,
              .provided_name,
              .resize,
              .routing,
              .history,
              .blocks
            )
        )
      },
      mappings: ($idx.mappings // {})
    }
  ' "${SOURCE_DUMP}" >"${CREATE_BODY}"

  echo "Wrote create body: ${CREATE_BODY}"
  if [[ "${QUIET:-}" != "yes" ]]; then
    echo "Review/edit ${CREATE_BODY} before create-dest if needed (legacy analyzers, etc.)."
  fi
}

cmd_create_dest() {
  if [[ ! -f "${CREATE_BODY}" ]]; then
    echo "Create body missing; running dump-source first..."
    cmd_dump_source
  fi
  echo "==> PUT /${DEST_INDEX}"
  os_request PUT "/${DEST_INDEX}" "$(cat "${CREATE_BODY}")" | pretty
}

cmd_reindex_full() {
  local t0 watermark
  t0="$(utc_now_watermark_format)"
  watermark="$(utc_minus_minutes_watermark_format "${DELTA_MARGIN_MINUTES}")"
  state_set "t0" "${t0}"
  state_set "t0_recorded_at_utc" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  state_set "watermark_gte" "${watermark}"
  echo "Recorded T0 (watermark format)= ${t0}"
  echo "Delta lower bound (T0 - ${DELTA_MARGIN_MINUTES}m)= ${watermark}"

  # slices must be a query param on this cluster (body field "slices" -> HTTP 400)
  local qs="wait_for_completion=false"
  # Empty / 0 / off = no throttle (faster for small-medium indexes)
  if [[ -n "${REQUESTS_PER_SECOND:-}" && "${REQUESTS_PER_SECOND}" != "0" && "${REQUESTS_PER_SECOND}" != "off" ]]; then
    qs="${qs}&requests_per_second=${REQUESTS_PER_SECOND}"
  fi
  if [[ "${REINDEX_SLICES}" != "off" ]]; then
    qs="${qs}&slices=${REINDEX_SLICES}"
  fi

  local body
  body="$(jq -n \
    --arg src "${SOURCE_INDEX}" \
    --arg dest "${DEST_INDEX}" \
    --argjson size "${REINDEX_SIZE}" \
    '{
      source: { index: $src, size: $size },
      dest: { index: $dest, op_type: "create" },
      conflicts: "proceed"
    }')"

  echo "==> POST _reindex?${qs}"
  local resp task
  resp="$(os_request POST "/_reindex?${qs}" "${body}")"
  echo "${resp}" | pretty
  task="$(echo "${resp}" | jq -r '.task // empty')"
  if [[ -z "${task}" ]]; then
    echo "ERROR: no task id in response" >&2
    exit 1
  fi
  state_set "last_task" "${task}"
  state_set "last_task_kind" "full"
  echo "Saved task=${task} to ${STATE_FILE}"
}

cmd_reindex_delta() {
  local t0 watermark next_watermark round started_utc started_wm
  t0="$(state_get t0)"
  watermark="$(state_get watermark_gte)"
  if [[ -z "${t0}" || -z "${watermark}" ]]; then
    echo "ERROR: t0/watermark_gte missing in state. Run reindex-full first." >&2
    exit 1
  fi

  # Prefer explicit WATERMARK_GTE override for this round only
  if [[ -n "${WATERMARK_GTE:-}" ]]; then
    watermark="${WATERMARK_GTE}"
  fi

  round="$(state_get delta_round)"
  if [[ -z "${round}" ]]; then
    round=0
  fi
  round=$((round + 1))

  started_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  started_wm="$(utc_now_watermark_format)"

  # Advance watermark for the *next* round to (now - margin), unless disabled.
  # This round still uses the current watermark (overlap is intentional / safe).
  next_watermark="$(utc_minus_minutes_watermark_format "${DELTA_MARGIN_MINUTES}")"
  if [[ "${NO_ADVANCE_WATERMARK:-}" == "yes" ]]; then
    echo "NO_ADVANCE_WATERMARK=yes: leaving watermark_gte=${watermark} for next round"
    next_watermark="${watermark}"
  fi

  echo "Delta round #${round}: ${WATERMARK_FIELD} >= ${watermark}"
  echo "  t0=${t0}  margin=${DELTA_MARGIN_MINUTES}m"
  echo "  next_watermark_gte (for following round)= ${next_watermark}"

  # Sync wait avoids async task-poll overhead under write-block (final-delta default).
  local wait_comp="${REINDEX_WAIT_FOR_COMPLETION:-false}"
  local qs="wait_for_completion=${wait_comp}"
  if [[ "${REINDEX_SLICES}" != "off" ]]; then
    qs="${qs}&slices=${REINDEX_SLICES}"
  fi
  local body
  body="$(jq -n \
    --arg src "${SOURCE_INDEX}" \
    --arg dest "${DEST_INDEX}" \
    --arg field "${WATERMARK_FIELD}" \
    --arg gte "${watermark}" \
    --argjson size "${REINDEX_SIZE}" \
    '{
      source: {
        index: $src,
        size: $size,
        query: { range: { ($field): { gte: $gte } } }
      },
      dest: { index: $dest, op_type: "create" },
      conflicts: "proceed"
    }')"

  echo "==> POST _reindex?${qs} (delta)"
  local resp task took created total conflicts
  resp="$(os_request POST "/_reindex?${qs}" "${body}")"
  echo "${resp}" | pretty

  state_set "last_watermark_gte" "${watermark}"
  state_set "watermark_gte" "${next_watermark}"
  state_set "delta_round" "${round}"
  state_set "delta_started_at_utc" "${started_utc}"
  state_set "delta_started_wm" "${started_wm}"

  if [[ "${wait_comp}" == "true" ]]; then
    # Synchronous: response is the reindex result (no task id)
    took="$(echo "${resp}" | jq -r '.took // empty')"
    created="$(echo "${resp}" | jq -r '.created // 0')"
    total="$(echo "${resp}" | jq -r '.total // 0')"
    conflicts="$(echo "${resp}" | jq -r '.version_conflicts // 0')"
    state_set "last_task" ""
    state_set "last_task_kind" "delta-sync"
    state_set "last_took_ms" "${took:-0}"
    state_set "last_created" "${created}"
    state_set "last_total" "${total}"
    state_set "last_version_conflicts" "${conflicts}"
    echo "Sync delta done took_ms=${took:-0} created=${created} total=${total} conflicts=${conflicts}"
    return 0
  fi

  task="$(echo "${resp}" | jq -r '.task // empty')"
  if [[ -z "${task}" ]]; then
    echo "ERROR: no task id in response" >&2
    exit 1
  fi
  state_set "last_task" "${task}"
  state_set "last_task_kind" "delta"
  echo "Saved task=${task} round=${round} to ${STATE_FILE}"
}

# Tight delta after block-write: minimize scroll window, do not advance watermark.
# Lower bound = (last delta start - FINAL_DELTA_MARGIN_MINUTES), or WATERMARK_GTE, or watermark_gte.
cmd_final_delta() {
  local started_utc started_wm watermark state_wm

  if [[ -z "$(state_get t0)" ]]; then
    echo "ERROR: t0 missing. Run reindex-full (+ catchup) first." >&2
    exit 1
  fi

  # Soft check: source should already be write-blocked
  local write_block
  write_block="$(
    os_request GET "/${SOURCE_INDEX}/_settings/index.blocks.write" 2>/dev/null \
      | jq -r --arg i "${SOURCE_INDEX}" '.[$i].settings.index.blocks.write // empty' \
      || true
  )"
  if [[ "${write_block}" != "true" ]]; then
    echo "WARN: index.blocks.write is not true on ${SOURCE_INDEX} (got: '${write_block:-unset}')." >&2
    echo "  Run block-write before final-delta to avoid racing new writes." >&2
  fi

  if [[ -n "${WATERMARK_GTE:-}" ]]; then
    watermark="${WATERMARK_GTE}"
    echo "final-delta: using WATERMARK_GTE override=${watermark}"
  else
    started_utc="$(state_get delta_started_at_utc)"
    started_wm="$(state_get delta_started_wm)"
    # Compat with older state files
    if [[ -z "${started_wm}" ]]; then
      started_wm="$(state_get delta_started_lambda)"
    fi
    if [[ -n "${started_utc}" ]]; then
      watermark="$(utc_iso_minus_minutes_watermark_format "${started_utc}" "${FINAL_DELTA_MARGIN_MINUTES}")"
      echo "final-delta: last delta started ${started_utc} → gte=${watermark} (margin=${FINAL_DELTA_MARGIN_MINUTES}m)"
    elif [[ -n "${started_wm}" ]]; then
      # Fallback: treat stored watermark string as "now" base via date -d if possible
      if date -u -d "${started_wm} - ${FINAL_DELTA_MARGIN_MINUTES} minutes" '+%Y/%m/%d %H:%M:%S' >/dev/null 2>&1; then
        watermark="$(date -u -d "${started_wm} - ${FINAL_DELTA_MARGIN_MINUTES} minutes" '+%Y/%m/%d %H:%M:%S')"
      else
        watermark="${started_wm}"
      fi
      echo "final-delta: from delta_started_wm → gte=${watermark}"
    else
      state_wm="$(state_get watermark_gte)"
      if [[ -z "${state_wm}" ]]; then
        echo "ERROR: no delta_started_* / watermark_gte. Run catchup or reindex-delta first." >&2
        exit 1
      fi
      watermark="${state_wm}"
      echo "final-delta: fallback to watermark_gte=${watermark} (no prior delta start recorded)"
    fi
  fi

  echo "==> final-delta (tight, NO_ADVANCE_WATERMARK)"
  # Default sync under write-block to cut task-poll latency on empty/tiny deltas.
  local sync="${FINAL_DELTA_SYNC:-yes}"
  if [[ "${sync}" == "yes" ]]; then
    WATERMARK_GTE="${watermark}" NO_ADVANCE_WATERMARK=yes \
      REINDEX_WAIT_FOR_COMPLETION=true cmd_reindex_delta
    state_set "last_task_kind" "final-delta-sync"
  else
    WATERMARK_GTE="${watermark}" NO_ADVANCE_WATERMARK=yes cmd_reindex_delta
    state_set "last_task_kind" "final-delta"
  fi
}

# Count source docs that would be included in the next delta (current watermark_gte).
cmd_delta_estimate() {
  local watermark
  watermark="${WATERMARK_GTE:-$(state_get watermark_gte)}"
  if [[ -z "${watermark}" ]]; then
    echo "ERROR: watermark_gte missing. Run reindex-full first." >&2
    exit 1
  fi
  echo "==> Estimate docs with ${WATERMARK_FIELD} >= ${watermark}"
  local body resp count
  body="$(jq -n \
    --arg field "${WATERMARK_FIELD}" \
    --arg gte "${watermark}" \
    '{ query: { range: { ($field): { gte: $gte } } } }')"
  resp="$(os_request POST "/${SOURCE_INDEX}/_count" "${body}")"
  count="$(echo "${resp}" | jq -r '.count')"
  echo "${resp}" | pretty
  state_set "last_delta_estimate" "${count}"
  state_set "last_delta_estimate_gte" "${watermark}"
  echo "estimated_docs=${count} (next reindex-delta lower bound=${watermark})"
}

cmd_wait_task() {
  local task="${1:-$(state_get last_task)}"
  if [[ -z "${task}" ]]; then
    echo "ERROR: no task id (pass as arg or run reindex-* first)" >&2
    exit 1
  fi
  echo "==> Waiting for task ${task}"
  local zero_streak=0 last_logged_created=-1 last_total_hint=0 poll=0
  while true; do
    local resp completed total_hint created_hint sleep_s
    resp="$(os_request GET "/_tasks/${task}?wait_for_completion=false")"
    completed="$(echo "${resp}" | jq -r '.completed')"
    if [[ "${completed}" == "true" ]]; then
      echo "${resp}" | jq '{
        completed,
        error: .error,
        response: {
          took: .response.took,
          total: .response.total,
          updated: .response.updated,
          created: .response.created,
          version_conflicts: .response.version_conflicts,
          failures: .response.failures
        }
      }'
      local failures took created total conflicts
      failures="$(echo "${resp}" | jq '.response.failures | length')"
      took="$(echo "${resp}" | jq -r '.response.took // empty')"
      created="$(echo "${resp}" | jq -r '.response.created // 0')"
      total="$(echo "${resp}" | jq -r '.response.total // 0')"
      conflicts="$(echo "${resp}" | jq -r '.response.version_conflicts // 0')"
      if [[ -n "${took}" && "${took}" != "null" ]]; then
        state_set "last_took_ms" "${took}"
        state_set "last_created" "${created}"
        state_set "last_total" "${total}"
        state_set "last_version_conflicts" "${conflicts}"
        echo "Recorded last_took_ms=${took} last_created=${created} last_total=${total} conflicts=${conflicts}"
      fi
      if [[ "${failures}" != "0" && "${failures}" != "null" ]]; then
        echo "WARN: reindex reported failures" >&2
      fi
      if echo "${resp}" | jq -e '.error != null' >/dev/null 2>&1; then
        echo "ERROR: task failed" >&2
        exit 1
      fi
      break
    fi

    total_hint="$(echo "${resp}" | jq -r '.task.status.total // 0')"
    created_hint="$(echo "${resp}" | jq -r '.task.status.created // 0')"
    poll=$((poll + 1))

    # Adaptive poll: slices=auto often sits at total=0 for a while — back off & reduce log spam
    if [[ "${total_hint}" -eq 0 ]]; then
      zero_streak=$((zero_streak + 1))
      if [[ "${zero_streak}" -le 3 ]]; then
        sleep_s=0.5
      elif [[ "${zero_streak}" -le 10 ]]; then
        sleep_s=2
      else
        sleep_s=5
      fi
      # slices=auto parent often stays total=0 for minutes — log sparsely on long waits
      local idle_every=3
      if [[ "${zero_streak}" -gt 30 ]]; then
        idle_every=12
      elif [[ "${zero_streak}" -gt 12 ]]; then
        idle_every=6
      fi
      if [[ "${zero_streak}" -eq 1 || $((zero_streak % idle_every)) -eq 0 ]]; then
        echo "  ... starting/idle (poll=${poll}, total=0, sleep=${sleep_s}s — slices parent may lag)"
      fi
    else
      zero_streak=0
      if [[ "${total_hint}" -gt 5000 ]]; then
        sleep_s=5
      elif [[ "${total_hint}" -gt 500 ]]; then
        sleep_s=1
      else
        sleep_s=0.25
      fi
      # large jobs: log ~every 5% (or 100k docs), not every poll
      # slices=auto parent total grows as children report — avoid fake "100%"
      local should_log=0 pct step total_growing=0
      if [[ "${total_hint}" -gt "${last_total_hint}" && "${last_total_hint}" -gt 0 ]]; then
        total_growing=1
      fi
      last_total_hint="${total_hint}"
      if [[ "${total_hint}" -le 500 ]]; then
        should_log=1
      elif [[ "${created_hint}" != "${last_logged_created}" ]]; then
        if [[ "${total_hint}" -gt 100000 ]]; then
          step=$((total_hint / 20))
          [[ "${step}" -lt 100000 ]] && step=100000
          if [[ "${last_logged_created}" -lt 0 || $((created_hint - last_logged_created)) -ge "${step}" ]]; then
            should_log=1
          fi
        else
          should_log=1
        fi
      fi
      if [[ "${should_log}" -eq 1 ]]; then
        if [[ "${total_growing}" -eq 1 ]]; then
          echo "  ... running (created=${created_hint}, reported_total=${total_hint} growing)"
        elif [[ "${total_hint}" -gt 0 ]]; then
          pct=$((created_hint * 100 / total_hint))
          echo "  ... running (${pct}% created=${created_hint}/${total_hint})"
        else
          echo "  ... running (total=${total_hint}, created=${created_hint})"
        fi
        last_logged_created="${created_hint}"
      fi
    fi
    sleep "${sleep_s}"
  done
}

# Multi-round delta catch-up until created is drained (preferred) or took is small
# after a drain attempt. Does NOT block-write; use fast-switch afterwards.
cmd_catchup() {
  local target_ms max_rounds stop_created took created
  target_ms=$((DELTA_TARGET_SECONDS * 1000))
  max_rounds="${DELTA_MAX_ROUNDS}"
  stop_created="${DELTA_STOP_CREATED}"

  if [[ -z "$(state_get watermark_gte)" ]]; then
    echo "ERROR: watermark_gte missing. Run reindex-full (+ wait-task) first." >&2
    exit 1
  fi

  echo "==> Catch-up loop"
  echo "  prefer: created <= ${stop_created}"
  echo "  also ok: took <= ${DELTA_TARGET_SECONDS}s after draining (created>${stop_created} → another round)"
  echo "  max rounds: ${max_rounds}"
  echo

  local i
  for ((i = 1; i <= max_rounds; i++)); do
    echo "-------- catchup iteration ${i}/${max_rounds} --------"
    cmd_delta_estimate
    cmd_reindex_delta
    cmd_wait_task

    took="$(state_get last_took_ms)"
    created="$(state_get last_created)"
    if [[ -z "${took}" ]]; then
      echo "ERROR: last_took_ms missing after wait-task" >&2
      exit 1
    fi

    echo "Round result: took_ms=${took} created=${created} (target_ms=${target_ms})"

    if [[ "${created}" -le "${stop_created}" ]]; then
      echo "STOP: created=${created} <= DELTA_STOP_CREATED=${stop_created} (caught up)"
      state_set "catchup_ok" "yes"
      state_set "catchup_reason" "created_le_stop"
      return 0
    fi
    if [[ "${took}" -le "${target_ms}" ]]; then
      # Fast enough but still copied docs — drain one more round when possible
      if [[ "${i}" -lt "${max_rounds}" ]]; then
        echo "took ok but created=${created} > ${stop_created}; drain another round..."
        echo
        continue
      fi
      echo "STOP: took_ms=${took} <= target_ms=${target_ms} (max rounds; ready for fast-switch)"
      state_set "catchup_ok" "yes"
      state_set "catchup_reason" "took_le_target"
      return 0
    fi
    echo "Continue: still above target; starting next delta round..."
    echo
  done

  echo "WARN: reached DELTA_MAX_ROUNDS=${max_rounds} without meeting target." >&2
  echo "  last_took_ms=$(state_get last_took_ms) last_created=$(state_get last_created)" >&2
  echo "  Options: raise DELTA_MAX_ROUNDS, lower write load, or proceed knowing final delta may be long." >&2
  state_set "catchup_ok" "no"
  state_set "catchup_reason" "max_rounds"
  return 1
}

cmd_block_write() {
  echo "==> PUT /${SOURCE_INDEX}/_settings blocks.write=true"
  os_request PUT "/${SOURCE_INDEX}/_settings" \
    '{"index":{"blocks":{"write":true}}}' | pretty
  state_set "write_block_started_ms" "$(now_ms)"
  state_set "write_block_started_utc" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

cmd_unblock_write() {
  echo "==> PUT /${SOURCE_INDEX}/_settings blocks.write=false"
  os_request PUT "/${SOURCE_INDEX}/_settings" \
    '{"index":{"blocks":{"write":false}}}' | pretty
  state_set "write_block_cleared_utc" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

# Returns 0 if an in-progress snapshot touches $1; 1 if clear; 2 if status unknown/timeout.
snapshot_touches_index() {
  local idx="$1"
  local tmp http_code resp
  local timeout_s="${SNAPSHOT_STATUS_TIMEOUT_SECONDS:-30}"
  tmp="$(mktemp)"
  http_code="$(
    curl "${curl_opts[@]}" "${auth_args[@]}" \
      --max-time "${timeout_s}" \
      -o "${tmp}" -w "%{http_code}" \
      -X GET "${OS_BASE_URL}/_snapshot/_status" 2>/dev/null || echo "000"
  )"
  resp="$(cat "${tmp}" 2>/dev/null || true)"
  rm -f "${tmp}"
  if [[ "${http_code}" != "200" ]]; then
    echo "WARN: GET /_snapshot/_status HTTP ${http_code} (treat as unknown)" >&2
    return 2
  fi
  if echo "${resp}" | jq -e --arg i "${idx}" '
    [.snapshots[]? | select(
      ((.indices | type) == "object" and (.indices | has($i)))
      or ((.indices | type) == "array" and (.indices | index($i) != null))
    )] | length > 0
  ' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Wait until SOURCE_INDEX is not snapshotted (before write-block).
# SNAPSHOT_PRECHECK=no to skip. Unknown status → warn and proceed (or fail if STRICT).
wait_snapshots_clear_before_lock() {
  local idx="${1:-${SOURCE_INDEX}}"
  local max_s poll_s elapsed=0 rc
  if [[ "${SNAPSHOT_PRECHECK:-yes}" != "yes" ]]; then
    echo "SNAPSHOT_PRECHECK=${SNAPSHOT_PRECHECK:-} — skip pre-lock snapshot wait"
    return 0
  fi
  max_s="${SNAPSHOT_WAIT_BEFORE_LOCK_SECONDS:-300}"
  poll_s="${SNAPSHOT_POLL_SECONDS:-15}"
  echo "==> Pre-lock snapshot check for ${idx} (max wait ${max_s}s)"
  while true; do
    if snapshot_touches_index "${idx}"; then
      rc=0
    else
      rc=$?
    fi
    if [[ "${rc}" -eq 1 ]]; then
      echo "  no in-progress snapshot touching ${idx}"
      state_set "snapshot_precheck" "clear"
      return 0
    fi
    if [[ "${rc}" -eq 2 ]]; then
      if [[ "${SNAPSHOT_PRECHECK_STRICT:-no}" == "yes" ]]; then
        echo "ERROR: snapshot status unknown and SNAPSHOT_PRECHECK_STRICT=yes" >&2
        state_set "snapshot_precheck" "unknown_strict_fail"
        exit 1
      fi
      echo "  WARN: snapshot status unknown — proceed (set SNAPSHOT_PRECHECK_STRICT=yes to refuse)"
      state_set "snapshot_precheck" "unknown_proceed"
      return 0
    fi
    if [[ "${elapsed}" -ge "${max_s}" ]]; then
      echo "ERROR: still snapshotted after ${max_s}s — refuse write-block (retry later)" >&2
      echo "  Re-run: CONFIRM=yes $0 fast-switch   (or wait-snapshots then fast-switch)" >&2
      state_set "snapshot_precheck" "timeout"
      exit 1
    fi
    echo "  ${idx} is in an in-progress snapshot — wait ${poll_s}s (${elapsed}/${max_s}s)"
    sleep "${poll_s}"
    elapsed=$((elapsed + poll_s))
  done
}

cmd_wait_snapshots() {
  wait_snapshots_clear_before_lock "${SOURCE_INDEX}"
}

# If write-block has been held too long, unblock and abort (avoid long producer 403).
abort_if_write_block_budget_exceeded() {
  local started now elapsed max_s max_ms
  max_s="${WRITE_BLOCK_MAX_SECONDS:-120}"
  [[ "${max_s}" == "0" || "${max_s}" == "off" ]] && return 0
  started="$(state_get write_block_started_ms)"
  if [[ -z "${started}" ]]; then
    return 0
  fi
  now="$(now_ms)"
  elapsed=$((now - started))
  max_ms=$((max_s * 1000))
  if [[ "${elapsed}" -lt "${max_ms}" ]]; then
    return 0
  fi
  echo "ERROR: write-block held ${elapsed}ms > WRITE_BLOCK_MAX_SECONDS=${max_s}s — abort cutover" >&2
  echo "  Unblocking source so producers can resume; re-run catchup + fast-switch when idle." >&2
  cmd_unblock_write || true
  state_set "fast_switch_aborted" "write_block_budget"
  state_set "fast_switch_abort_elapsed_ms" "${elapsed}"
  exit 1
}

cmd_compare() {
  echo "==> Compare counts"
  local sc dc diff
  sc="$(os_request GET "/${SOURCE_INDEX}/_count" | jq -r '.count')"
  dc="$(os_request GET "/${DEST_INDEX}/_count" | jq -r '.count')"
  state_set "last_compare_source" "${sc}"
  state_set "last_compare_dest" "${dc}"
  diff=$((sc - dc))
  echo "source(${SOURCE_INDEX})=${sc}"
  echo "dest(${DEST_INDEX})=${dc}"
  echo "diff(source-dest)=${diff}"
  if [[ "${diff}" -ne 0 ]]; then
    echo "Note: counts differ — continue catchup or expect final-delta under write block to close the gap."
  fi
}

cmd_cutover() {
  if [[ "${CONFIRM:-}" != "yes" ]]; then
    echo "DANGER: This will DELETE /${SOURCE_INDEX} then create alias ${ALIAS_NAME} -> ${DEST_INDEX}" >&2
    echo "Re-run with CONFIRM=yes to proceed:" >&2
    echo "  CONFIRM=yes $0 cutover" >&2
    exit 1
  fi
  if [[ "${ALIAS_NAME}" != "${SOURCE_INDEX}" ]]; then
    echo "WARN: ALIAS_NAME=${ALIAS_NAME} != SOURCE_INDEX=${SOURCE_INDEX}" >&2
    echo "Producers typically write to physical names like SOURCE_INDEX; alias should usually match." >&2
  fi

  # Atomic: remove_index + add alias in one _aliases call.
  # Avoids DELETE→gap→producer auto-recreates physical index→alias name conflict.
  local body attempt max_attempts sleep_s resp
  max_attempts="${CUTOVER_SNAPSHOT_RETRIES:-36}"
  sleep_s="${CUTOVER_SNAPSHOT_SLEEP_SECONDS:-10}"
  body="$(jq -n \
    --arg src "${SOURCE_INDEX}" \
    --arg dest "${DEST_INDEX}" \
    --arg alias "${ALIAS_NAME}" \
    '{
      actions: [
        { remove_index: { index: $src } },
        { add: { index: $dest, alias: $alias } }
      ]
    }')"

  echo "==> POST /_aliases (remove_index ${SOURCE_INDEX} + alias ${ALIAS_NAME} → ${DEST_INDEX})"
  attempt=1
  while true; do
    # Capture body even on HTTP error (os_request returns 1 but still prints JSON).
    if resp="$(os_request POST "/_aliases" "${body}")"; then
      echo "${resp}" | pretty
      break
    fi
    echo "${resp}" | pretty || true
    if echo "${resp}" | jq -e '
      (.error.type // "") == "snapshot_in_progress_exception"
      or ((.error.reason // "") | test("snapshotted|snapshot"; "i"))
    ' >/dev/null 2>&1; then
      # Prefer short 403: abandon + unblock rather than wait indefinitely under lock
      abort_if_write_block_budget_exceeded
      if [[ "${attempt}" -ge "${max_attempts}" ]]; then
        echo "ERROR: cutover still blocked by snapshot after ${max_attempts} attempts — unblocking" >&2
        cmd_unblock_write || true
        state_set "fast_switch_aborted" "snapshot_retries_exhausted"
        exit 1
      fi
      echo "  snapshot in progress — retry ${attempt}/${max_attempts} in ${sleep_s}s (write-block budget=${WRITE_BLOCK_MAX_SECONDS:-120}s)" >&2
      sleep "${sleep_s}"
      attempt=$((attempt + 1))
      continue
    fi
    echo "ERROR: cutover _aliases failed" >&2
    exit 1
  done

  if [[ "${SKIP_ALIAS_VERIFY:-}" == "yes" ]]; then
    echo "==> Verify alias skipped (SKIP_ALIAS_VERIFY=yes)"
  else
    echo "==> Verify alias"
    os_request GET "/_alias/${ALIAS_NAME}" | pretty
  fi
  state_set "cutover_at_utc" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Cutover done. Producers targeting '${ALIAS_NAME}' now hit '${DEST_INDEX}'."
}

# After catchup: minimize 403 window in one process.
#   CONFIRM=yes $0 fast-switch
# Steps: wait-snapshots → optional compare → block-write → final-delta → wait-task → cutover
cmd_fast_switch() {
  if [[ "${CONFIRM:-}" != "yes" ]]; then
    echo "DANGER: fast-switch will block-write, final-delta, remove_index+alias." >&2
    echo "Pre-req: reindex-full + wait-task + catchup already done." >&2
    echo "Re-run with CONFIRM=yes:" >&2
    echo "  CONFIRM=yes $0 fast-switch" >&2
    exit 1
  fi

  local t0 t1 t2 t3 t4 t5 sc dc
  echo "==> fast-switch (single process, timed)"
  echo "  SOURCE=${SOURCE_INDEX} DEST=${DEST_INDEX} ALIAS=${ALIAS_NAME}"
  echo "  WRITE_BLOCK_MAX_SECONDS=${WRITE_BLOCK_MAX_SECONDS:-120} SNAPSHOT_WAIT_BEFORE_LOCK_SECONDS=${SNAPSHOT_WAIT_BEFORE_LOCK_SECONDS:-300}"

  # Do NOT lock while source is being snapshotted (avoids long 403 waiting for DELETE).
  wait_snapshots_clear_before_lock "${SOURCE_INDEX}"

  if [[ "${SKIP_COMPARE:-}" != "yes" ]]; then
    local diff max_diff="${COMPARE_MAX_DIFF:-100}"
    t0="$(now_ms)"
    cmd_compare
    t1="$(now_ms)"
    sc="$(state_get last_compare_source)"
    dc="$(state_get last_compare_dest)"
    diff=$((sc - dc))
    # Live writers: source often 1–N ahead until write-block; final-delta closes the gap.
    # Refuse only if dest ahead (unexpected) or gap larger than COMPARE_MAX_DIFF.
    if [[ "${diff}" -lt 0 ]]; then
      echo "ERROR: dest ahead of source (diff=${diff}); refuse fast-switch." >&2
      exit 1
    fi
    if [[ "${diff}" -gt "${max_diff}" ]]; then
      echo "ERROR: count gap ${diff} > COMPARE_MAX_DIFF=${max_diff}; refuse fast-switch. Re-run catchup." >&2
      exit 1
    fi
    if [[ "${diff}" -gt 0 ]]; then
      echo "  compare gap=${diff} (<=${max_diff}) — proceed; final-delta under write-block will drain"
    fi
    echo "  compare_ms=$((t1 - t0))"
  else
    echo "  SKIP_COMPARE=yes"
  fi

  # Re-check immediately before lock (snapshot may have started during compare).
  wait_snapshots_clear_before_lock "${SOURCE_INDEX}"

  t1="$(now_ms)"
  cmd_block_write
  t2="$(now_ms)"
  echo "  block_write_ms=$((t2 - t1))"

  cmd_final_delta
  t3="$(now_ms)"
  echo "  final_delta_submit_ms=$((t3 - t2))"

  if [[ "$(state_get last_task_kind)" == "final-delta-sync" || -z "$(state_get last_task)" ]]; then
    t4="$(now_ms)"
    echo "  final_delta_wait_ms=$((t4 - t3)) (sync) last_took_ms=$(state_get last_took_ms) created=$(state_get last_created)"
  else
    cmd_wait_task
    t4="$(now_ms)"
    echo "  final_delta_wait_ms=$((t4 - t3)) last_took_ms=$(state_get last_took_ms) created=$(state_get last_created)"
  fi

  abort_if_write_block_budget_exceeded

  CONFIRM=yes cmd_cutover
  t5="$(now_ms)"
  echo "  cutover_ms=$((t5 - t4))"
  echo
  echo "==> fast-switch DONE"
  echo "  write_block_window_ms=$((t5 - t2))  (block-write → cutover done; producers see 403 here)"
  echo "  reader_cutover_ms=$((t5 - t4))      (remove_index → alias; brief reader gap)"
  state_set "fast_switch_block_window_ms" "$((t5 - t2))"
  state_set "fast_switch_cutover_ms" "$((t5 - t4))"
}

# Soft-tune during migrate (disable with MIGRATE_AUTO_TUNE=no).
# Tiers (docs):
#   small  < SMALL (250k): RPS off + slices off
#   mid    < MID   (500k): RPS off, keep slices (multi-shard parallel)
#   large  >= MID:         RPS off (avoid docs/RPS floor); slices off if 1 primary shard
#                          set MIGRATE_LARGE_KEEP_RPS=yes to keep env REQUESTS_PER_SECOND
migrate_auto_tune() {
  local docs shards
  local small="${MIGRATE_AUTO_TUNE_SMALL_DOCS:-${MIGRATE_AUTO_TUNE_MAX_DOCS:-250000}}"
  local mid="${MIGRATE_AUTO_TUNE_MID_DOCS:-500000}"
  if [[ "${MIGRATE_AUTO_TUNE:-yes}" != "yes" ]]; then
    echo "MIGRATE_AUTO_TUNE=${MIGRATE_AUTO_TUNE:-} (skipped)"
    state_set "migrate_auto_tune" "skipped"
    return 0
  fi
  docs="$(os_request GET "/${SOURCE_INDEX}/_count" | jq -r '.count')"
  shards="$(os_request GET "/${SOURCE_INDEX}/_settings" | jq -r --arg i "${SOURCE_INDEX}" '
    .[$i].settings.index.number_of_shards // .[keys_unsorted[0]].settings.index.number_of_shards // "1"
  ')"
  echo "auto-tune: source_docs=${docs} shards=${shards} small<${small} mid<${mid}"
  state_set "migrate_source_docs" "${docs}"
  state_set "migrate_source_shards" "${shards}"

  # Drop throttle floor unless large + KEEP_RPS (protect busy prod clusters)
  if [[ "${docs}" -ge "${mid}" && "${MIGRATE_LARGE_KEEP_RPS:-}" == "yes" ]]; then
    echo "auto-tune: large + MIGRATE_LARGE_KEEP_RPS=yes — keep REQUESTS_PER_SECOND=${REQUESTS_PER_SECOND:-} REINDEX_SLICES=${REINDEX_SLICES}"
    state_set "migrate_auto_tune" "large_keep_rps"
    state_set "migrate_rps" "${REQUESTS_PER_SECOND:-}"
    state_set "migrate_slices" "${REINDEX_SLICES}"
    return 0
  fi

  if [[ -n "${REQUESTS_PER_SECOND:-}" && "${REQUESTS_PER_SECOND}" != "0" && "${REQUESTS_PER_SECOND}" != "off" ]]; then
    echo "auto-tune: REQUESTS_PER_SECOND ${REQUESTS_PER_SECOND} → off"
    REQUESTS_PER_SECOND=off
  fi

  if [[ "${docs}" -ge "${mid}" ]]; then
    # 1 shard: slices=auto adds no parallelism and muddies parent task progress
    if [[ "${shards}" == "1" && "${REINDEX_SLICES}" == "auto" ]]; then
      echo "auto-tune: REINDEX_SLICES auto → off (large, 1 shard)"
      REINDEX_SLICES=off
    fi
    # Larger scroll batches help long single-shard full reindexes (override with REINDEX_SIZE=)
    if [[ "${REINDEX_SIZE}" == "1000" ]]; then
      local big_size="${MIGRATE_LARGE_REINDEX_SIZE:-2500}"
      echo "auto-tune: REINDEX_SIZE 1000 → ${big_size} (large index)"
      REINDEX_SIZE="${big_size}"
    fi
    echo "auto-tune: large index — RPS=off REINDEX_SLICES=${REINDEX_SLICES} REINDEX_SIZE=${REINDEX_SIZE}"
    state_set "migrate_auto_tune" "large"
  elif [[ "${docs}" -ge "${small}" ]]; then
    echo "auto-tune: mid index — RPS=off keep REINDEX_SLICES=${REINDEX_SLICES}"
    state_set "migrate_auto_tune" "mid"
  else
    if [[ "${REINDEX_SLICES}" == "auto" ]]; then
      echo "auto-tune: REINDEX_SLICES auto → off (small index)"
      REINDEX_SLICES=off
    fi
    state_set "migrate_auto_tune" "small"
  fi
  state_set "migrate_rps" "${REQUESTS_PER_SECOND:-}"
  state_set "migrate_slices" "${REINDEX_SLICES}"
}

# One-shot: dump → create → full → wait → catchup → fast-switch (same process after load).
#   CONFIRM=yes $0 migrate
cmd_migrate() {
  if [[ "${CONFIRM:-}" != "yes" ]]; then
    echo "DANGER: migrate runs full reindex + catchup + fast-switch (DELETE source)." >&2
    echo "Re-run with CONFIRM=yes:" >&2
    echo "  CONFIRM=yes $0 migrate" >&2
    exit 1
  fi

  local tw0 tw1
  tw0="$(now_ms)"
  echo "==> migrate ${SOURCE_INDEX} → ${DEST_INDEX} (alias ${ALIAS_NAME})"
  # Quiet noisy manual hints; skip extra alias GET inside cutover (still timed)
  QUIET=yes
  SKIP_ALIAS_VERIFY="${SKIP_ALIAS_VERIFY:-yes}"
  cmd_inspect
  migrate_auto_tune
  cmd_dump_source
  cmd_create_dest
  cmd_reindex_full
  cmd_wait_task
  cmd_catchup
  CONFIRM=yes SKIP_ALIAS_VERIFY="${SKIP_ALIAS_VERIFY}" cmd_fast_switch
  tw1="$(now_ms)"
  echo "==> migrate DONE wall_ms=$((tw1 - tw0))"
  echo "  settings used: RPS=${REQUESTS_PER_SECOND:-} slices=${REINDEX_SLICES}"
  state_set "migrate_wall_ms" "$((tw1 - tw0))"
}

cmd_status() {
  echo "OS_BASE_URL=${OS_BASE_URL}"
  echo "SOURCE_INDEX=${SOURCE_INDEX}"
  echo "DEST_SUFFIX=${DEST_SUFFIX}"
  echo "DEST_INDEX=${DEST_INDEX}"
  echo "ALIAS_NAME=${ALIAS_NAME}"
  echo "WATERMARK_FIELD=${WATERMARK_FIELD}"
  echo "DELTA_MARGIN_MINUTES=${DELTA_MARGIN_MINUTES}"
  echo "FINAL_DELTA_MARGIN_MINUTES=${FINAL_DELTA_MARGIN_MINUTES}"
  echo "DELTA_TARGET_SECONDS=${DELTA_TARGET_SECONDS}"
  echo "DELTA_MAX_ROUNDS=${DELTA_MAX_ROUNDS}"
  echo "DELTA_STOP_CREATED=${DELTA_STOP_CREATED}"
  echo "STATE_FILE=${STATE_FILE}"
  if [[ -f "${STATE_FILE}" ]]; then
    echo "--- state ---"
    jq . "${STATE_FILE}"
  else
    echo "(no state file yet)"
  fi
}

cmd_help() {
  cat <<EOF
Usage: $0 <command>

Config (outside script):
  cp "$(dirname "$0")/migration.env.example" "$(dirname "$0")/migration.env"
  # set OS_BASE_URL / OS_USERNAME / OS_PASSWORD / SOURCE_INDEX
  # DEST defaults to \${SOURCE_INDEX}_reidx; ALIAS defaults to SOURCE_INDEX
  MIGRATION_ENV=/path/to/migration.env $0 ping

Commands:
  ping            Cluster hello (GET /)
  inspect         Source/dest counts and basic settings
  dump-source     Save source index + generate dest create body
  create-dest     PUT new index from create body
  reindex-full    Async full reindex (records T0 + watermark); op_type=create
  reindex-delta   Async delta by ${WATERMARK_FIELD:-EventTimestamp} >= watermark;
                  advances watermark to (now - margin) for the next round
  delta-estimate  Count source docs matching current watermark (preview next delta)
  catchup         Drain deltas: prefer created<=0; if took ok but created>0, another round
  final-delta     After block-write: tight gte (last delta start - FINAL_DELTA_MARGIN),
                  does not advance watermark (minimize 403 window)
  fast-switch     Timed: compare → block-write → final-delta → wait → cutover
                  (CONFIRM=yes). Use after catchup for second-level cutover.
  migrate         One-shot: inspect→dump→create→full→wait→catchup→fast-switch
                  (CONFIRM=yes). No local backup.
  wait-task [id]  Poll _tasks until completed; records last_took_ms / created
  block-write     index.blocks.write=true on source
  unblock-write   index.blocks.write=false on source
  compare         Print source vs dest _count
  cutover         Atomic remove_index + alias (CONFIRM=yes; snapshot-aware)
  wait-snapshots  Wait until SOURCE is not in an in-progress snapshot
  status          Show env targets + state file
  help            This message

Typical:
  CONFIRM=yes $0 migrate

Optional overrides (CLI exports beat migration.env):
  WATERMARK_GTE='2026/10/14 08:00:00'   force this delta lower bound
  NO_ADVANCE_WATERMARK=yes              do not bump watermark after delta
  REQUESTS_PER_SECOND=off               disable full-reindex throttle (or 0 / empty)
  REINDEX_SLICES=off                    clearer progress vs slices=auto
  MIGRATE_AUTO_TUNE=no                  disable migrate auto RPS/slices tuning
  MIGRATE_AUTO_TUNE_SMALL_DOCS=250000   docs < this → RPS off + slices off
  MIGRATE_AUTO_TUNE_MID_DOCS=500000     docs < this → RPS off, keep slices
  MIGRATE_AUTO_TUNE_MAX_DOCS=250000     alias for SMALL_DOCS (compat)
  MIGRATE_LARGE_KEEP_RPS=yes            large: keep env REQUESTS_PER_SECOND (throttle)
  DELTA_TARGET_SECONDS=60               catchup took threshold (seconds)
  DELTA_MAX_ROUNDS=10                   catchup max iterations
  DELTA_STOP_CREATED=0                  stop when created <= this
  FINAL_DELTA_MARGIN_MINUTES=1          final-delta safety margin (keep small)
  SKIP_COMPARE=yes                      skip pre-lock compare inside fast-switch
  COMPARE_MAX_DIFF=100                  allow source-dest gap before lock (final-delta drains)
  CUTOVER_SNAPSHOT_RETRIES=36           retry _aliases if snapshot_in_progress
  CUTOVER_SNAPSHOT_SLEEP_SECONDS=10     sleep between snapshot retries
  SNAPSHOT_PRECHECK=yes                 wait for clear snapshots before write-block
  SNAPSHOT_WAIT_BEFORE_LOCK_SECONDS=300 max wait before refusing lock
  SNAPSHOT_POLL_SECONDS=15              poll interval while waiting
  SNAPSHOT_STATUS_TIMEOUT_SECONDS=30    curl timeout for GET _snapshot/_status
  SNAPSHOT_PRECHECK_STRICT=no           yes = refuse if status API unknown
  WRITE_BLOCK_MAX_SECONDS=120           under lock: abort+unblock if exceeded (0=off)
  FINAL_DELTA_SYNC=yes                  sync wait_for_completion under write-block (default)
  MIGRATE_LARGE_REINDEX_SIZE=2500       auto bump from 1000 on large migrate
  SKIP_ALIAS_VERIFY=yes                 skip GET _alias after cutover (migrate default)
  QUIET=yes                             less dump-source chatter
  CONFIRM=yes                           required for cutover / fast-switch / migrate
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  shift || true

  case "${cmd}" in
    help|-h|--help)
      cmd_help
      exit 0
      ;;
  esac

  require_cmds
  load_env
  init_paths
  setup_curl

  case "${cmd}" in
    ping)           cmd_ping ;;
    inspect)        cmd_inspect ;;
    dump-source)    cmd_dump_source ;;
    create-dest)    cmd_create_dest ;;
    reindex-full)   cmd_reindex_full ;;
    reindex-delta)  cmd_reindex_delta ;;
    delta-estimate) cmd_delta_estimate ;;
    catchup)        cmd_catchup ;;
    final-delta)    cmd_final_delta ;;
    fast-switch)    cmd_fast_switch ;;
    migrate)        cmd_migrate ;;
    wait-task)      cmd_wait_task "${1:-}" ;;
    block-write)    cmd_block_write ;;
    unblock-write)  cmd_unblock_write ;;
    compare)        cmd_compare ;;
    cutover)        cmd_cutover ;;
    wait-snapshots) cmd_wait_snapshots ;;
    status)         cmd_status ;;
    *)
      echo "Unknown command: ${cmd}" >&2
      cmd_help >&2
      exit 1
      ;;
  esac
}

main "$@"

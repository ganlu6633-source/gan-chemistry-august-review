import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

import {
  END_DATE,
  GRADE_SCHEDULES,
  PERSONAL_RECOVERY_DAY_INDEXES,
  START_DATE,
  scheduleDates,
  validateScheduleSpec,
} from './review-schedule-20260822-20260929.mjs'

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..')
export const MIGRATION_PATH = path.join(
  REPO_ROOT,
  'supabase',
  'candidates',
  '20260821235500_individualize_review_plans_through_september.sql',
)

const BEGIN_MARKER = '-- GENERATED_GRADE_SCHEDULE_BEGIN'
const END_MARKER = '-- GENERATED_GRADE_SCHEDULE_END'

function quoteSql(value) {
  return `'${String(value).replaceAll("'", "''")}'`
}

function chunk(values, size) {
  return Array.from({ length: Math.ceil(values.length / size) }, (_, index) =>
    values.slice(index * size, (index + 1) * size))
}

function renderGradeInsert(gradeBand, skills) {
  const arrayRows = chunk(skills, 5)
    .map((row) => `  ${row.map(quoteSql).join(',')}`)
    .join(',\n')
  return `insert into _grade_schedule (grade_band, day_index, skill_id)
select ${quoteSql(gradeBand)}, (item.position - 1)::integer, item.skill_id
from unnest(array[
${arrayRows}
]::text[]) with ordinality as item(skill_id, position);`
}

export function renderGeneratedScheduleBlock() {
  validateScheduleSpec()
  const inserts = Object.entries(GRADE_SCHEDULES)
    .map(([gradeBand, skills]) => renderGradeInsert(gradeBand, skills))
    .join('\n\n')
  return `${BEGIN_MARKER}\n${inserts}\n${END_MARKER}`
}

export function validateMigrationContract(sql) {
  const dates = scheduleDates()
  if (dates.length !== 39 || dates[0] !== START_DATE || dates.at(-1) !== END_DATE) {
    throw new Error('curriculum spine date range changed unexpectedly')
  }
  const currentBlock = sql.match(
    new RegExp(`${BEGIN_MARKER}[\\s\\S]*?${END_MARKER}`),
  )?.[0]
  if (currentBlock !== renderGeneratedScheduleBlock()) {
    throw new Error('generated grade schedule block is stale; run this script with --write')
  }
  const recoveryLiteral = `array[${PERSONAL_RECOVERY_DAY_INDEXES.join(',')}]::integer[]`
  if (!sql.includes(recoveryLiteral)) {
    throw new Error(`recovery anchors must remain ${recoveryLiteral}`)
  }
  if (!sql.includes("date '2026-08-22'") || !sql.includes("date '2026-09-29'")) {
    throw new Error('migration must retain the exact 2026-08-22..2026-09-29 window')
  }
  return true
}

export function synchronizeMigration({ write = false } = {}) {
  const sql = fs.readFileSync(MIGRATION_PATH, 'utf8')
  const generated = renderGeneratedScheduleBlock()
  const markerPattern = new RegExp(`${BEGIN_MARKER}[\\s\\S]*?${END_MARKER}`)
  if (!markerPattern.test(sql)) throw new Error('generated schedule markers are missing')
  const synchronized = sql.replace(markerPattern, generated)
  if (write && synchronized !== sql) fs.writeFileSync(MIGRATION_PATH, synchronized, 'utf8')
  validateMigrationContract(write ? synchronized : sql)
  return {
    changed: synchronized !== sql,
    dateCount: scheduleDates().length,
    startDate: START_DATE,
    endDate: END_DATE,
    recoveryDayIndexes: [...PERSONAL_RECOVERY_DAY_INDEXES],
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const write = process.argv.includes('--write')
  const result = synchronizeMigration({ write })
  process.stdout.write(`${JSON.stringify(result)}\n`)
}

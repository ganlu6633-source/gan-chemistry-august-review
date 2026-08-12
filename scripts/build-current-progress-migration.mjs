import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

const curriculum = readFileSync(resolve('supabase/migrations/20260812044629_seed_full_four_week_curriculum.sql'), 'utf8').split(/\r?\n/)
const plans = readFileSync(resolve('supabase/migrations/20260812044632_generate_four_week_student_plans.sql'), 'utf8').split(/\r?\n/)
const intro = curriculum.filter((line) => line.includes('H1_MOLE_INTRO') || line.includes('H1_ELECTROLYTE_INTRO'))
const planBodyStart = plans.findIndex((line) => line.startsWith('create temporary table'))
const planBodyEnd = plans.findIndex((line) => line === 'commit;')
if (intro.length !== 20 || planBodyStart < 0 || planBodyEnd < 0) throw new Error('Generated migration inputs are incomplete')

const output = [
  '-- Aligns the active high-one cohort to the latest teacher-confirmed lesson boundary.',
  'begin;',
  ...intro,
  ...plans.slice(planBodyStart, planBodyEnd),
  'commit;',
  '',
]
writeFileSync(resolve('supabase/migrations/20260812060000_align_current_high1_progress.sql'), output.join('\n'), 'utf8')
console.log(JSON.stringify({ introStatements: intro.length, planBodyLines: planBodyEnd - planBodyStart }))

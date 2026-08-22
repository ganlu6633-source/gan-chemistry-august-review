/**
 * Curriculum spine for the remaining summer review and the first school month.
 *
 * This file names only the classroom spine.  A plan builder may replace one of
 * the five classroom concepts on `personalRecovery` days with one verified
 * unresolved/diagnostic concept.  The two High-1 profiles explicitly marked
 * for daily redox use one rotating H1_REDOX concept every day; they never turn
 * the whole five-question day into a redox-only plan.
 */

export const START_DATE = '2026-08-22'
export const END_DATE = '2026-09-29'

export const PERSONAL_RECOVERY_DAY_INDEXES = Object.freeze([0, 4, 9, 14, 20, 27, 34])

export const GRADE_SCHEDULES = Object.freeze({
  高一: Object.freeze([
    // 8/22—8/31: close the already learned summer-review loop.
    'H1_CLASSIFY', 'H1_PERIODIC', 'H1_MOLE_INTRO', 'H1_GAS_MOLAR_VOLUME', 'H1_CLASSIFY',
    'H1_PERIODIC', 'H1_MOLE_INTRO', 'H1_GAS_MOLAR_VOLUME', 'H1_REDOX', 'H1_MOLE_INTRO',
    // 9/1—9/14: 苏教版必修一从第一单元开始，按分类/转化→计量→浓度推进。
    'H1_CLASSIFY', 'H1_REACTION_CLASSIFICATION', 'H1_CLASSIFY', 'H1_REACTION_CLASSIFICATION',
    'H1_MOLE_INTRO', 'H1_MOLE_INTRO', 'H1_SOLUTION_CONCENTRATION', 'H1_SOLUTION_CONCENTRATION',
    'H1_MOLE_INTRO', 'H1_SOLUTION_CONCENTRATION', 'H1_GAS_MOLAR_VOLUME', 'H1_GAS_MOLAR_VOLUME',
    'H1_CLASSIFY', 'H1_REACTION_CLASSIFICATION',
    // 9/15—9/29: keep following the same textbook unit; do not jump ahead.
    'H1_MOLE_INTRO', 'H1_SOLUTION_CONCENTRATION', 'H1_REACTION_CLASSIFICATION',
    'H1_GAS_MOLAR_VOLUME', 'H1_CLASSIFY', 'H1_MOLE_INTRO', 'H1_SOLUTION_CONCENTRATION',
    'H1_REACTION_CLASSIFICATION', 'H1_GAS_MOLAR_VOLUME', 'H1_CLASSIFY', 'H1_MOLE_INTRO',
    'H1_SOLUTION_CONCENTRATION', 'H1_REACTION_CLASSIFICATION', 'H1_GAS_MOLAR_VOLUME', 'H1_CLASSIFY',
  ]),
  高二: Object.freeze([
    // 8/22—8/31: diagnose the eight already represented review modules.
    'H2_THERMO', 'H2_RATE', 'H2_EQUIL', 'H2_K', 'H2_WEAK',
    'H2_PH_HYDRO', 'H2_KSP', 'H2_ELECTRO', 'H2_THERMO', 'H2_ELECTRO',
    // 9/1—9/14: 苏教版选择性必修一从反应热到电化学、腐蚀与防护。
    'H2_THERMO', 'H2_THERMO', 'H2_THERMO', 'H2_THERMO',
    'H2_ELECTRO', 'H2_ELECTRO', 'H2_ELECTRO', 'H2_ELECTRO', 'H2_ELECTRO',
    'H2_THERMO', 'H2_ELECTRO', 'H2_ELECTRO', 'H2_THERMO', 'H2_ELECTRO',
    // 9/15—9/29: only then enter rate, equilibrium and its quantitative tools.
    'H2_RATE', 'H2_RATE', 'H2_EQUIL', 'H2_EQUIL', 'H2_K',
    'H2_RATE', 'H2_EQUIL', 'H2_K', 'H2_WEAK', 'H2_PH_HYDRO',
    'H2_KSP', 'H2_ELECTRO', 'H2_EQUIL', 'H2_K', 'H2_RATE',
  ]),
  高三: Object.freeze([
    // Error-prone and high-frequency exam modules come first and recur sooner.
    'H3_ION_REDOX', 'H3_STOICH', 'H3_EXPERIMENT', 'H3_AQ', 'H3_ION_REDOX',
    'H3_ELECTRO', 'H3_STOICH', 'H3_EQUILIBRIUM', 'H3_EXPERIMENT', 'H3_THERMO_RATE',
    'H3_ION_REDOX', 'H3_INORGANIC', 'H3_AQ', 'H3_PROCESS', 'H3_STOICH',
    'H3_STRUCTURE', 'H3_EXPERIMENT', 'H3_ORGANIC', 'H3_ION_REDOX', 'H3_ELECTRO',
    'H3_AQ', 'H3_EQUILIBRIUM', 'H3_STOICH', 'H3_THERMO_RATE', 'H3_EXPERIMENT',
    'H3_INORGANIC', 'H3_PROCESS', 'H3_ION_REDOX', 'H3_AQ', 'H3_STRUCTURE',
    'H3_STOICH', 'H3_ORGANIC', 'H3_ELECTRO', 'H3_EQUILIBRIUM', 'H3_EXPERIMENT',
    'H3_ION_REDOX', 'H3_STOICH', 'H3_AQ', 'H3_PROCESS',
  ]),
})

export function scheduleDates() {
  const start = new Date(`${START_DATE}T00:00:00Z`)
  return Array.from({ length: 39 }, (_, index) => {
    const date = new Date(start)
    date.setUTCDate(start.getUTCDate() + index)
    return date.toISOString().slice(0, 10)
  })
}

export function validateScheduleSpec() {
  const dates = scheduleDates()
  if (dates[0] !== START_DATE || dates.at(-1) !== END_DATE || dates.length !== 39) {
    throw new Error('review schedule date window must be 2026-08-22 through 2026-09-29')
  }
  for (const [gradeBand, schedule] of Object.entries(GRADE_SCHEDULES)) {
    if (schedule.length !== dates.length || schedule.some((skillId) => !skillId.startsWith(`H${gradeBand === '高一' ? 1 : gradeBand === '高二' ? 2 : 3}_`))) {
      throw new Error(`${gradeBand} schedule does not contain exactly one valid classroom skill per day`)
    }
  }
  if (new Set(PERSONAL_RECOVERY_DAY_INDEXES).size !== PERSONAL_RECOVERY_DAY_INDEXES.length
    || PERSONAL_RECOVERY_DAY_INDEXES.some((index) => index < 0 || index >= dates.length)) {
    throw new Error('personal recovery anchors must be unique day indexes inside the schedule window')
  }
  return true
}

validateScheduleSpec()

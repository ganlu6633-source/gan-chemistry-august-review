import { expect, test } from '@playwright/test'

const TEST_TEACHER_CODE = process.env.E2E_TEACHER_CODE ?? '904422'

const reviewPlans = Array.from({ length: 40 }, (_, index) => {
  const date = new Date(Date.UTC(2026, 7, 17 + index)).toISOString().slice(0, 10)
  return { id: `p${index + 1}`, studentId: 'demo', date, mode: 'REVIEW', title: `第${index + 1}天复习`, skillIds: ['H1_CLASSIFY'], knowledgeSummaries: ['分类依据', '氧化物判别', '常见误区'], estimatedMinutes: 35, source: 'mixed', isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null, questionCount: 5, roundLimit: 5, maxQuestionLevel: 3, isResolved: false, isComplete: false, roundsRemaining: 5 }
})

const demoSkillCatalog = {
  高一: [
    ['H1_CLASSIFY', '物质的分类'], ['H1_PERIODIC', '元素周期律'], ['H1_ELECTROLYTE_INTRO', '电解质基础'], ['H1_REDOX', '氧化还原'],
    ['H1_MOLE_INTRO', '物质的量基础'], ['H1_ELECTROLYTE', '离子反应'], ['H1_GAS_MOLAR_VOLUME', '气体摩尔体积基础'], ['H1_MOLE', '物质的量计算'], ['H1_NACL', '钠和氯'],
  ],
  高二: [
    ['H2_THERMO', '反应热与方向'], ['H2_RATE', '化学反应速率'], ['H2_EQUIL', '化学平衡'], ['H2_K', '平衡常数'],
    ['H2_WEAK', '弱电解质电离'], ['H2_PH_HYDRO', '水解与pH'], ['H2_KSP', '沉淀溶解平衡'], ['H2_ELECTRO', '电化学'],
  ],
  高三: [
    ['H3_STOICH', '化学计量'], ['H3_ION_REDOX', '离子与氧化还原'], ['H3_THERMO_RATE', '热化学与速率'], ['H3_EQUILIBRIUM', '平衡综合'],
    ['H3_AQ', '水溶液综合'], ['H3_ELECTRO', '电化学综合'], ['H3_INORGANIC', '无机元素网络'], ['H3_EXPERIMENT', '化学实验'],
    ['H3_PROCESS', '工艺流程'], ['H3_STRUCTURE', '物质结构与性质'], ['H3_ORGANIC', '有机化学基础'],
  ],
} as const

const definitionsFor = (gradeBand: keyof typeof demoSkillCatalog) => demoSkillCatalog[gradeBand].map(([id, title], index) => ({
  id, title, moduleId: `${gradeBand}-M${index + 1}`, gradeBand, maxLevel: 4, examImportance: 5 as const, examDepth: 4 as const, prerequisites: [], levelCriteria: [],
}))

const studentDashboard = {
  profile: { id: 'demo', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: reviewPlans,
  skillStates: [{ studentId:'demo', skillId:'H1_CLASSIFY', verifiedLevel:2, candidateLevel:3, maxLevel:4, stability:'verified', evidence:[], consecutiveErrors:0, nextReviewAt:null, reviewIntervalIndex:1, lastReviewedAt:null, teacherIntervention:false }],
  skillDefinitions: definitionsFor('高一'),
  todayQuestionCount: 5,
  achievements: [{ id:'a1', title:'物质分类 L2 已点亮', description:'真棒，通过了L2的检验。', earnedAt:'2026-08-12T08:00:00Z' }],
}

const futurePreviewPlan = {
  id: 'future-preview-plan', studentId: 'future-preview-student', date: '2099-12-31', mode: 'REVIEW',
  title: '科粤版·1.1 身边的化学', skillIds: ['1.1-K01'], targetConceptKeys: ['1.1-K01'],
  knowledgeSummaries: ['化学研究对象', '化学的价值'], estimatedMinutes: 15, source: 'scheduled', isScheduled: true,
  questionCount: 12, roundLimit: 1, maxQuestionLevel: 2, deliveryMode: 'junior_adaptive', juniorSessionStatus: 'not_started',
  hardQuestionCap: 15, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null,
  isResolved: false, isComplete: false, roundsRemaining: 1,
}

const futurePreviewDashboard = {
  ...studentDashboard,
  profile: { id: 'future-preview-student', displayName: '预习学生', gradeBand: '初三', textbookVersion: '科粤版', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: [futurePreviewPlan],
  skillStates: [],
  skillDefinitions: [],
  achievements: [],
}

const futurePreviewCard = {
  id: 'KC-1.1-K01', skillId: '1.1-K01', title: '化学在研究什么',
  core: '化学研究物质的组成、结构、性质、变化和用途。',
  detail: '先分清研究对象，再把观察到的现象与物质变化联系起来。',
  steps: ['找到正在研究的物质', '判断关注的是性质还是变化'],
  commonMistakes: ['把所有自然现象都当成化学问题'],
  microExample: '研究蜡烛燃烧前后生成了什么物质，属于化学的研究范围。',
  reviewStatus: 'approved',
}

const demoGradeContent = {
  高一: { skillId: 'H1_CLASSIFY', planTitle: '物质分类与元素周期律', topics: ['物质分类树', '周期律趋势', '阿伏加德罗常数'] },
  高二: { skillId: 'H2_EQUIL', planTitle: '选择性必修一综合复习', topics: ['化学平衡', '水溶液中的离子平衡', '电化学'] },
  高三: { skillId: 'H3_PROCESS', planTitle: '8月27日质检冲刺', topics: ['反应原理综合', '无机流程', '实验与有机综合'] },
} as const

const demoDashboardFor = (gradeBand: '高一' | '高二' | '高三') => ({
  ...studentDashboard,
  profile: { ...studentDashboard.profile, id: `demo-${gradeBand}`, displayName: '演示学生', gradeBand, isDemo: true, availableDemoGrades: ['高一', '高二', '高三'] },
  plans: reviewPlans.map((plan) => ({ ...plan, id: `${gradeBand}-${plan.id}`, studentId: `demo-${gradeBand}`, title: `${gradeBand} · ${demoGradeContent[gradeBand].planTitle} · 第${plan.id.slice(1)}天`, skillIds: [demoGradeContent[gradeBand].skillId], knowledgeSummaries: demoGradeContent[gradeBand].topics })),
  skillStates: studentDashboard.skillStates.map((state) => ({ ...state, studentId: `demo-${gradeBand}`, skillId: demoGradeContent[gradeBand].skillId })),
  skillDefinitions: definitionsFor(gradeBand),
})

const guardianDashboard = {
  student: { displayName: '测试学生', gradeBand: '高一' }, weeklyCompleted: 5, weeklyPlanned: 6, weeklyQuizCompleted: 2, stableSkillCount: 2, growingSkillCount: 1, forgottenSkillCount: 1, teacherAttentionCount: 1,
  skillSummary: { total: 8, learned: 4, full: 1, partial: 2, unlit: 1, due: 1, recovered: 0, answeredQuestions: 3 },
  progress: ['氧化物定义经过两次新母题检验后已经稳定。'], concerns: ['交叉分类仍需继续巩固，系统已经安排同技能新题。'],
  behaviorSignals: [], timeline: [{ id:'q1', at:'2026-08-13T02:10:00Z', type:'attempt', title:'完成即时小测 · 第2轮', description:'物质的量：答对 13/15，用时5分10秒；需要继续巩固：物质的量计算' }, { id:'t1', at:'2026-08-12T08:00:00Z', type:'progress', title:'通过氧化物定义检验', description:'系统记录了两个独立证据。' }],
}

const recordSkill = (overrides: Record<string, unknown>) => ({
  skillId: 'H1_CLASSIFY', title: '物质的分类', moduleId: '高一-M1', maxLevel: 4, verifiedLevel: 2, candidateLevel: 3,
  evidenceStatus: 'partial', exposure: 'learned', retentionStatus: 'forming', lastReviewedAt: '2026-08-13T08:00:00Z', nextReviewAt: '2026-08-17T08:00:00Z', teacherIntervention: false,
  attemptCount: 1, answeredQuestionCount: 2, correctQuestionCount: 1, uniqueMotherCount: 2,
  learnedTopics: ['混合物与纯净物', '单质与化合物'], knowledgeEvidenceScope: 'module_directory_only', recentQuestionsTruncated: false,
  knowledgeSections: [{ id: 'classification-tree', title: '分类总树', summary: '从物质一路向下判断', points: [
    { id: 'pure-substance', title: '纯净物与混合物', rule: '先按样品中含有几种物质判断。' },
    { id: 'acid-axis', title: '酸的三条分类轴', rule: '元数、强弱、是否含氧要分别判断，结果可以交叉。' },
  ] }],
  recentQuestions: [
    { questionId: 'q-record-1', motherId: 'm-record-1', level: 2, stem: '下列物质属于纯净物的是', options: ['空气', '液氯', '盐酸', '漂白粉'], selectedOption: 0, correctOption: 1, explanation: '液氯只含 Cl₂ 一种物质，属于纯净物；空气、盐酸和漂白粉都含多种物质。', imageUrl: null, correct: false, uncertain: true, durationSec: 38, answeredAt: '2026-08-13T08:00:00Z', snapshotAvailable: true, currentQuestionStatus: 'available' },
    { questionId: 'q-record-2', motherId: 'm-record-2', level: 1, stem: '物质分类的第一层依据是什么', options: ['元素种类', '所含物质种类', '能否导电', '是否溶于水'], selectedOption: 1, correctOption: 1, explanation: '第一层先看样品中含有几种物质。', imageUrl: null, correct: true, uncertain: false, durationSec: 21, answeredAt: '2026-08-12T08:00:00Z', snapshotAvailable: true, currentQuestionStatus: 'available' },
  ],
  nextPlan: { id: 'p3', date: '2026-08-17', title: '分类树与电解质' },
  ...overrides,
})

const learningRecord = {
  generatedAt: '2026-08-14T08:00:00Z',
  evidenceScope: '技能级证据；知识点列表仅说明模块包含什么，不代表每个知识点都已逐项验证。',
  historyWindow: { attemptLimit: 500, answerLimit: 500, recentQuestionsPerSkillLimit: 20, loadedAttempts: 2, totalAttempts: 2, loadedAnswers: 3, totalAnswersInLoadedAttempts: 3, attemptsTruncated: false, answersTruncated: false, hasMore: false },
  summary: { total: 8, learned: 4, full: 1, partial: 2, unlit: 1, due: 1, recovered: 0, answeredQuestions: 3 },
  skills: [
    recordSkill({}),
    recordSkill({ skillId: 'H1_PERIODIC', title: '元素周期律', evidenceStatus: 'full', verifiedLevel: 4, retentionStatus: 'stable', answeredQuestionCount: 1, correctQuestionCount: 1, uniqueMotherCount: 1, recentQuestions: [] }),
    recordSkill({ skillId: 'H1_REDOX', title: '氧化还原', evidenceStatus: 'unlit', verifiedLevel: 0, retentionStatus: 'unknown', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [], nextPlan: { id: 'p4', date: '2026-08-18', title: '氧化还原电子守恒' } }),
    recordSkill({ skillId: 'H1_MOLE_INTRO', title: '物质的量基础', evidenceStatus: 'partial', verifiedLevel: 1, retentionStatus: 'due', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [] }),
    recordSkill({ skillId: 'H1_ELECTROLYTE_INTRO', title: '电解质基础', evidenceStatus: 'unlit', verifiedLevel: 0, exposure: 'future', retentionStatus: 'unknown', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [] }),
    recordSkill({ skillId: 'H1_ELECTROLYTE', title: '离子反应', evidenceStatus: 'unlit', verifiedLevel: 0, exposure: 'future', retentionStatus: 'unknown', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [] }),
    recordSkill({ skillId: 'H1_MOLE', title: '物质的量计算', evidenceStatus: 'unlit', verifiedLevel: 0, exposure: 'future', retentionStatus: 'unknown', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [] }),
    recordSkill({ skillId: 'H1_NACL', title: '钠和氯', evidenceStatus: 'unlit', verifiedLevel: 0, exposure: 'future', retentionStatus: 'unknown', answeredQuestionCount: 0, correctQuestionCount: 0, uniqueMotherCount: 0, recentQuestions: [] }),
  ],
}

const teacherDashboard = {
  students: [
    { id:'demo', displayName:'测试学生', gradeBand:'高一', status:'active', needsInitialDiagnostic:false, guardianNames:['测试妈妈','测试爸爸'], curriculumCohort:'high1_completed', planDays:40 },
    { id:'high2-demo', displayName:'高二测试学生', gradeBand:'高二', status:'active', needsInitialDiagnostic:false, guardianNames:['高二测试家长'], curriculumCohort:'high2_selective1_complete', planDays:40 },
    { id:'high3-demo', displayName:'高三测试学生', gradeBand:'高三', status:'active', needsInitialDiagnostic:false, guardianNames:[], curriculumCohort:'high3_exam_sprint', planDays:40 },
  ],
  alerts: [], dailySummary: { generatedAt:'2026-08-13T02:10:05Z', classQuizCount:1, quizCompletedStudentCount:1, quizRosterCount:5, reviewCount:1, interventionCount:0 },
  recentQuizSessions: [{ id:'q1', studentId:'demo', studentName:'测试学生', round:2, trainingTheme:'物质的量', correctCount:13, totalCount:15, totalSec:310, wrongTags:['物质的量计算'], slowTags:[], completedAt:'2026-08-13T02:10:00Z' }],
  pendingCourseNodes: 0, pendingQuestions: 0,
}

const classificationCard = {
  id: 'KC_H1_CLASSIFY', skillId: 'H1_CLASSIFY', title: '物质到底分成哪些？从总树干一路分到底',
  core: '先牢记第一根树干：物质分为纯净物和混合物；纯净物再分为单质和化合物。',
  detail: '每次都从物质出发，一层一层判断。', steps: ['先分纯净物和混合物', '再分单质和化合物'],
  commonMistakes: ['把溶液当纯净物'], microExample: 'H₂SO₄是二元强酸和含氧酸。', reviewStatus: 'approved',
  structuredContent: {
    version: 2, intro: '假设你现在完全不记得：从最上面的物质开始，一层一层往下走。',
    overview: ['先分纯净物和混合物。', '纯净物再分单质和化合物。', '化合物继续分氧化物、酸、碱、盐。', '横向再判断电解质。'],
    visualSummary: { kind: 'tree', title: '物质分类总树', tree: { label: '物质', children: [
      { label: '混合物', children: [{ label: '分散系', children: [{ label: '溶液' }, { label: '胶体' }, { label: '浊液' }] }] },
      { label: '纯净物', children: [{ label: '单质' }, { label: '化合物', children: [{ label: '有机化合物' }, { label: '无机化合物', children: [{ label: '氧化物' }, { label: '酸' }, { label: '碱' }, { label: '盐' }] }] }] },
    ] }, axes: [{ label: '化合物｜电离', items: ['电解质', '非电解质'] }, { label: '酸｜三条轴', items: ['元数', '强弱', '含氧与否'] }] },
    rootTree: { label: '物质', rule: '先按样品中有几种物质分类。', examples: ['空气是混合物', '液氯是纯净物'], visualSteps: ['物质', '数物质种类', '纯净物/混合物'], children: [
      { label: '混合物', rule: '含两种或两种以上物质。', examples: ['空气', '盐酸'] },
      { label: '纯净物', rule: '只含一种物质。', examples: ['液氯Cl₂'], children: [
        { label: '单质', rule: '纯净物中只含一种元素。', examples: ['O₂'] },
        { label: '化合物', rule: '纯净物中含两种或两种以上元素。', examples: ['H₂O'], children: [
          { label: '无机化合物', rule: '本讲继续分氧化物、酸、碱和盐。', examples: ['NaCl'] },
        ] },
      ] },
    ] },
    sections: [
      { title: '酸要沿三条独立的线分类', summary: '元数、强弱和是否含氧分别判断。', items: [
        { label: '按可电离的H⁺个数', rule: '分一元酸、二元酸和多元酸。', examples: ['一元：HCl', '二元：H₂SO₄', '三元：H₃PO₄'] },
        { label: '按电离程度', rule: '分强酸和弱酸。', examples: ['强酸：HCl', '弱酸：CH₃COOH'] },
      ] },
      { title: '碱也要沿三条独立的线分类', summary: '元数、强弱和溶解性分别判断。', items: [
        { label: '按可电离的OH⁻个数', rule: '分一元碱、二元碱和三元碱。', examples: ['一元：NaOH', '二元：Ca(OH)₂'] },
        { label: '按溶解性', rule: '分易溶、微溶和难溶。', examples: ['微溶：Ca(OH)₂'], caution: 'Ca(OH)₂微溶但属于强碱。' },
      ] },
    ],
    workedExamples: [{ substance: 'H₂SO₄', path: '纯净物 → 化合物 → 无机化合物 → 酸', labels: ['二元酸', '强酸', '含氧酸'] }],
    checkpoints: ['我能画出物质分类总树。'],
  },
}

const classificationQuestion = { id:'q-classify', motherId:'m-classify', skillId:'H1_CLASSIFY', level:1, gradeBand:'高一', stem:'物质分类的第一个分叉是', options:['单质和化合物','纯净物和混合物','酸和碱','金属和非金属'], correctOption:1, explanation:'先分纯净物和混合物。', scaffold:'从物质树根开始。', reviewStatus:'approved', scopeStatus:'IN', sourceKind:'teacher_original' }
const roundQuestions = Array.from({ length: 5 }, (_, index) => ({ ...classificationQuestion, id: `q-classify-${index + 1}`, motherId: `m-classify-${index + 1}`, stem: index === 0 ? classificationQuestion.stem : `第${index + 1}个分类判断：物质分类的第一个分叉是` }))
const redoxCard = {
  id: 'KC_H1_REDOX', skillId: 'H1_REDOX', title: '氧化还原：把电子转移的逻辑完整接起来',
  core: '标价只是入口，电子守恒才是主线。', detail: '从化合价变化追到得失电子。',
  steps: ['标价', '找升降', '配电子', '查守恒'], commonMistakes: ['只背口诀'], microExample: 'FeS₂被O₂氧化。', reviewStatus: 'approved',
  structuredContent: {
    version: 2,
    intro: '先标出反应前后化合价，再追踪得失电子，最后用守恒把方程式闭合。',
    overview: ['标出反应前后化合价。', '确定升降与电子数。', '求最小公倍数并定系数。', '用原子、电荷和电子守恒校验。'],
    visualSummary: { kind: 'balance', title: '氧化还原电子天平', center: 'e⁻总数相等', groups: [{ label: '升价｜失电子', items: ['被氧化', '还原剂'] }, { label: '降价｜得电子', items: ['被还原', '氧化剂'] }] },
    sections: [
      { title: '标价', summary: '先找真正变价的元素。', items: [{ label: '标反应前后价态', rule: '根据单质为0和化合价代数和规则，标出同一元素反应前后的价态。', examples: ['【示范：FeS₂被O₂氧化】FeS₂中Fe为+2、S为-1，O₂中O为0；产物中Fe为+3、SO₄²⁻中S为+6。'], visualSteps: ['读反应式', '标价', '找变价元素'] }] },
      { title: '升降与电子数', summary: '每个粒子的变价原子数也要计入。', items: [{ label: '计算得失电子', rule: '化合价变化数乘变价原子个数，得到一个粒子得失的电子数。', examples: ['【示范：FeS₂被O₂氧化】Fe由+2到+3失1e⁻，两个S由-1到+6共失14e⁻，所以每个FeS₂共失15e⁻。'], visualSteps: ['Fe失1e⁻', '2个S失14e⁻', '每个FeS₂失15e⁻'] }] },
      { title: '最小公倍数', summary: '总失电子必须等于总得电子。', items: [{ label: '先定氧化还原骨架', rule: '求升降电子数的最小公倍数，先确定氧化剂、还原剂及对应产物的系数。', examples: ['【示范：FeS₂被O₂氧化】O₂中两个O由0到-2共得4e⁻；15和4的最小公倍数是60，先定4FeS₂和15O₂。'], visualSteps: ['失15e⁻', '得4e⁻', '最小公倍数60', '4:15'] }] },
      { title: '守恒校验', summary: '先补介质，再查三类守恒。', items: [{ label: '补齐并复核', rule: '按酸碱介质补H₂O、H⁺或OH⁻，最后核对原子、电荷与得失电子总数。', examples: ['【示范：FeS₂被O₂氧化】4FeS₂+15O₂+2H₂O=4Fe³⁺+8SO₄²⁻+4H⁺；Fe、S、O、H原子守恒，左右总电荷均为0。'], visualSteps: ['补H₂O/H⁺', '查原子', '查电荷', '查电子'] }] },
    ],
    workedExamples: [
      { substance: 'FeS₂被O₂氧化', path: '标价→升降电子数→最小公倍数→补介质→三重守恒。', labels: ['标价', '电子数', '60', '守恒'] },
      { substance: '酸性MnO₄⁻氧化Fe²⁺', path: '这段长文字必须由图解替代。', labels: ['先定1∶5', '再补H和O', '查三守恒'] },
    ],
    checkpoints: ['我能正确标价。', '我能计算一个粒子的电子数。', '我会用最小公倍数定系数。', '我会做三类守恒检查。'],
  },
}

const periodicCard = {
  ...redoxCard,
  id: 'KC_H1_PERIODIC', skillId: 'H1_PERIODIC', title: '元素周期律：把结构、位置与性质完整接起来',
  core: '同周期和同主族必须分别限定比较对象。', detail: '从结构原因推出性质，再用化合物事实验证。',
  structuredContent: {
    ...redoxCard.structuredContent,
    intro: '从原子结构、周期表位置一直连到最高价含氧体系与气态氢化物。',
    visualSummary: { kind: 'compare', title: '元素周期律完整趋势图', groups: [
      { label: '同周期 →', items: ['层数不变·核电荷↑', '半径总体↓', '金属性↓｜非金属性↑'] },
      { label: '最高价氧化物', items: ['Na₂O→MgO→Al₂O₃→SiO₂→P₄O₁₀→SO₃→Cl₂O₇'] },
      { label: '对应水化物', items: ['NaOH→Mg(OH)₂→Al(OH)₃→H₂SiO₃→H₃PO₄→H₂SO₄→HClO₄', '碱性减弱→两性→酸性增强'] },
      { label: '气态氢化物', items: ['SiH₄＜PH₃＜H₂S＜HCl', 'HF＞HCl＞HBr＞HI', '热稳定性≠水溶液酸性≠还原性'] },
      { label: '价态与通式', items: ['最低负价−4/−3/−2/−1', 'RH₄/RH₃/H₂R/HR'] },
    ] },
    sections: [{ title: '最高价含氧体系的边界', summary: '对应关系不等于直接水合。', items: [{ label: '对应水化物', rule: '比较最高价氧化物对应水化物的酸碱性。', examples: ['【示范：第3周期】SiO₂对应H₂SiO₃，但SiO₂不能直接与水生成H₂SiO₃。'], visualSteps: ['最高价氧化物', '对应水化物', '碱性→两性→酸性'] }] }],
    workedExamples: [{ substance: '第3周期', path: '先定位，再比较最高价含氧体系和气态氢化物。', labels: ['结构', '位置', '性质', '证据'] }],
    checkpoints: ['我会写最高价含氧体系。', '我会比较气态氢化物热稳定性。', '我不混淆酸性与稳定性。', '我会检查O、F等边界。'],
  },
}

const visualKindCards = [
  { kind: 'tree', title: '层级树', tree: { label: '根', children: [{ label: '分支甲' }, { label: '分支乙' }] } },
  { kind: 'flow', title: '步骤流', steps: [{ label: '第一步' }, { label: '第二步' }, { label: '第三步' }, { label: '第四步' }] },
  { kind: 'cycle', title: '循环图', steps: [{ label: '旧状态' }, { label: '扰动' }, { label: '新状态' }, { label: '再出发' }] },
  { kind: 'compare', title: '对照图', groups: [{ label: '左侧', items: ['特点甲'] }, { label: '右侧', items: ['特点乙'] }] },
  { kind: 'network', title: '关系网络', center: '中心', groups: [{ label: '入口甲', items: ['关系甲'] }, { label: '入口乙', items: ['关系乙'] }] },
  { kind: 'balance', title: '守恒天平', center: '=', groups: [{ label: '左边', items: ['数量甲'] }, { label: '右边', items: ['数量乙'] }] },
].map((visualSummary, index) => ({ ...redoxCard, id: `visual-${index}`, title: `${visualSummary.title}验收卡`, structuredContent: { ...redoxCard.structuredContent, visualSummary } }))

test.beforeEach(async ({ page }) => {
  let mockAttemptCount = 0
  await page.route('**/functions/v1/chemistry-access', async (route) => {
    const responseHeaders = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { ...responseHeaders, 'Access-Control-Allow-Headers': 'apikey,content-type,x-app-session' } })
      return
    }
    const body = route.request().postDataJSON() as { action: string; name?: string; code?: string; data?: { planId?: string; planDayId?: string; gradeBand?: '高一' | '高二' | '高三'; studentId?: string; previewRound?: number } }
    if (body.action === 'recover_access_code') {
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ ok: true, message: '登录码已更新，请使用新登录码进入。' }) })
      return
    }
    if (body.action === 'login') {
      if (body.code === TEST_TEACHER_CODE) {
        await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ session: { role: 'teacher', token: 'teacher-test-token', displayName: body.name, expiresAt: '2099-01-01T00:00:00Z' } }) })
        return
      }
      const guardian = body.code === '22222222'
      const demo = body.name === '演示学生'
      const futurePreviewStudent = body.name === '预习学生'
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ session: { role: guardian ? 'guardian' : 'student', token: 'test-token', displayName: demo ? '演示学生' : futurePreviewStudent ? '预习学生' : '测试学生', expiresAt: '2099-01-01T00:00:00Z' }, dashboard: guardian ? guardianDashboard : demo ? demoDashboardFor('高一') : futurePreviewStudent ? futurePreviewDashboard : studentDashboard }) })
      return
    }
    if (body.action === 'future_plan_preview') {
      expect(body.data?.planId).toBe(futurePreviewPlan.id)
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: responseHeaders,
        body: JSON.stringify({ preview: { previewMode: 'future_knowledge_only', plan: futurePreviewPlan, cards: [futurePreviewCard], formalOpenDate: futurePreviewPlan.date, recordsLearningEvidence: false, includesQuestions: false } }),
      })
      return
    }
    if (body.action === 'demo_dashboard') {
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ dashboard: demoDashboardFor(body.data?.gradeBand ?? '高一') }) })
      return
    }
    if (body.action === 'change_own_code' || body.action === 'set_recovery_secret') {
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ ok: true, message: body.action === 'change_own_code' ? '登录码已修改。下次请使用新登录码进入。' : '私密找回短语已安全保存。' }) })
      return
    }
    if (body.action === 'learning_record') {
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ record: learningRecord }) })
      return
    }
    if (body.action === 'start_plan') {
      const useRedox = body.data?.planId === 'p2'
      const useVisualKinds = body.data?.planId === 'p3'
      const usePeriodic = body.data?.planId === 'p4'
      const attemptSequence = body.data?.studentId && body.data.previewRound ? body.data.previewRound - 1 : mockAttemptCount
      const basePlan = usePeriodic ? reviewPlans[3] : useVisualKinds ? reviewPlans[2] : useRedox ? reviewPlans[1] : reviewPlans[0]
      const plan = { ...basePlan, attemptCount: attemptSequence, roundsRemaining: Math.max(0, 5 - attemptSequence) }
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ payload: { plan, cards: usePeriodic ? [periodicCard] : useVisualKinds ? visualKindCards : [useRedox ? redoxCard : classificationCard], questions: roundQuestions, attemptSequence, roundNumber: attemptSequence + 1, roundLimit: 5, questionCount: 5, isResolved: false, isComplete: false, roundsRemaining: Math.max(0, 5 - attemptSequence) } }) })
      return
    }
    if (body.action === 'submit_attempt') {
      mockAttemptCount += 1
      const plans = reviewPlans.map((plan) => plan.id === body.data?.planDayId ? { ...plan, attemptCount: mockAttemptCount, latestScore: 0, latestCompletedAt: new Date().toISOString(), isComplete: mockAttemptCount >= 5, roundsRemaining: Math.max(0, 5 - mockAttemptCount) } : plan)
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ dashboard: { ...studentDashboard, plans }, achievements: [] }) })
      return
    }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ dashboard: body.action === 'guardian_dashboard' ? guardianDashboard : studentDashboard }) })
  })
  await page.route('**/functions/v1/chemistry-teacher', async (route) => {
    const responseHeaders = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { ...responseHeaders, 'Access-Control-Allow-Headers': 'apikey,content-type,x-app-session' } })
      return
    }
    expect(route.request().headers()['x-app-session']).toBe('teacher-test-token')
    const body = route.request().postDataJSON() as { action: string; data?: { studentId?: string; planId?: string; previewRound?: number } }
    if (body.action === 'preview_start_plan') expect(body.data?.studentId).toBeTruthy()
    const response = body.action === 'list_course_nodes' ? { nodes: [] }
      : body.action === 'list_questions' ? { questions: [] }
      : body.action === 'student_preview_dashboard' ? { dashboard: body.data?.studentId === 'high2-demo' ? demoDashboardFor('高二') : body.data?.studentId === 'high3-demo' ? demoDashboardFor('高三') : studentDashboard }
      : body.action === 'student_learning_record' ? { record: learningRecord }
      : body.action === 'preview_start_plan' ? { payload: { plan: reviewPlans.find((plan) => plan.id === body.data?.planId) ?? reviewPlans[0], cards: [classificationCard], questions: roundQuestions, attemptSequence: (body.data?.previewRound ?? 1) - 1, roundNumber: body.data?.previewRound ?? 1, roundLimit: 5, questionCount: 5, isResolved: false, isComplete: false, roundsRemaining: 6 - (body.data?.previewRound ?? 1) } }
      : { dashboard: teacherDashboard }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify(response) })
  })
})

test('access page contains name and code inputs with no role selector', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await expect(page.getByLabel('输入姓名')).toHaveCount(1)
  await expect(page.getByPlaceholder('请输入姓名')).toHaveCount(1)
  await expect(page.getByLabel('登录码')).toHaveCount(1)
  await expect(page.getByPlaceholder('6—12位数字')).toHaveCount(1)
  await expect(page.locator('.login-card')).not.toContainText('学生姓名')
  await expect(page.locator('.login-card')).not.toContainText('家长姓名')
  await expect(page.locator('.login-card')).not.toContainText('学生端')
  await expect(page.locator('.login-card')).not.toContainText('家长端')
  await expect(page.getByRole('radio')).toHaveCount(0)
  await expect(page.getByRole('combobox')).toHaveCount(0)
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
  await expect.poll(() => page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).filter((registration) => registration.scope.includes('/gan-chemistry-august-review/')).length)).toBe(0)
  await expect.poll(() => page.evaluate(async () => (await caches.keys()).filter((key) => key.startsWith('gan-chemistry-shell')).length)).toBe(0)
})

test('a future plan opens only the knowledge preview and never starts formal answering', async ({ page }) => {
  const accessActions: string[] = []
  page.on('request', (request) => {
    if (!request.url().includes('/functions/v1/chemistry-access') || request.method() !== 'POST') return
    const body = request.postDataJSON() as { action?: string } | null
    if (body?.action) accessActions.push(body.action)
  })

  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('预习学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()

  const futurePlanButton = page.getByRole('button', { name: /科粤版·1\.1 身边的化学，可提前预习/ })
  await expect(futurePlanButton).toBeVisible()
  await futurePlanButton.click()

  const preview = page.getByTestId('future-plan-preview')
  await expect(preview).toBeVisible()
  await expect(preview).toContainText('提前预习 · 只读知识页')
  await expect(preview).toContainText('不展示正式题目、答案或提示')
  await expect(preview).toContainText('不计入掌握度和正式学习记录')
  await expect(preview).toContainText(futurePreviewCard.title)
  await expect(preview.getByRole('button', { name: /开始|提交|下一题|查看解析/ })).toHaveCount(0)
  expect(accessActions).toContain('future_plan_preview')
  expect(accessActions).not.toContain('start_plan')
  expect(accessActions).not.toContain('junior_open_session')
  expect(accessActions).not.toContain('junior_submit_step')
  expect(accessActions).not.toContain('submit_attempt')
})

test('forgotten code can be reset with a private recovery phrase', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByText('忘记登录码？').click()
  const panel = page.locator('.recovery-panel')
  await panel.getByLabel('找回姓名').fill('测试学生')
  await panel.getByLabel('私密找回短语').fill('我的化学小火箭')
  await panel.getByLabel('设置新的数字码').fill('123456')
  await panel.getByLabel('再次输入数字码').fill('123456')
  await panel.getByRole('button', { name: '重设登录码' }).click()
  await expect(panel).toContainText('登录码已更新')
  await expect(panel).toContainText('不要使用身份证号、生日、手机号')
})

test('public High-3 demo opens the reviewed read-only learning chain without writing evidence', async ({ page }) => {
  const writeActions: string[] = []
  page.on('request', (request) => {
    if (!request.url().includes('/functions/v1/chemistry-access') || request.method() !== 'POST') return
    const body = request.postDataJSON() as { action?: string }
    if (['submit_attempt', 'junior_submit_step'].includes(String(body.action))) writeActions.push(String(body.action))
  })
  await page.setViewportSize({ width: 360, height: 780 })
  await page.clock.setFixedTime(new Date('2026-08-17T08:00:00+08:00'))
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('演示学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: '高三' }).click()
  await page.locator('.focus-card .primary-button').click()

  await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()
  await expect(page.getByText('本次结果只在当前页面展示，不会写入任何真实学生档案。')).toHaveCount(0)
  await expect(page.getByText('2025年福建省质检')).toHaveCount(0)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
  expect(writeActions).toEqual([])
})

test('student code routes to student experience without guardian entry', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-08-17T08:00:00+08:00'))
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: /测试学生，今天先把/ })).toBeVisible()
  await expect(page.getByRole('button', { name: /能力地图/ })).toBeVisible()
  await expect(page.getByText('家长端')).toHaveCount(0)
  await expect(page.getByRole('button', { name: '学习计划' })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: '我的学习计划' })).toBeVisible()
  await expect(page.locator('.plan-day')).toHaveCount(40)
  await expect(page.locator('.week-card')).toHaveCount(6)
  await expect(page.locator('.plan-day[aria-current="date"]')).toHaveCount(1)
  await expect(page.locator('.plan-day[aria-current="date"]')).toContainText('今天')
  await expect(page.locator('.week-card.is-current-week')).toHaveCount(1)
  await expect(page.locator('.page-title')).toContainText('8月17日—9月25日')
  await expect(page.locator('.page-title')).toContainText('8月17日是复习第1天')
  await expect(page.locator('.plan-day').first()).toContainText('08-17 · 周一')
  await expect(page.locator('.plan-day').last()).toContainText('09-25 · 周五')
  await expect(page.locator('.plan-day').first().locator('li')).toHaveCount(3)
  await page.locator('.plan-day').first().click()
  await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()
  // A card may use either the generic quick-visual renderer or a dedicated,
  // source-informed chemistry figure.  The first-screen contract is the
  // visible figure itself, not a particular implementation class.
  const summaryFigure = page.locator('.knowledge-explainer > figure').first()
  await expect(summaryFigure).toBeVisible()
  await expect(summaryFigure).toContainText('物质分类总树')
  await expect(page.locator('.quick-tree')).toContainText('物质')
  await expect(page.locator('.quick-tree')).toContainText('纯净物')
  await expect(page.locator('.quick-tree')).toContainText('混合物')
  await expect(page.locator('.quick-tree')).toContainText('氧化物')
  await expect(page.locator('.quick-tree')).toContainText('酸')
  await expect(page.locator('.quick-tree')).toContainText('碱')
  await expect(page.locator('.quick-tree')).toContainText('盐')
  await expect(page.locator('.quick-tree-axes')).toContainText('横向分类轴')
  await expect(page.locator('.quick-recall')).toHaveCount(0)
  await expect(page.locator('.knowledge-card .core-rule')).toHaveCount(0)
  await expect(page.locator('.classification-map')).not.toBeVisible()
  await page.locator('.full-explanation > summary').click()
  await expect(page.getByRole('heading', { name: '知识总树' })).toBeVisible()
  await expect(page.locator('.knowledge-tree')).toContainText('混合物')
  await expect(page.locator('.knowledge-tree')).toContainText('纯净物')
  await expect(page.locator('.knowledge-tree')).toContainText('单质')
  await expect(page.locator('.knowledge-tree')).toContainText('化合物')
  await expect(page.getByRole('heading', { name: '酸要沿三条独立的线分类' })).toBeVisible()
  await expect(page.getByRole('heading', { name: '碱也要沿三条独立的线分类' })).toBeVisible()
  await expect(page.locator('.classification-map')).toContainText('一元酸')
  await expect(page.locator('.classification-map')).toContainText('二元酸')
  await expect(page.locator('.classification-map')).toContainText('多元酸')
  await expect(page.locator('.classification-map')).toContainText('微溶但属于强碱')
  await expect(page.locator('.classification-item')).toHaveCount(4)
  await expect(page.locator('.classification-item .point-demo')).toHaveCount(4)
  await expect(page.locator('.classification-item .memory-diagram')).toHaveCount(4)
  await expect(page.locator('.knowledge-tree .point-demo')).toHaveCount(6)
  await expect(page.locator('.knowledge-tree .memory-diagram')).toHaveCount(6)
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('Enter advances the complete review flow including feedback and the next round', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-08-17T08:00:00+08:00'))
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()

  await page.locator('.focus-card').getByRole('button', { name: '开始第一轮' }).click()
  await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()

  await page.keyboard.press('Enter')
  await expect(page.locator('.quiz-head')).toContainText('第 1 轮 · 1/5')

  for (let questionIndex = 1; questionIndex <= 5; questionIndex += 1) {
    // Intentionally choose the fixture's wrong option so the first round
    // leaves a real unresolved point and the next-round action is present.
    await page.locator('.option-list button').first().click()
    await page.keyboard.press('Enter')
    await expect(page.locator('.answer-feedback')).toBeVisible()

    await page.keyboard.press('Enter')
    if (questionIndex < 5) {
      await expect(page.locator('.quiz-head')).toContainText(`第 1 轮 · ${questionIndex + 1}/5`)
      await expect(page.locator('.answer-feedback')).toHaveCount(0)
      await expect(page.getByRole('button', { name: '提交答案' })).toBeDisabled()
    }
  }

  await expect(page.getByText('今天第 1 轮完成')).toBeVisible()
  await page.keyboard.press('Enter')
  await expect(page.locator('.quiz-head')).toContainText('第 2 轮 · 1/5')
})

test('student can change the code and set a private recovery phrase after login', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: '账户设置' }).click()
  await expect(page.getByRole('heading', { name: '账户与找回' })).toBeVisible()
  const codeCard = page.locator('.account-card').first()
  await codeCard.getByLabel('当前登录码').fill('11111111')
  await codeCard.getByLabel('新登录码', { exact: true }).fill('654321')
  await codeCard.getByLabel('再次输入新登录码', { exact: true }).fill('654321')
  await codeCard.getByRole('button', { name: '保存新登录码' }).click()
  await expect(page.getByRole('status')).toContainText('登录码已修改')
  const recoveryCard = page.locator('.account-card').nth(1)
  await recoveryCard.getByLabel('当前登录码').fill('654321')
  await recoveryCard.getByLabel('私密找回短语').fill('化学树会发光')
  await recoveryCard.getByLabel('再次输入找回短语').fill('化学树会发光')
  await recoveryCard.getByRole('button', { name: '保存找回短语' }).click()
  await expect(page.getByRole('status')).toContainText('私密找回短语已安全保存')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('demo student can switch among all three high-school grades without writing a real record', async ({ page }) => {
  test.setTimeout(90_000)
  await page.clock.setFixedTime(new Date('2026-08-14T08:00:00+08:00'))
  const startedFor: string[] = []
  page.on('request', (request) => {
    if (!request.url().includes('/functions/v1/chemistry-access') || request.method() !== 'POST') return
    const body = request.postDataJSON() as { action?: string; data?: { studentId?: string } }
    if (body.action === 'start_plan' && body.data?.studentId) startedFor.push(body.data.studentId)
  })
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('演示学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  const switcher = page.getByLabel('切换演示年级')
  await expect(switcher).toContainText('每一天都可以打开完整学习链路')
  await expect(switcher).toContainText('作答只在当前页面模拟，不写入任何正式学生记录')
  const mapExpectations = { 高一: { nodes: 9, edges: 8, title: '高一化学基础主干' }, 高二: { nodes: 8, edges: 7, title: '选择性必修一·反应原理地图' }, 高三: { nodes: 11, edges: 11, title: '高考化学综合能力地图' } } as const
  for (const grade of ['高二', '高三', '高一'] as const) {
    await switcher.getByRole('button', { name: grade }).click()
    await expect(switcher.getByRole('button', { name: grade })).toHaveClass(/active/)
    await expect(page.locator('.focus-card')).toContainText(`${grade} ·`)
    await expect(page.locator('.focus-card')).toContainText(demoGradeContent[grade].topics[0])
    await page.getByRole('button', { name: '能力地图' }).click()
    await expect(page.locator('.ability-atlas')).toHaveCount(1)
    await expect(page.locator('.ability-atlas')).toContainText(mapExpectations[grade].title)
    await expect(page.locator('.ability-node')).toHaveCount(mapExpectations[grade].nodes)
    await expect(page.locator('.ability-map-links > path')).toHaveCount(mapExpectations[grade].edges)
    await expect(page.locator('.ability-map-links > path').first()).toHaveAttribute('d', /^M /)
    await expect(page.locator('.ability-map-links > path').first()).toHaveAttribute('marker-end', /url\(#.+-(main|support)\)/)
    await expect(page.locator('.galaxy-zone')).toHaveCount(0)
    await expect(page.locator('.ability-atlas')).not.toContainText(/H[123][-_]/)
    await page.getByRole('button', { name: '今天', exact: true }).click()
    await page.locator('.focus-card').getByRole('button', { name: /开始第一轮/ }).click()
    await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()
    await page.getByRole('button', { name: /返回计划/ }).click()
  }
  expect(startedFor).toEqual(['demo-高二', 'demo-高三', 'demo-高一'])
  await expect(page.getByRole('button', { name: '账户设置' })).toHaveCount(0)
})

test('ability map remains one readable vertical route on a compact phone', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-08-17T08:00:00+08:00'))
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: '能力地图' }).click()

  await expect(page.locator('.ability-atlas')).toHaveCount(1)
  await expect(page.locator('.ability-map-stage')).toHaveCount(4)
  await expect(page.locator('.ability-node')).toHaveCount(9)
  await expect(page.locator('.ability-map-links > path')).toHaveCount(8)
  await expect(page.locator('.ability-node[aria-current="step"]')).toHaveCount(1)
  await expect(page.locator('.ability-node[aria-current="step"]')).toContainText('你在这里')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((element) => element.clientWidth))
})

test('a grandfathered legacy review day can finish its existing five-round record', async ({ page }) => {
  test.setTimeout(90_000)
  await page.clock.setFixedTime(new Date('2026-08-17T08:00:00+08:00'))
  const submissions: Array<{ sequence: number; answers: unknown[] }> = []
  page.on('request', (request) => {
    if (!request.url().includes('/functions/v1/chemistry-access') || request.method() !== 'POST') return
    const body = request.postDataJSON() as { action?: string; data?: { sequence?: number; answers?: unknown[] } }
    if (body.action === 'submit_attempt' && typeof body.data?.sequence === 'number' && Array.isArray(body.data.answers)) submissions.push({ sequence: body.data.sequence, answers: body.data.answers })
  })
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.locator('.daily-orb')).toContainText('5')
  await page.locator('.focus-card').getByRole('button', { name: '开始第一轮' }).click()
  await page.getByRole('button', { name: /我理解了，开始练习/ }).click()

  for (let round = 1; round <= 5; round += 1) {
    await expect(page.locator('.round-track')).toHaveAttribute('aria-label', `今天共5轮，当前第${round}轮`)
    for (let question = 0; question < 5; question += 1) {
      await page.locator('.option-list button').first().click()
      await page.getByRole('button', { name: '提交答案' }).click()
      await expect(page.locator('.answer-feedback')).toContainText('先把关键一步稳住')
      if (question < 4) await page.getByRole('button', { name: '下一题' }).click()
    }
    await page.getByRole('button', { name: `完成第 ${round} 轮` }).click()
    await expect(page.getByText(`今天第 ${round} 轮完成`)).toBeVisible()
    if (round < 5) await page.getByRole('button', { name: `进入第 ${round + 1} 轮` }).click()
  }

  await expect(page.getByRole('button', { name: '进入第 6 轮' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: '查看今日成果' })).toBeVisible()
  expect(submissions).toHaveLength(5)
  expect(submissions.map((item) => item.sequence)).toEqual([0, 1, 2, 3, 4])
  expect(submissions.every((item) => item.answers.length === 5)).toBe(true)
})

test('guardian code routes directly to the concise guardian explanation', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试家长')
  await page.getByLabel('登录码').fill('22222222')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: '测试学生的化学成长说明' })).toBeVisible()
  await expect(page.getByRole('heading', { name: '当天定位，连续接稳' })).toBeVisible()
  await expect(page.locator('.guardian-care-design')).toContainText('每天 1—8 道原题')
  await expect(page.locator('.guardian-care-design')).toContainText('错题与不确定题优先')
  await expect(page.locator('.guardian-care-design')).toContainText('甘老师复核错因后安排讲解')
  await expect(page.getByText(/本周已有 2 轮即时小测同步到这里/)).toBeVisible()
  await expect(page.getByText('完成即时小测 · 第2轮')).toBeVisible()
  await expect(page.getByText('下一步重点')).toBeVisible()
  await expect(page.getByRole('heading', { name: '一起把基础接得更稳' })).toBeVisible()
  await expect(page.locator('body')).not.toContainText('下节课单独追问')
})

test('student can replay learned, partly lit and unlit skills with exact answered-question evidence', async ({ page }) => {
  test.setTimeout(90_000)
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: '我的战绩' }).click()

  const summary = page.locator('[data-testid="learning-record-summary"]')
  await expect(summary).toContainText('完全点亮')
  await expect(summary).toContainText('点亮一部分')
  await expect(summary).toContainText('待建立证据')
  await expect(summary).toContainText('需要回看')
  await expect(summary).toContainText('后续学习')
  await expect(page.getByText('4/8')).toBeVisible()

  const classification = page.locator('[data-testid="learning-skill-card"]', { hasText: '物质的分类' })
  await classification.locator('summary').first().click()
  await expect(classification).toContainText('酸的三条分类轴')
  await expect(classification).toContainText('元数、强弱、是否含氧要分别判断')
  const question = classification.locator('[data-testid="learning-question-evidence"]').first()
  await question.locator('summary').click()
  await expect(question).toContainText('下列物质属于纯净物的是')
  await expect(question).toContainText('A. 空气')
  await expect(question).toContainText('B. 液氯')
  await expect(question).toContainText('学生选择')
  await expect(question).toContainText('正确答案')
  await expect(question).toContainText('液氯只含 Cl₂ 一种物质')
  await expect(question).toContainText('不确定')

  const redox = page.locator('[data-testid="learning-skill-card"]', { hasText: '氧化还原' })
  await redox.locator('summary').first().click()
  await expect(redox).toContainText('待建立证据')
  await expect(redox).toContainText('真实作答证据即将在这里累积')
  await expect(redox).toContainText('氧化还原电子守恒')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((element) => element.clientWidth))
})

test('guardian sees the same skill facts and exact question evidence without internal notes', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试家长')
  await page.getByLabel('登录码').fill('22222222')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: '学过什么、点亮多少、下一步在哪里' })).toBeVisible({ timeout: 15_000 })
  await expect(page.locator('[data-testid="learning-record-summary"]')).toContainText('点亮一部分')
  const classification = page.locator('[data-testid="learning-skill-card"]', { hasText: '物质的分类' })
  await classification.locator('summary').first().click()
  await classification.locator('[data-testid="learning-question-evidence"]').first().locator('summary').click()
  await expect(classification).toContainText('学生选择')
  await expect(classification).toContainText('正确答案')
  await expect(classification).toContainText('解析与订正')
  await expect(page.locator('body')).not.toContainText('下节课单独追问')
  await expect(page.locator('body')).not.toContainText('11111111')
})

test('expanded learning record stays readable on a compact phone', async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 800 })
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: '我的战绩' }).click()
  const classification = page.locator('[data-testid="learning-skill-card"]', { hasText: '物质的分类' })
  await classification.locator('summary').first().click()
  await classification.locator('[data-testid="learning-question-evidence"]').first().locator('summary').click()
  await expect(classification).toContainText('解析与订正')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((element) => element.clientWidth))
})

test('a full zero-forgetting card pairs every redox point with a demo and visual flow', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.locator('.plan-day').nth(1).click()
  await expect(page.getByRole('heading', { name: '氧化还原：把电子转移的逻辑完整接起来' })).toBeVisible()
  const redoxFigure = page.locator('figure[aria-label="氧化还原反应双轨关系与电子守恒图"]')
  await expect(redoxFigure).toBeVisible()
  await expect(redoxFigure).toContainText('氧化轨｜升价 → 失电子')
  await expect(redoxFigure).toContainText('失电子总数')
  await expect(redoxFigure).toContainText('得电子总数')
  await expect(page.locator('.classification-map')).not.toBeVisible()
  await page.locator('.full-explanation > summary').click()
  await expect(page.locator('.classification-item')).toHaveCount(4)
  await expect(page.locator('.classification-item .point-demo')).toHaveCount(4)
  await expect(page.locator('.classification-item .memory-diagram')).toHaveCount(4)
  await expect(page.locator('.classification-map')).toContainText('Fe由+2到+3失1e⁻')
  await expect(page.locator('.classification-map')).toContainText('标价')
  await expect(page.locator('.classification-map')).toContainText('最小公倍数')
  const balanceFigure = page.getByRole('figure', { name: '酸性高锰酸根与亚铁离子配平五步图' })
  await expect(balanceFigure).toBeVisible()
  await expect(balanceFigure).toContainText('MnO₄⁻ ∶ Fe²⁺ ＝ 1 ∶ 5')
  await expect(balanceFigure).toContainText('发生氧化反应')
  await expect(balanceFigure).toContainText('MnO₄⁻ + 5Fe²⁺ + 8H⁺ → Mn²⁺ + 5Fe³⁺ + 4H₂O')
  await expect(balanceFigure).not.toContainText('这段长文字必须由图解替代')
  await balanceFigure.scrollIntoViewIfNeeded()
  await expect(balanceFigure).toBeInViewport()
  const figureFits = await balanceFigure.evaluate((element) => {
    const rect = element.getBoundingClientRect()
    return rect.left >= 0 && rect.right <= document.documentElement.clientWidth
      && element.scrollWidth <= element.clientWidth
  })
  expect(figureFits).toBe(true)
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('all six quick visual types render without adding student-side text work', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.locator('.plan-day').nth(2).click()
  for (const kind of ['tree', 'flow', 'cycle', 'compare', 'network', 'balance']) {
    const genericOrDedicatedFigure = page.locator(`.quick-visual-${kind}, .knowledge-explainer > figure:not(.quick-visual)`).first()
    await expect(genericOrDedicatedFigure).toBeVisible()
    await expect(page.locator('.quick-recall')).toHaveCount(0)
    await expect(page.locator('.knowledge-card .core-rule')).toHaveCount(0)
    await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
    if (kind !== 'balance') await page.getByRole('button', { name: '下一张' }).click()
  }
})

test('periodic law first screen includes compound and hydride trend evidence', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.locator('.plan-day').nth(3).click()
  const map = page.locator('.periodic-trend-visual')
  for (const formula of ['Na₂O', 'P₄O₁₀（常简写P₂O₅）', 'Cl₂O₇', 'NaOH', 'Al(OH)₃', 'HClO₄']) {
    await expect(map).toContainText(formula)
  }
  await expect(map).toContainText('SiH₄ ＜ PH₃ ＜ H₂S ＜ HCl')
  await expect(map).toContainText('HF ＞ HCl ＞ HBr ＞ HI')
  await expect(map).toContainText('同周期气态氢化物热稳定性')
  await expect(map).toContainText('同主族氢化物热稳定性')
  await page.locator('.full-explanation > summary').click()
  await expect(page.locator('.classification-map')).toContainText('SiO₂不能直接与水生成H₂SiO₃')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('teacher name and code use the same entry and open the private workspace', async ({ page }) => {
  test.setTimeout(90_000)
  const forbiddenWrites: string[] = []
  page.on('request', (request) => {
    if (request.method() !== 'POST') return
    const body = request.postDataJSON() as { action?: string }
    if (body.action === 'submit_attempt') forbiddenWrites.push(body.action)
  })
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('任意检查名称')
  await page.getByLabel('登录码').fill(TEST_TEACHER_CODE)
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page).toHaveURL(/\/teacher$/)
  await expect(page.getByRole('heading', { name: '今天最值得看的事' })).toBeVisible()
  await expect(page.getByRole('heading', { name: '今日即时小测' })).toBeVisible()
  await expect(page.getByText('测试学生 · 第2轮')).toBeVisible()
  await expect(page.getByText('甘老师工作台')).toBeVisible()
  await expect(page.getByLabel('教师邮箱')).toHaveCount(0)
  await expect(page.getByText('白名单')).toHaveCount(0)
  await expect(page.getByText('登录链接')).toHaveCount(0)
  await expect(page.getByRole('button', { name: '退出登录' })).toBeVisible()
  await page.getByRole('button', { name: '课堂记录' }).click()
  await expect(page.getByRole('heading', { name: '快速课堂记录' })).toBeVisible()
  await page.getByRole('button', { name: '学生档案' }).click()
  await expect(page.getByRole('heading', { name: '学生与家长档案' })).toBeVisible()
  await expect(page.getByText('测试妈妈')).toBeVisible()
  await expect(page.getByText('测试爸爸')).toBeVisible()
  const gradeFilter = page.getByRole('group', { name: '按年级筛选学生' })
  await gradeFilter.getByRole('button', { name: /^高三/ }).click()
  await expect(page.getByText('高三测试学生')).toBeVisible()
  await expect(page.getByText('高二测试学生')).toHaveCount(0)
  await gradeFilter.getByRole('button', { name: /^全部/ }).click()
  await page.getByRole('button', { name: '模拟查看测试学生的学生端' }).click()
  await expect(page.getByRole('heading', { name: '模拟学生端' })).toBeVisible()
  await expect(page.getByText('安全预览，不写入真人记录')).toBeVisible()
  await page.getByRole('button', { name: /打开完整模拟学生界面/ }).click()
  await expect(page).toHaveURL(/\/teacher\/preview\/demo$/)
  await expect(page.getByText(/甘老师只读模拟/)).toBeVisible()
  await expect(page.getByRole('button', { name: '账户设置' })).toHaveCount(0)
  await page.getByRole('button', { name: '我的战绩' }).click()
  await expect(page.getByText('只读学习证据')).toBeVisible()
  const previewSkill = page.locator('[data-testid="learning-skill-card"]', { hasText: '物质的分类' })
  await previewSkill.locator('summary').first().click()
  await expect(previewSkill).toContainText('下列物质属于纯净物的是')
  expect(forbiddenWrites).toEqual([])
  await page.getByRole('button', { name: '今天', exact: true }).click()
  await page.locator('.focus-card').getByRole('button', { name: /开始第一轮/ }).click()
  await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()
  await page.getByRole('button', { name: /我理解了，开始练习/ }).click()
  for (let index = 0; index < 5; index += 1) {
    await page.locator('.option-list button').nth(1).click()
    await page.getByRole('button', { name: '提交答案' }).click()
    await expect(page.locator('.answer-feedback')).toContainText('判断正确')
    if (index < 4) await page.getByRole('button', { name: '下一题' }).click()
  }
  await page.getByRole('button', { name: '完成第 1 轮' }).click()
  await expect(page.getByText('演示第 1 轮完成')).toBeVisible()
  expect(forbiddenWrites).toEqual([])
  await page.getByRole('button', { name: '返回演示计划' }).click()
  await page.getByRole('button', { name: /返回教师后台/ }).click()
  await expect(page).toHaveURL(/\/teacher$/)
  await page.getByRole('button', { name: '课程节点审核' }).click()
  await expect(page.getByRole('heading', { name: '课程节点审核' })).toBeVisible()
  await page.getByRole('button', { name: '题库审核' }).click()
  await expect(page.getByRole('heading', { name: '题库审核' })).toBeVisible()
  await page.getByRole('button', { name: '权限与访问码' }).click()
  await expect(page.getByRole('heading', { name: '权限与访问码' })).toBeVisible()
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

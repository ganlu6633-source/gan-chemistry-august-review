import { expect, test } from '@playwright/test'

const reviewPlans = Array.from({ length: 40 }, (_, index) => {
  const date = new Date(Date.UTC(2026, 7, 15 + index)).toISOString().slice(0, 10)
  return { id: `p${index + 1}`, studentId: 'demo', date, mode: 'REVIEW', title: `第${index + 1}天复习`, skillIds: ['H1-CLASSIFY'], knowledgeSummaries: ['分类依据', '氧化物判别', '常见误区'], estimatedMinutes: 16, source: 'mixed', isScheduled: true, attemptCount: 0, firstScore: null, latestScore: null, latestCompletedAt: null }
})

const studentDashboard = {
  profile: { id: 'demo', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: reviewPlans,
  skillStates: [{ studentId:'demo', skillId:'H1-CLASSIFY', verifiedLevel:2, candidateLevel:3, maxLevel:4, stability:'verified', evidence:[], consecutiveErrors:0, nextReviewAt:null, reviewIntervalIndex:1, lastReviewedAt:null, teacherIntervention:false }],
  skillDefinitions: [{ id:'H1-CLASSIFY', title:'物质分类', moduleId:'F01', gradeBand:'高一', maxLevel:4, examImportance:5, examDepth:3, prerequisites:[], levelCriteria:[] }],
  todayQuestionCount: 6,
  achievements: [{ id:'a1', title:'物质分类 L2 已点亮', description:'真棒，通过了L2的检验。', earnedAt:'2026-08-12T08:00:00Z' }],
}

const guardianDashboard = {
  student: { displayName: '测试学生', gradeBand: '高一' }, weeklyCompleted: 5, weeklyPlanned: 6, stableSkillCount: 2, growingSkillCount: 1, forgottenSkillCount: 1, teacherAttentionCount: 1,
  progress: ['氧化物定义经过两次新母题检验后已经稳定。'], concerns: ['交叉分类仍需继续巩固，系统已经安排同技能新题。'],
  behaviorSignals: [], timeline: [{ id:'t1', at:'2026-08-12T08:00:00Z', type:'progress', title:'通过氧化物定义检验', description:'系统记录了两个独立证据。' }],
}

const teacherDashboard = {
  students: [{ id:'demo', displayName:'测试学生', gradeBand:'高一', status:'active', needsInitialDiagnostic:false, guardianNames:['测试家长'], curriculumCohort:'high1_completed', planDays:40 }],
  alerts: [], dailySummary: { generatedAt:'2026-08-12T01:00:00Z', classQuizCount:0, reviewCount:1, interventionCount:0 },
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
    workedExamples: [{ substance: 'FeS₂被O₂氧化', path: '标价→升降电子数→最小公倍数→补介质→三重守恒。', labels: ['标价', '电子数', '60', '守恒'] }],
    checkpoints: ['我能正确标价。', '我能计算一个粒子的电子数。', '我会用最小公倍数定系数。', '我会做三类守恒检查。'],
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
  await page.route('**/functions/v1/chemistry-access', async (route) => {
    const responseHeaders = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { ...responseHeaders, 'Access-Control-Allow-Headers': 'apikey,content-type,x-app-session' } })
      return
    }
    const body = route.request().postDataJSON() as { action: string; name?: string; code?: string; data?: { planId?: string } }
    if (body.action === 'login') {
      if (body.code === '33333333') {
        await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ session: { role: 'teacher', token: 'teacher-test-token', displayName: '甘老师', expiresAt: '2099-01-01T00:00:00Z' } }) })
        return
      }
      const guardian = body.code === '22222222'
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ session: { role: guardian ? 'guardian' : 'student', token: 'test-token', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }, dashboard: guardian ? guardianDashboard : studentDashboard }) })
      return
    }
    if (body.action === 'start_plan') {
      const useRedox = body.data?.planId === 'p2'
      const useVisualKinds = body.data?.planId === 'p3'
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ payload: { plan: useVisualKinds ? reviewPlans[2] : useRedox ? reviewPlans[1] : reviewPlans[0], cards: useVisualKinds ? visualKindCards : [useRedox ? redoxCard : classificationCard], questions: [classificationQuestion], attemptSequence: 0 } }) })
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
    const body = route.request().postDataJSON() as { action: string }
    const response = body.action === 'list_course_nodes' ? { nodes: [] } : body.action === 'list_questions' ? { questions: [] } : { dashboard: teacherDashboard }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify(response) })
  })
})

test('access page contains name and code inputs with no role selector', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await expect(page.getByLabel('输入姓名')).toHaveCount(1)
  await expect(page.getByPlaceholder('请输入姓名')).toHaveCount(1)
  await expect(page.getByLabel('登录码')).toHaveCount(1)
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

test('student code routes to student experience without guardian entry', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: /测试学生，今天先把/ })).toBeVisible()
  await expect(page.getByRole('button', { name: /能力星图/ })).toBeVisible()
  await expect(page.getByText('家长端')).toHaveCount(0)
  await page.getByRole('button', { name: /学习计划/ }).click()
  await expect(page.locator('.plan-day')).toHaveCount(40)
  await expect(page.locator('.week-card')).toHaveCount(7)
  await expect(page.locator('.page-title')).toContainText('8月15日—9月23日')
  await expect(page.locator('.page-title')).toContainText('8月15日是复习第1天')
  await expect(page.locator('.plan-day').first()).toContainText('08-15 · 周六')
  await expect(page.locator('.plan-day').last()).toContainText('09-23 · 周三')
  await expect(page.locator('.plan-day').first().locator('li')).toHaveCount(3)
  await page.locator('.plan-day').first().click()
  await expect(page.getByRole('heading', { name: '物质到底分成哪些？从总树干一路分到底' })).toBeVisible()
  await expect(page.locator('.quick-visual-tree')).toBeVisible()
  await expect(page.locator('.quick-visual-tree')).toContainText('物质分类总树')
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

test('guardian code routes directly to the concise guardian explanation', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试家长')
  await page.getByLabel('登录码').fill('22222222')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: '测试学生的化学成长说明' })).toBeVisible()
  await expect(page.getByText('真实问题不回避')).toBeVisible()
  await expect(page.locator('body')).not.toContainText('下节课单独追问')
})

test('a full zero-forgetting card pairs every redox point with a demo and visual flow', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: /学习计划/ }).click()
  await page.locator('.plan-day').nth(1).click()
  await expect(page.getByRole('heading', { name: '氧化还原：把电子转移的逻辑完整接起来' })).toBeVisible()
  await expect(page.locator('.quick-visual-balance')).toContainText('氧化还原电子天平')
  await expect(page.locator('.quick-visual-balance')).toContainText('升价｜失电子')
  await expect(page.locator('.quick-visual-balance')).toContainText('e⁻总数相等')
  await expect(page.locator('.classification-map')).not.toBeVisible()
  await page.locator('.full-explanation > summary').click()
  await expect(page.locator('.classification-item')).toHaveCount(4)
  await expect(page.locator('.classification-item .point-demo')).toHaveCount(4)
  await expect(page.locator('.classification-item .memory-diagram')).toHaveCount(4)
  await expect(page.locator('.classification-map')).toContainText('Fe由+2到+3失1e⁻')
  await expect(page.locator('.classification-map')).toContainText('标价')
  await expect(page.locator('.classification-map')).toContainText('最小公倍数')
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('all six quick visual types render without adding student-side text work', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await page.getByRole('button', { name: /学习计划/ }).click()
  await page.locator('.plan-day').nth(2).click()
  for (const kind of ['tree', 'flow', 'cycle', 'compare', 'network', 'balance']) {
    await expect(page.locator(`.quick-visual-${kind}`)).toBeVisible()
    await expect(page.locator('.quick-recall')).toHaveCount(0)
    await expect(page.locator('.knowledge-card .core-rule')).toHaveCount(0)
    await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
    if (kind !== 'balance') await page.getByRole('button', { name: '下一张' }).click()
  }
})

test('teacher name and code use the same entry and open the private workspace', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('输入姓名').fill('甘老师')
  await page.getByLabel('登录码').fill('33333333')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page).toHaveURL(/\/teacher$/)
  await expect(page.getByRole('heading', { name: '今天最值得看的事' })).toBeVisible()
  await expect(page.getByText('甘老师工作台')).toBeVisible()
  await expect(page.getByLabel('教师邮箱')).toHaveCount(0)
  await expect(page.getByText('白名单')).toHaveCount(0)
  await expect(page.getByText('登录链接')).toHaveCount(0)
  await expect(page.getByRole('button', { name: '退出登录' })).toBeVisible()
  await page.getByRole('button', { name: '课堂记录' }).click()
  await expect(page.getByRole('heading', { name: '快速课堂记录' })).toBeVisible()
  await page.getByRole('button', { name: '学生档案' }).click()
  await expect(page.getByRole('heading', { name: '学生与家长档案' })).toBeVisible()
  await page.getByRole('button', { name: '计划编辑器' }).click()
  await expect(page.getByRole('heading', { name: '学习计划编辑器' })).toBeVisible()
  await page.getByRole('button', { name: '题库审核' }).click()
  await expect(page.getByRole('heading', { name: '题库审核' })).toBeVisible()
  await page.getByRole('button', { name: '权限与访问码' }).click()
  await expect(page.getByRole('heading', { name: '权限与访问码' })).toBeVisible()
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

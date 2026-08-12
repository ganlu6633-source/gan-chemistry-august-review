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
    version: 1, intro: '假设你现在完全不记得：从最上面的物质开始，一层一层往下走。',
    rootTree: { label: '物质', rule: '先按样品中有几种物质分类。', children: [
      { label: '混合物', rule: '含两种或两种以上物质。', examples: ['空气', '盐酸'] },
      { label: '纯净物', rule: '只含一种物质。', children: [
        { label: '单质', rule: '纯净物中只含一种元素。' },
        { label: '化合物', rule: '纯净物中含两种或两种以上元素。', children: [
          { label: '无机化合物', rule: '本讲继续分氧化物、酸、碱和盐。' },
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
        { label: '按溶解性', rule: '分易溶、微溶和难溶。', caution: 'Ca(OH)₂微溶但属于强碱。' },
      ] },
    ],
    workedExamples: [{ substance: 'H₂SO₄', path: '纯净物 → 化合物 → 无机化合物 → 酸', labels: ['二元酸', '强酸', '含氧酸'] }],
    checkpoints: ['我能画出物质分类总树。'],
  },
}

const classificationQuestion = { id:'q-classify', motherId:'m-classify', skillId:'H1_CLASSIFY', level:1, gradeBand:'高一', stem:'物质分类的第一个分叉是', options:['单质和化合物','纯净物和混合物','酸和碱','金属和非金属'], correctOption:1, explanation:'先分纯净物和混合物。', scaffold:'从物质树根开始。', reviewStatus:'approved', scopeStatus:'IN', sourceKind:'teacher_original' }

test.beforeEach(async ({ page }) => {
  await page.route('**/functions/v1/chemistry-access', async (route) => {
    const responseHeaders = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { ...responseHeaders, 'Access-Control-Allow-Headers': 'apikey,content-type,x-app-session' } })
      return
    }
    const body = route.request().postDataJSON() as { action: string; name?: string; code?: string }
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
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ payload: { plan: reviewPlans[0], cards: [classificationCard], questions: [classificationQuestion], attemptSequence: 0 } }) })
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
  await expect(page.getByRole('heading', { name: '物质分类总树' })).toBeVisible()
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

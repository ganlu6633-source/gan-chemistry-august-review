import { expect, test } from '@playwright/test'

const studentDashboard = {
  profile: { id: 'demo', displayName: '测试学生', gradeBand: '高一', enrollmentStartDate: '2026-08-01', needsInitialDiagnostic: false },
  plans: [{ id: 'p1', studentId: 'demo', date: '2026-08-12', mode: 'REVIEW', title: '物质分类与氧化物', skillIds: ['H1-CLASSIFY','H1-OXIDE'], estimatedMinutes: 6, source: 'mixed', isScheduled: true }],
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

test.beforeEach(async ({ page }) => {
  await page.route('**/functions/v1/chemistry-access', async (route) => {
    const responseHeaders = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' }
    if (route.request().method() === 'OPTIONS') {
      await route.fulfill({ status: 204, headers: { ...responseHeaders, 'Access-Control-Allow-Headers': 'apikey,content-type,x-app-session' } })
      return
    }
    const body = route.request().postDataJSON() as { action: string; name?: string; code?: string }
    if (body.action === 'login') {
      const guardian = body.code === '22222222'
      await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ session: { role: guardian ? 'guardian' : 'student', token: 'test-token', displayName: '测试学生', expiresAt: '2099-01-01T00:00:00Z' }, dashboard: guardian ? guardianDashboard : studentDashboard }) })
      return
    }
    await route.fulfill({ status: 200, contentType: 'application/json', headers: responseHeaders, body: JSON.stringify({ dashboard: body.action === 'guardian_dashboard' ? guardianDashboard : studentDashboard }) })
  })
})

test('access page contains name and code inputs with no role selector', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await expect(page.getByLabel('姓名')).toHaveCount(1)
  await expect(page.getByLabel('登录码')).toHaveCount(1)
  await expect(page.getByRole('radio')).toHaveCount(0)
  await expect(page.getByRole('combobox')).toHaveCount(0)
  await expect(page.locator('html')).toHaveJSProperty('scrollWidth', await page.locator('html').evaluate((el) => el.clientWidth))
})

test('student code routes to student experience without guardian entry', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('姓名').fill('测试学生')
  await page.getByLabel('登录码').fill('11111111')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: /测试学生，今天先把/ })).toBeVisible()
  await expect(page.getByRole('button', { name: /能力星图/ })).toBeVisible()
  await expect(page.getByText('家长端')).toHaveCount(0)
})

test('guardian code routes directly to the concise guardian explanation', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/')
  await page.getByLabel('姓名').fill('测试家长')
  await page.getByLabel('登录码').fill('22222222')
  await page.getByRole('button', { name: /进入我的化学世界/ }).click()
  await expect(page.getByRole('heading', { name: '测试学生的化学成长说明' })).toBeVisible()
  await expect(page.getByText('真实问题不回避')).toBeVisible()
  await expect(page.locator('body')).not.toContainText('下节课单独追问')
})

test('teacher route uses independent email authentication', async ({ page }) => {
  await page.goto('/gan-chemistry-august-review/teacher')
  await expect(page.getByRole('heading', { name: '教师工作台' })).toBeVisible()
  await expect(page.getByLabel('教师邮箱')).toBeVisible()
  await expect(page.getByLabel('登录码')).toHaveCount(0)
})

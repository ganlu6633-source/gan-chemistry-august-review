import { readdirSync, readFileSync, statSync } from 'node:fs'
import { dirname, extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { knowledgeVisualSummaries } from './knowledge-visual-summaries.mjs'
import { zeroForgettingCards } from './zero-forgetting-content.mjs'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const roots = ['src', 'scripts', join('supabase', 'migrations')]
const extensions = new Set(['.ts', '.tsx', '.mjs', '.sql'])
const files = []

const collect = (path) => {
  if (statSync(path).isDirectory()) {
    readdirSync(path).forEach((name) => collect(join(path, name)))
    return
  }
  if (extensions.has(extname(path))) files.push(path)
}
roots.forEach((root) => collect(resolve(repoRoot, root)))

const badUnicodeToken = `N${String.fromCodePoint(0x2090)}`
const badPlainToken = new RegExp(`(?<![A-Za-z0-9_])N${'A'}(?=(判断|选择|常数))`, 'gu')
const errors = []
let canonicalTokenCount = 0

for (const path of files) {
  const text = readFileSync(path, 'utf8')
  const relative = path.slice(repoRoot.length + 1)
  if (text.includes(badUnicodeToken)) errors.push(`${relative}: 含Unicode小写下标a`)
  if (badPlainToken.test(text)) errors.push(`${relative}: 含未标下标的阿伏加德罗常数简称`)
  badPlainToken.lastIndex = 0
  canonicalTokenCount += text.split('N_A').length - 1
}

if (canonicalTokenCount < 20) errors.push(`N_A规范令牌数量异常：${canonicalTokenCount}`)

const redox = zeroForgettingCards.find((card) => card.skillId === 'H1_REDOX')
const redoxText = JSON.stringify(redox)
for (const required of [
  '升价→失电子→被氧化→发生氧化反应',
  '还原剂→氧化产物',
  '降价→得电子→被还原→发生还原反应',
  '氧化剂→还原产物',
]) {
  if (!redoxText.includes(required)) errors.push(`H1_REDOX缺少完整链条：${required}`)
}

const redoxVisual = knowledgeVisualSummaries.H1_REDOX
const visualText = JSON.stringify(redoxVisual)
for (const required of ['发生氧化反应', '反应物是还原剂', '生成氧化产物', '发生还原反应', '反应物是氧化剂', '生成还原产物']) {
  if (!visualText.includes(required)) errors.push(`H1_REDOX快速图缺项：${required}`)
}

const moleIntro = zeroForgettingCards.find((card) => card.skillId === 'H1_MOLE_INTRO')
const moleText = JSON.stringify(moleIntro)
for (const required of ['分子', '原子', '离子', '电子', '质子', '中子', '离子晶体的化学式单位', '²³Na', 'NaCl晶体中不存在独立的NaCl分子']) {
  if (!moleText.includes(required)) errors.push(`H1_MOLE_INTRO对象或示范缺项：${required}`)
}

const equilibrium = zeroForgettingCards.find((card) => card.skillId === 'H2_K')
const equilibriumText = JSON.stringify(equilibrium)
for (const required of [
  'aA+bB⇌cC+dD',
  'Kc=c(C)^c·c(D)^d/[c(A)^a·c(B)^b]',
  '所有浓度取平衡值',
  '省略纯固体和纯液体',
]) {
  if (!equilibriumText.includes(required)) errors.push(`H2_K平衡常数表达式缺项：${required}`)
}

const equilibriumVisualPath = resolve(repoRoot, 'src', 'components', 'EquilibriumConstantFormulaVisual.tsx')
const equilibriumVisualText = readFileSync(equilibriumVisualPath, 'utf8')
for (const required of [
  'equilibrium-numerator',
  'equilibrium-denominator',
  '<i>c</i>(C)<sup>c</sup>',
  '<i>c</i>(D)<sup>d</sup>',
  '<i>c</i>(A)<sup>a</sup>',
  '<i>c</i>(B)<sup>b</sup>',
]) {
  if (!equilibriumVisualText.includes(required)) errors.push(`Kc教材式分式图缺项：${required}`)
}

if (errors.length) {
  console.error(`符号与氧化还原逻辑契约失败（${errors.length}项）\n- ${errors.join('\n- ')}`)
  process.exit(1)
}

console.log(JSON.stringify({
  status: 'PASS',
  scannedFiles: files.length,
  canonicalAvogadroTokens: canonicalTokenCount,
  forbiddenNotationHits: 0,
  redoxChains: 2,
  particleObjectKinds: 7,
  equilibriumFormulaDisplay: 'stacked_fraction',
}, null, 2))

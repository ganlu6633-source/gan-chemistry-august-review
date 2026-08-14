import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs'
import { join, resolve } from 'node:path'

const root = resolve(process.cwd())
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
if (pkg.name !== 'gan-chemistry-learning-system') throw new Error('Refusing to publish outside the expected repository.')
const dist = join(root, 'dist')
if (!existsSync(join(dist, 'index.html'))) throw new Error('Production build is missing dist/index.html.')
const rootAssets = join(root, 'assets')
if (existsSync(rootAssets)) rmSync(rootAssets, { recursive: true, force: true })
for (const name of ['index.html', 'manifest.webmanifest', 'chemistry-icon.svg', 'sw.js', 'assets']) {
  const source = join(dist, name)
  if (existsSync(source)) cpSync(source, join(root, name), { recursive: true })
}
const teacherDir = join(root, 'teacher')
mkdirSync(teacherDir, { recursive: true })
cpSync(join(dist, 'index.html'), join(teacherDir, 'index.html'))
// GitHub Pages serves this fallback for direct visits to nested SPA routes such as
// /teacher/preview/:studentId, allowing React Router to restore the intended view.
cpSync(join(dist, 'index.html'), join(root, '404.html'))
console.log('Published the verified dist bundle to the GitHub Pages root.')

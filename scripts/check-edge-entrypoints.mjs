import { readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { build } from 'esbuild'

const functionsRoot = resolve('supabase/functions')
const entryPoints = readdirSync(functionsRoot, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => resolve(functionsRoot, entry.name, 'index.ts'))

await build({
  entryPoints,
  bundle: true,
  write: false,
  outdir: resolve('.edge-build-check'),
  platform: 'neutral',
  format: 'esm',
  target: 'es2022',
  external: ['https://*', 'jsr:*'],
  logLevel: 'error',
})

console.log(`Edge entrypoint syntax/build check passed (${entryPoints.length} functions).`)

import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react(), {
    name: 'publish-index-name',
    enforce: 'post',
    generateBundle(_options, bundle) {
      const entry = bundle['app.html']
      if (!entry) return
      entry.fileName = 'index.html'
      bundle['index.html'] = entry
      delete bundle['app.html']
    },
  }],
  base: '/gan-chemistry-august-review/',
  build: { sourcemap: true, rollupOptions: { input: 'app.html' } },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx'],
    setupFiles: './src/test/setup.ts',
    coverage: { reporter: ['text', 'json', 'html'] },
  },
})

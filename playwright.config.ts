import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  // Eight concurrent WebKit instances intermittently starve the Windows CI
  // host and turn ordinary post-login clicks into 30-second timeouts. Four
  // still exercises tests in parallel without making the mobile-iOS project
  // depend on scheduler luck.
  workers: 4,
  forbidOnly: true,
  retries: 1,
  reporter: [['html', { open: 'never' }], ['list']],
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'on-first-retry' },
  webServer: {
    // `pnpm` may perform package-manager policy/network verification before it
    // runs a script. The E2E harness must use the already-installed workspace
    // binaries so an offline verification retry cannot consume this timeout.
    command: 'npm run build && npm run preview -- --host 127.0.0.1',
    url: 'http://127.0.0.1:4173/gan-chemistry-august-review/',
    reuseExistingServer: true,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium-desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile-compact-360', use: { ...devices['Pixel 5'], viewport: { width: 360, height: 800 } } },
    { name: 'mobile-android', use: { ...devices['Pixel 7'] } },
    { name: 'mobile-ios', use: { ...devices['iPhone 13'] } },
  ],
})

import { chromium, devices } from '@playwright/test'
import { mkdir } from 'node:fs/promises'
import { preview } from 'vite'

const base = 'http://localhost:4173/gan-chemistry-august-review/'
await mkdir('test-results/visual', { recursive: true })
const server = await preview({ preview: { host: 'localhost', port: 4173 } })
const browser = await chromium.launch()

async function capture(name, options, code) {
  const context = await browser.newContext(options)
  const page = await context.newPage()
  const errors = []
  page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()) })
  page.on('pageerror', (error) => errors.push(error.message))
  await page.goto(base, { waitUntil: 'networkidle' })
  if (code) {
    await page.getByLabel('访问码').fill(code)
    await page.getByRole('button', { name: /进入我的化学世界/ }).click()
    try {
      await page.waitForSelector(code === '22222222' ? '.guardian-dashboard' : '.student-theme', { timeout: 15000 })
    } catch (error) {
      console.error(JSON.stringify({ name, errors, body: await page.locator('body').innerText() }))
      throw error
    }
  }
  await page.screenshot({ path: `test-results/visual/${name}.png`, fullPage: true })
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  console.log(JSON.stringify({ name, errors, overflow, title: await page.title() }))
  await context.close()
}

await capture('desktop-login', { viewport: { width: 1440, height: 1000 } })
await capture('desktop-student', { viewport: { width: 1440, height: 1000 } }, '11111111')
await capture('desktop-guardian', { viewport: { width: 1440, height: 1000 } }, '22222222')
await capture('mobile-student', devices['Pixel 7'], '11111111')
await capture('mobile-guardian', devices['Pixel 7'], '22222222')
await browser.close()
await server.close()

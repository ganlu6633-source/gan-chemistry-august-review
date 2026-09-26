import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const state = 'chemistry_registration'
const corpId = process.env.WECOM_CORP_ID
const secret = process.env.WECOM_CONTACT_SECRET
const member = process.env.WECOM_MEMBER_USER_ID
if (!corpId || !secret || !member) {
  throw new Error('Set WECOM_CORP_ID, WECOM_CONTACT_SECRET and WECOM_MEMBER_USER_ID in this shell before creating the QR.')
}

const publicDir = resolve('public')
const metadataFile = resolve(publicDir, 'wecom-contact-way.json')
try {
  await readFile(metadataFile)
  throw new Error('Contact QR metadata already exists. Reuse the current QR instead of creating another one.')
} catch (error) {
  if (error?.code !== 'ENOENT') throw error
}

async function wecomJson(url, body) {
  const response = await fetch(url, body ? {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  } : undefined)
  if (!response.ok) throw new Error(`WeCom API HTTP ${response.status}`)
  const data = await response.json()
  if (data.errcode !== 0) throw new Error(`WeCom API error ${data.errcode}`)
  return data
}

const tokenUrl = new URL('https://qyapi.weixin.qq.com/cgi-bin/gettoken')
tokenUrl.searchParams.set('corpid', corpId)
tokenUrl.searchParams.set('corpsecret', secret)
const { access_token: token } = await wecomJson(tokenUrl)
const createUrl = new URL('https://qyapi.weixin.qq.com/cgi-bin/externalcontact/add_contact_way')
createUrl.searchParams.set('access_token', token)
const result = await wecomJson(createUrl, {
  type: 1, scene: 2, skip_verify: true, state, user: [member], remark: '甘老师化学网站注册',
})
if (typeof result.config_id !== 'string' || !/^https:\/\//.test(result.qr_code || '')) {
  throw new Error('WeCom did not return a Contact Me QR and config ID.')
}
const image = await fetch(result.qr_code)
if (!image.ok) throw new Error(`QR image HTTP ${image.status}`)
const type = image.headers.get('content-type') || ''
const extension = type.includes('image/png') ? 'png' : type.includes('image/jpeg') ? 'jpg' : null
if (!extension) throw new Error(`Unsupported WeCom QR image content type: ${type}`)
await mkdir(publicDir, { recursive: true })
const imageName = `wecom-contact.${extension}`
await writeFile(resolve(publicDir, imageName), Buffer.from(await image.arrayBuffer()))
await writeFile(metadataFile, `${JSON.stringify({ configId: result.config_id, state, imageName }, null, 2)}\n`)
console.log(`Created website Contact Me QR: public/${imageName}`)
console.log(`WeCom config ID: ${result.config_id}`)

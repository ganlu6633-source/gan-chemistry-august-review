import { createCipheriv, createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { decryptWecomPayload, verifyWecomSignature, xmlTag } from './protocol'

const corpId = 'ww1234567890abcdef'
const token = 'callback-secret'
const key = Buffer.from(Array.from({ length: 32 }, (_, index) => index + 1))
const aesKey = key.toString('base64').slice(0, -1)

function encrypt(xml: string, receiver = corpId) {
  const content = Buffer.from(xml)
  const size = Buffer.alloc(4)
  size.writeUInt32BE(content.length)
  const plain = Buffer.concat([Buffer.alloc(16, 7), size, content, Buffer.from(receiver)])
  const padding = 32 - (plain.length % 32)
  const cipher = createCipheriv('aes-256-cbc', key, key.subarray(0, 16))
  cipher.setAutoPadding(false)
  return Buffer.concat([cipher.update(Buffer.concat([plain, Buffer.alloc(padding, padding)])), cipher.final()]).toString('base64')
}

describe('WeCom callback protocol', () => {
  it('authenticates and decrypts a callback with WeCom 32-byte PKCS#7 padding', () => {
    const xml = '<xml><MsgType><![CDATA[event]]></MsgType><State><![CDATA[chemistry_registration]]></State></xml>'
    const encrypted = encrypt(xml)
    const timestamp = '1790400000'
    const nonce = '123456'
    const signature = createHash('sha1').update([token, timestamp, nonce, encrypted].sort().join('')).digest('hex')
    expect(verifyWecomSignature(token, timestamp, nonce, encrypted, signature)).toBe(true)
    expect(verifyWecomSignature(token, timestamp, nonce, encrypted, '0'.repeat(40))).toBe(false)
    expect(decryptWecomPayload(encrypted, aesKey, corpId)).toBe(xml)
    expect(xmlTag(xml, 'State')).toBe('chemistry_registration')
    expect(() => decryptWecomPayload(encrypted, aesKey, 'wrong-corp')).toThrow('receiver')
  })

  it('handles a 32-byte padding block and rejects malformed ciphertext', () => {
    const xml = 'a'.repeat(32 - ((20 + corpId.length) % 32))
    expect(decryptWecomPayload(encrypt(xml), aesKey, corpId)).toBe(xml)
    expect(() => decryptWecomPayload('not-base64', aesKey, corpId)).toThrow()
  })
})

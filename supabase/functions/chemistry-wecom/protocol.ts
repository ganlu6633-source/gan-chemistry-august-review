import { createDecipheriv, createHash, timingSafeEqual } from "node:crypto";

function fixedTimeEquals(left: string, right: string): boolean {
  const a = Buffer.from(left, "utf8");
  const b = Buffer.from(right, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

export function verifyWecomSignature(
  token: string,
  timestamp: string,
  nonce: string,
  encrypted: string,
  signature: string,
): boolean {
  if (!token || !/^\d{1,20}$/.test(timestamp) || !/^[\w-]{1,128}$/.test(nonce)
    || !encrypted || !/^[0-9a-f]{40}$/i.test(signature)) return false;
  const expected = createHash("sha1").update([token, timestamp, nonce, encrypted].sort().join("")).digest("hex");
  return fixedTimeEquals(expected, signature.toLowerCase());
}

export function decryptWecomPayload(encrypted: string, encodingAesKey: string, expectedCorpId: string): string {
  if (!/^[A-Za-z0-9+/]{43}$/.test(encodingAesKey)) throw new Error("Invalid WeCom AES key");
  const key = Buffer.from(`${encodingAesKey}=`, "base64");
  if (key.length !== 32) throw new Error("Invalid WeCom AES key length");
  const ciphertext = Buffer.from(encrypted, "base64");
  if (!ciphertext.length || ciphertext.length % 16 !== 0) throw new Error("Invalid WeCom ciphertext");
  const decipher = createDecipheriv("aes-256-cbc", key, key.subarray(0, 16));
  decipher.setAutoPadding(false);
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  const padding = decrypted.at(-1) || 0;
  if (padding < 1 || padding > 32 || padding > decrypted.length) throw new Error("Invalid WeCom padding");
  for (let index = decrypted.length - padding; index < decrypted.length; index++) {
    if (decrypted[index] !== padding) throw new Error("Invalid WeCom padding");
  }
  const plaintext = decrypted.subarray(0, decrypted.length - padding);
  if (plaintext.length < 21) throw new Error("Invalid WeCom payload length");
  const xmlLength = plaintext.readUInt32BE(16);
  if (xmlLength < 1 || 20 + xmlLength > plaintext.length) throw new Error("Invalid WeCom message length");
  const receiver = plaintext.subarray(20 + xmlLength).toString("utf8");
  if (receiver !== expectedCorpId) throw new Error("Invalid WeCom receiver");
  return plaintext.subarray(20, 20 + xmlLength).toString("utf8");
}

export function xmlTag(xml: string, name: string): string | null {
  if (!/^[A-Za-z][A-Za-z0-9]*$/.test(name)) throw new Error("Invalid XML tag");
  const match = xml.match(new RegExp(`<${name}>([\\s\\S]*?)<\\/${name}>`));
  if (!match) return null;
  const value = match[1].trim();
  const raw = value.startsWith("<![CDATA[") && value.endsWith("]]>") ? value.slice(9, -3) : value;
  return raw.replace(/&lt;|&gt;|&amp;|&quot;|&apos;/g, (entity) => ({
    "&lt;": "<", "&gt;": ">", "&amp;": "&", "&quot;": '"', "&apos;": "'",
  })[entity] || entity);
}

export function shouldIssueInviteForContact(
  member: string,
  expectedMember: string,
  state: string | null,
  allowAllNewContacts: boolean,
): boolean {
  if (!member || !expectedMember || member !== expectedMember) return false;
  return allowAllNewContacts || state === "chemistry_registration";
}

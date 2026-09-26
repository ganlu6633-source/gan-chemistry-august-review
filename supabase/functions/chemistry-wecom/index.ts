import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { createHash, createHmac } from "node:crypto";
import { decryptWecomPayload, shouldIssueInviteForContact, verifyWecomSignature, xmlTag } from "./protocol.ts";

const SITE_URL = "https://ganlu6633-source.github.io/gan-chemistry-august-review/";
const INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
let tokenCache: { value: string; expiresAt: number } | null = null;

function config() {
  const corpId = Deno.env.get("WECOM_CORP_ID") || "";
  const contactSecret = Deno.env.get("WECOM_CONTACT_SECRET") || "";
  const callbackToken = Deno.env.get("WECOM_CALLBACK_TOKEN") || "";
  const callbackAesKey = Deno.env.get("WECOM_CALLBACK_AES_KEY") || "";
  const memberUserId = Deno.env.get("WECOM_MEMBER_USER_ID") || "";
  const allowUntagged = Deno.env.get("WECOM_INVITE_UNTAGGED_CONTACTS") === "true";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  if (!corpId || !contactSecret || !callbackToken || !callbackAesKey || !memberUserId || !serviceKey || !supabaseUrl) return null;
  return { corpId, contactSecret, callbackToken, callbackAesKey, memberUserId, allowUntagged, serviceKey, supabaseUrl };
}

function eventIdentity(corpId: string, member: string, external: string, created: string): string {
  return createHash("sha256")
    .update(`wecom-contact-add-v1:${corpId}:${member}:${external}:${created}`)
    .digest("hex");
}

function invitationCode(secret: string, eventHash: string): string {
  const digest = createHmac("sha256", secret).update(`wecom-invite-code-v1:${eventHash}`).digest();
  return Array.from(digest.subarray(0, 10), (byte) => INVITE_ALPHABET[byte & 31]).join("");
}

function invitationHash(secret: string, code: string): string {
  return createHmac("sha256", secret).update(`chem-registration-invite-v1:${code}`).digest("hex");
}

async function accessToken(corpId: string, contactSecret: string): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now()) return tokenCache.value;
  const url = new URL("https://qyapi.weixin.qq.com/cgi-bin/gettoken");
  url.searchParams.set("corpid", corpId);
  url.searchParams.set("corpsecret", contactSecret);
  const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error("WeCom token request failed");
  const data = await response.json();
  if (data.errcode !== 0 || typeof data.access_token !== "string") throw new Error(`WeCom token error ${data.errcode}`);
  tokenCache = { value: data.access_token, expiresAt: Date.now() + Math.max(60, Number(data.expires_in || 7200) - 300) * 1000 };
  return tokenCache.value;
}

async function sendWelcome(token: string, welcomeCode: string, invitation: string): Promise<void> {
  const link = `${SITE_URL}#invite=${invitation}`;
  const response = await fetch(`https://qyapi.weixin.qq.com/cgi-bin/externalcontact/send_welcome_msg?access_token=${encodeURIComponent(token)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      welcome_code: welcomeCode,
      text: { content: `欢迎来到甘老师化学！你的专属邀请码：${invitation}\n点击下方卡片申请账号，邀请码会自动填好。24 小时内有效，只能使用一次；提交后老师会核对身份和学习进度。` },
      attachments: [{ msgtype: "link", link: { title: "申请甘老师化学账号", url: link, desc: "邀请码已自动填写，点击继续注册" } }],
    }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error("WeCom welcome request failed");
  const data = await response.json();
  // If delivery succeeded but recording it failed, WeCom rejects the replay.
  // The original one-time link remains valid, so record that as delivered.
  if (data.errcode !== 0 && data.errcode !== 41051) throw new Error(`WeCom welcome error ${data.errcode}`);
}

function parameter(url: URL, name: string): string {
  return url.searchParams.get(name) || "";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });
  const settings = config();
  if (!settings) return new Response("Webhook not configured", { status: 503 });
  try {
    const url = new URL(req.url);
    const timestamp = parameter(url, "timestamp");
    const nonce = parameter(url, "nonce");
    const signature = parameter(url, "msg_signature");
    if (req.method === "GET") {
      const echo = parameter(url, "echostr");
      if (!verifyWecomSignature(settings.callbackToken, timestamp, nonce, echo, signature)) {
        return new Response("Invalid signature", { status: 403 });
      }
      return new Response(decryptWecomPayload(echo, settings.callbackAesKey, settings.corpId), {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    const contentLength = Number(req.headers.get("content-length") || 0);
    if (contentLength > 131072) return new Response("Payload too large", { status: 413 });
    const body = await req.text();
    if (body.length > 131072) return new Response("Payload too large", { status: 413 });
    const encrypted = xmlTag(body, "Encrypt") || "";
    if (!verifyWecomSignature(settings.callbackToken, timestamp, nonce, encrypted, signature)) {
      return new Response("Invalid signature", { status: 403 });
    }
    const message = decryptWecomPayload(encrypted, settings.callbackAesKey, settings.corpId);
    const changeType = xmlTag(message, "ChangeType");
    if (xmlTag(message, "MsgType") !== "event" || xmlTag(message, "Event") !== "change_external_contact"
      || (changeType !== "add_external_contact" && changeType !== "add_half_external_contact")) return new Response("success");
    const member = xmlTag(message, "UserID") || "";
    if (!shouldIssueInviteForContact(member, settings.memberUserId, xmlTag(message, "State"), settings.allowUntagged)) {
      return new Response("success");
    }
    const external = xmlTag(message, "ExternalUserID") || "";
    const created = xmlTag(message, "CreateTime") || "";
    const welcomeCode = xmlTag(message, "WelcomeCode") || "";
    if (!member || !external || !/^\d{1,20}$/.test(created) || !welcomeCode) {
      console.error("WeCom registration event is missing a required field");
      return new Response("Incomplete registration event", { status: 422 });
    }
    const eventHash = eventIdentity(settings.corpId, member, external, created);
    const eventCode = invitationCode(settings.serviceKey, eventHash);
    const externalHash = createHmac("sha256", settings.serviceKey).update(`wecom-external-v1:${external}`).digest("hex");
    const admin = createClient(settings.supabaseUrl, settings.serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: invite, error: createError } = await admin.rpc("chem_create_wecom_registration_invite", {
      p_code_hash: invitationHash(settings.serviceKey, eventCode),
      p_external_hash: externalHash,
      p_event_hash: eventHash,
    });
    if (createError || !invite?.id) throw new Error("Could not create WeCom invitation");
    if (!invite.shouldSend) return new Response("success");
    if (typeof invite.eventHash !== "string" || !/^[0-9a-f]{64}$/.test(invite.eventHash)) {
      throw new Error("WeCom invitation has no event identity");
    }
    const code = invitationCode(settings.serviceKey, invite.eventHash);
    const token = await accessToken(settings.corpId, settings.contactSecret);
    await sendWelcome(token, welcomeCode, code);
    const { error: markError } = await admin.rpc("chem_mark_wecom_welcome_sent", { p_invite_id: invite.id });
    if (markError) throw new Error("Could not mark WeCom welcome delivered");
    return new Response("success");
  } catch (error) {
    console.error("WeCom callback failed:", error instanceof Error ? error.message : "unknown error");
    return new Response("Callback failed", { status: 500 });
  }
});

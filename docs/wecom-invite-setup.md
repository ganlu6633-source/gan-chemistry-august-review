# 企业微信自动邀请码接入

网站的企微回调地址：`https://phdleezffrqqzyveicrm.supabase.co/functions/v1/chemistry-wecom`。
该地址只接受企业微信签名并加密的回调；没有配置密钥时返回 503，不会发邀请码。

## 企业微信管理后台

1. 确认甘老师的成员账号已激活、完成实名认证、可使用「客户联系」，并在用于调用接口的自建应用可见范围内。
2. 在「客户联系 → 可调用接口的应用」加入该自建应用。使用这个应用可调用客户联系接口的 Secret，不要使用个人微信或名片二维码代替。
3. 在客户联系的事件回调中设置上面的 URL，生成 Token 和 43 位 EncodingAESKey。订阅新增客户事件。用于欢迎消息的固定欢迎语需要关闭，否则新增事件可能没有 `WelcomeCode`。
4. 在 Supabase 项目的 Edge Functions Secrets 中设置 `WECOM_CORP_ID`、`WECOM_CONTACT_SECRET`、`WECOM_CALLBACK_TOKEN`、`WECOM_CALLBACK_AES_KEY`、`WECOM_MEMBER_USER_ID`。不要把任何 Secret 填入网页、提交到 Git 或发在聊天里。Supabase 自动提供 `SUPABASE_URL` 和 `SUPABASE_SERVICE_ROLE_KEY`。
5. 选择发码范围。若使用已有的企业微信**个人名片**二维码，并同意所有新添加甘老师的客户都收到网站邀请码，另设 `WECOM_INVITE_UNTAGGED_CONTACTS=true`。服务端仍只接受指定成员 `UserID` 的新增客户事件；其他成员、其他渠道标识的事件不会发码。若只给从网站来的学生和家长发码，则保持该开关关闭，用企业微信「联系我」接口创建网站专用二维码：`type=1`、`scene=2`、`skip_verify=true`、`state=chemistry_registration`、`user=[甘老师的 UserID]`。本仓库的 `scripts/create-wecom-contact-way.mjs` 可创建并下载此码，随后替换注册页图片。

## 行为与验收

- 新客户添加甘老师时，企业微信回调带回新增客户事件及可能出现的一次性 `WelcomeCode`。网站专用码的事件带 `State=chemistry_registration`；个人名片方式通常没有该渠道标识，因此只能在明确开启无标识发码开关后处理。服务端验签、解密并核对企业 ID、成员 UserID 后生成 24 小时有效的 10 位邀请码，通过欢迎消息发送可点击的注册链接。相同客户的半客户/正式客户连续事件沿用第一个有效码。
- 学生或家长点开链接后邀请码自动填入。注册申请仍进入老师审核队列；家长绑定孩子必须由老师核对。旧的老师手动邀请码仍按指定身份和手机号使用。
- 验收应使用新的微信账号扫描所选二维码，核对免验证添加、20 秒内收到欢迎消息、注册链接预填、一次使用后失效、后台出现待审核申请。网站专用码模式需确认非网站渠道添加不触发发码；个人名片模式需确认所有新添加指定老师的客户都会收到邀请码。

邀请码链接可以转发。当前方案能证明**邀请码由真实新增客户事件触发**，尚不能证明**填注册表的人就是该客户本人**。若要禁止转发使用，需要另配能通过企业微信可信域名校验的自有域名，以网页授权取得 `external_userid`，与回调联系人比对；现有 GitHub Pages 域名不能直接假定可用于该校验。

官方接口：[配置「联系我」方式](https://developer.work.weixin.qq.com/document/path/92228)、[客户联系回调](https://developer.work.weixin.qq.com/document/path/92130)、[发送新客户欢迎语](https://developer.work.weixin.qq.com/document/path/92599)、[回调验签](https://developer.work.weixin.qq.com/document/path/91116)。

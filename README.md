# 甘老师化学学习系统 V2

一个统一数据层支撑的三角色化学学习系统：

- 学生端：REVIEW 长期复习、CLASS_QUIZ 课堂小测、可点击计划、知识卡、能力星图和成长记录。
- 家长端：30 秒读懂进步、关注点、遗忘回收、行为证据与教师行动，不展示内部标签。
- 教师端：Supabase Auth 魔法链接、学生档案、课堂记录、课程地图审核、题库审核和访问码重置。

## 本地运行

```bash
pnpm install
pnpm dev
```

创建 `.env.local` 并参考 `.env.example`。浏览器端只能使用 Supabase publishable key，任何 service role key 都不得进入前端或仓库。

## 质量检查

```bash
pnpm lint
pnpm test
pnpm test:e2e
pnpm build
```

`pnpm publish:static` 会先生产构建，再把经过构建的静态文件复制到仓库根目录，供当前 GitHub Pages 的 main/root 发布方式使用。源码入口保存在 `app.html`；根目录 `index.html` 是自动生成的生产文件。

## 数据与隐私

- 真实学生档案和访问码明文不进入公开仓库。
- 学生码和家长码完全独立；数据库只保存 bcrypt 强哈希和两位非敏感检索前缀。
- 所有公开 schema 表均启用 RLS，并显式拒绝浏览器直接访问；业务读写只经过职责分离的 Edge Functions。
- 教师内部备注不会进入学生或家长 DTO。
- 商业教辅材料没有复制进本仓库；首发题目为原创或原创变式，并带福建范围状态。

## 回滚

V2 上线前的旧站点已保存在 Git 标签 `pre-v2-20260812`。数据库迁移为新增式，旧表和旧 Edge Function 保留，直到 V2 线上验收完成。

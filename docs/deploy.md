# 部署说明

MVP 使用 GitHub Actions 构建 Flutter Web、Android APK、Windows installer exe/zip、macOS dmg/zip，并把 tag 构建产物上传到 GitHub Releases。所有 Cloudflare 部署通过 GitHub Actions + Wrangler CLI 完成，不依赖 Cloudflare Pages Git 集成。

## 当前 Actions

- `CI`：PR 和 `main` push 时运行 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build web --release`。
- `Deploy web`：`main` push 且 `apps/client/**` 有变更时，Actions 构建 Flutter Web 后通过 `wrangler pages deploy` 部署到 Cloudflare Pages。
- `Deploy worker`：`main` push 且 `workers/api/**` 有变更时，Actions 通过 `wrangler deploy` 发布 Worker API。也支持手动触发。
- `Release`：推送 `v*` tag 后并行构建 Android APK、Windows installer exe/zip、macOS dmg/zip、Web zip。每个平台构建完成后会立刻上传到同一个 GitHub Release；全部平台完成后再生成带 sha256/size 的完整 `update.json`。

## 必需配置

### GitHub Secrets（加密存储）

- `CLOUDFLARE_API_TOKEN`：Cloudflare API Token，需要 `Cloudflare Pages:Edit` 和 `Workers Scripts:Edit` 权限。

### GitHub Variables（非加密）

- `CLOUDFLARE_ACCOUNT_ID`：Cloudflare 账号 ID。

### 创建 Cloudflare API Token

1. 登录 https://dash.cloudflare.com/profile/api-tokens
2. 点击 "Create Token"
3. 使用 "Custom token" 模板
4. 权限设置：
   - Account - Cloudflare Pages - Edit
   - Account - Workers Scripts - Edit
5. 创建后复制 token，配置到两个仓库的 GitHub Secrets

## 还需要人工配置

1. 在 GitHub 仓库配置 `CLOUDFLARE_API_TOKEN` secret 后，Web 和 Worker 部署会在 push 到 `main` 时自动触发。
2. 在 Cloudflare Workers 配置 `workers/api/wrangler.toml` 对应的域名、D1/KV/R2 绑定。
3. 正式分发前补 Android keystore、Windows 代码签名、macOS Developer ID 签名和 notarization。
4. 如需稳定更新地址，把 release 生成的 `update.json` 同步到 Cloudflare Pages/R2 的 `latest.json`。

# 部署说明

MVP 使用 GitHub Actions 构建 Flutter Web、Android APK、Windows installer exe/zip、macOS dmg/zip，并把 tag 构建产物上传到 GitHub Releases。Cloudflare Pages、Workers 和签名密钥通过仓库 Secrets 配置。

## 当前 Actions

- `CI`：PR 和 `main` push 时运行 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build web --release`。
- `Deploy web`：GitHub Actions 只构建并上传 `flutter-web` artifact；正式 Web 部署由 Cloudflare Pages 的 Git 集成监听 `main` 自动完成。
- `Release`：推送 `v*` tag 后并行构建 Android APK、Windows installer exe/zip、macOS dmg/zip、Web zip。每个平台构建完成后会立刻上传到同一个 GitHub Release；全部平台完成后再生成带 sha256/size 的完整 `update.json`。
- `Deploy worker`：手动触发，执行 `wrangler deploy` 发布 Worker API。

必需 Secrets：

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

可选变量：

- `CLOUDFLARE_PAGES_PROJECT_NAME`：Cloudflare Pages 项目名，默认 `mianshi-zhilian-app`。

正式签名发布时再补 Android、macOS、Windows 证书 Secrets。

## 还需要人工配置

1. Cloudflare Pages 项目 `mianshi-zhilian-app` 已关联 `nontracey/mianshi-zhilian-app`，生产分支为 `main`。
2. 在 GitHub 仓库配置 `CLOUDFLARE_API_TOKEN` secret 后，Worker API 会在 `workers/api/**` 变更合并到 `main` 时自动部署。
3. 在 Cloudflare Workers 配置 `workers/api/wrangler.toml` 对应的域名、D1/KV/R2 绑定。
4. 正式分发前补 Android keystore、Windows 代码签名、macOS Developer ID 签名和 notarization。
5. 如需稳定更新地址，把 release 生成的 `update.json` 同步到 Cloudflare Pages/R2 的 `latest.json`。

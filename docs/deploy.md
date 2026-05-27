# 部署说明

MVP 使用 GitHub Actions 构建 Flutter Web、Android APK、Windows zip、macOS zip，并把 tag 构建产物上传到 GitHub Releases。Cloudflare Pages、Workers 和签名密钥通过仓库 Secrets 配置。

## 当前 Actions

- `CI`：PR 和 `main` push 时运行 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build web --release`。
- `Deploy web`：构建 Flutter Web，上传 `flutter-web` artifact；配置 Cloudflare secrets 后会直接执行 `wrangler pages deploy build/web`。
- `Release`：推送 `v*` tag 后并行构建 Android、Windows、macOS、Web 包，生成带 sha256/size 的 `update.json`，并创建 GitHub Release。
- `Deploy worker`：手动触发，执行 `wrangler deploy` 发布 Worker API。

必需 Secrets：

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

可选变量：

- `CLOUDFLARE_PAGES_PROJECT_NAME`：Cloudflare Pages 项目名，默认 `mianshi-zhilian-app`。

正式签名发布时再补 Android、macOS、Windows 证书 Secrets。

## 还需要人工配置

1. 在 Cloudflare Pages 创建项目，项目名建议 `mianshi-zhilian-app`。
2. 在 GitHub 仓库配置 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID`。
3. 在 Cloudflare Workers 配置 `workers/api/wrangler.toml` 对应的账号、域名、D1/KV/R2 绑定。
4. 正式分发前补 Android keystore、Windows 代码签名、macOS Developer ID 签名和 notarization。
5. 如需稳定更新地址，把 release 生成的 `update.json` 同步到 Cloudflare Pages/R2 的 `latest.json`。

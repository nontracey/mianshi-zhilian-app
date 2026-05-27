# 部署说明

MVP 使用 GitHub Actions 构建 Flutter Web 和 Android APK，并把构建产物上传到 GitHub Releases。Cloudflare Pages、Workers 和签名密钥通过仓库 Secrets 配置。

必需 Secrets：

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

正式签名发布时再补 Android、macOS、Windows 证书 Secrets。

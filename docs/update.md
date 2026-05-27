# 软件更新

App 检查 `update.json` 或稳定地址 `latest.json`，对比 `version` 与 `buildNumber` 后引导用户下载对应平台安装包。MVP 不做静默更新，Android、Windows、macOS 均由用户确认安装。

`Release` workflow 会在 tag 发布时生成：

- `mianshi-zhilian-vX.Y.Z-android.apk`
- `mianshi-zhilian-vX.Y.Z-windows-setup.exe`
- `mianshi-zhilian-vX.Y.Z-windows.zip`
- `mianshi-zhilian-vX.Y.Z-macos.dmg`
- `mianshi-zhilian-vX.Y.Z-macos.zip`
- `mianshi-zhilian-vX.Y.Z-web.zip`
- `update.json`

`update.json` 会包含每个平台安装包的 GitHub Release URL、sha256 和 size。长期建议再把它同步到 Cloudflare 的稳定路径，例如 `https://app.mianshi-zhilian.com/update/latest.json`。

平台安装包不等待全部构建完成才发布：Android、Windows、macOS、Web 任一平台构建完成后，会先上传到同一个 GitHub Release；`update.json` 在所有平台完成后补充上传。

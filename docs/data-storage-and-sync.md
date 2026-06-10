# 数据存储与同步边界

当前应用采用本地优先模式。用户学习、练习和配置数据先写入本机存储，之后按同步设置导出、推送或拉取；AI、内容接口和账号类功能则按需即时请求远端服务。账号云同步暂不开放，当前跨设备同步依赖文件导入导出或用户自备同步目标。

同步实现分两层：

- 同步数据包：由 `StorageService.exportSyncPackage` / `importSyncPackage` 定义，所有渠道共享同一份业务快照和隐私策略。
  同步包顶层包含元数据字段 `contentEnv` 和 `contentVersion`，记录同步时刻使用的知识内容环境和版本号。
  导入时可据此判断远端内容版本与本机是否一致，避免内容不匹配导致的进度错乱。
- 同步渠道：由 `DataSyncService` 选择 WebDAV、GitHub、Gitee 等传输目标；新增渠道只负责连接测试、下载快照、上传快照，不直接决定业务数据结构。

同步包 JSON 结构示例：

```json
{
  "schemaVersion": 1,
  "app": "mianshi-zhilian",
  "updatedAt": "2026-06-02T00:00:00.000Z",
  "deviceId": "device_xxx",
  "contentEnv": "production",
  "contentVersion": "2026-06-02T00:00:00.000Z",
  "data": { ... }
}
```

## 本地优先并参与同步的数据

这些数据写入本地 `SharedPreferences`。当同步方式配置为文件导入导出、WebDAV、GitHub 或 Gitee 时，会被打包成同步快照；文件导入导出和远端渠道使用同一批业务数据。

- `progress_map`：知识点掌握度、练习次数、下次复习时间。
- `practice_attempts`：复述、代码、本地保存和 AI 评估后的练习记录。
- `sessions`：普通练习会话记录。
- `mock_interview_sessions`：模拟面试会话与题目结果。
- `prep_plan`、`prep_goal`、`training_plan`：备考计划、目标和训练计划。
- `local_profile`：本地个人资料。
- `settings`：主题、语言、练习偏好、语音模式等应用设置。
- `disabled_domains`：首页隐藏的领域。
- `custom_routes`：自定义路线与 AI 生成路线的定义（phases、topicIds 等），随设备同步传播。
- `learning_scope`：当前学习范围（全领域/单领域/路线），仅存储指向路线的指针（`routeId`）和范围类型，替换旧的 `selected_route_id`/`route_mode_disabled` 两个独立键（已从同步列表移除，迁移时本地读取一次即可）。
- `project_library`、`project_dig_projects`：项目库与项目深挖资料。
- `ai_configs`：AI 配置元数据。
- `answer_versions_*`：回答草稿、AI 修改版、面试版等版本记录。
- `deletions`：删除墓碑表 `{"<集合>:<id>": "<deletedAt ISO>"}`，用于让删除操作跨设备传播（见下文合并语义）。

## 合并语义（本地优先 + 删除可传播）

合并只发生在**合并层**（`DataSyncService._mergePackages` 等），与具体渠道解耦；新增同步方式无需改动合并算法。核心规则是 **last-write-wins + 删除墓碑**，远端永远不会让本地已删除项「复活」：

- 列表类集合（`custom_routes` / `practice_attempts` / `sessions` / `mock_interview_sessions` / `project_library` / `project_dig_projects`）按实体 `id` 合并，同 id 取 `updatedAt` 较新者；相同则本地优先。
- `progress_map` 按 `lastPracticeAt` 做 LWW（取最近一次练习的版本），`practiceCount` 取两侧较大值（单调不回退）。
- 删除任一实体时写入 `deletions` 墓碑；合并时若某 id 的 `deletedAt >= updatedAt` 则判定已删除并剔除；删除后又有意重建（`updatedAt > deletedAt`）能正常恢复。墓碑超过 60 天后 GC。
- 设备本地偏好（`learning_scope` / `settings` / `disabled_domains` 等）按 local-wins，不被远端覆盖。

WebDAV 上传使用条件请求做并发冲突检测：已知 ETag 时带 `If-Match`、远端确认不存在时带 `If-None-Match: *`；服务器返回 412 即判定他端已写入，重新下载合并后重试（GitHub/Gitee 用 sha/409 等价机制）。

同步时会按隐私设置脱敏：

- 默认不上传完整练习回答文本，`practice_attempts.answer` 会清空，`improvedAnswer` 会置空，`answer_versions_*` 不会进入同步快照。
- 默认隐私模式下，同步回写本机时会保留本机已有的完整练习回答，避免传输用脱敏快照反向覆盖本地内容。
- 默认同步备考目标和项目库；关闭后不会同步可能包含公司、JD、岗位、项目细节的数据。
- 默认同步 AI 配置元数据，但不会同步 API Key。导入远端 AI 配置时，会尽量保留本地已有 key。

## 本地保存但不属于业务同步快照的数据

- `sync_settings`：同步方式、WebDAV/GitHub/Gitee 配置、本地同步状态。该配置只保存在当前设备。
- `_syncDirty`、`_syncDirtyAt`、`_syncDeviceId`：同步脏标记和设备标识。
- `_analyticsBuffer`：待发送的轻量埋点缓冲。
- 内容缓存：`topics_cache`、`domain_cache_*`、`content_version`、`domain_version_*` 等，用于减少内容库重复加载。
- 登录 token、刷新 token、当前用户信息：用于账号登录状态，不通过普通数据同步快照同步。
- 「记住密码」凭据：登录态本身由刷新令牌维持；勾选记住密码时，原生平台（Android/iOS/macOS/Windows）将密码存入操作系统安全存储（Keychain/Keystore/DPAPI），Web 端仅记住用户名、不存密码。该凭据只存本设备、绝不进入任何同步快照。
- 已下载安装包记录：`downloaded_installer` 记录已校验安装包的本地路径与版本，供更新页常驻「已下载，点此安装」入口；属设备本地状态，不同步。

## 即时请求的数据与功能

这些功能不会先进入同步快照再处理，而是在用户操作时即时请求远端：

- AI 文本评估：调用用户配置的 OpenAI-compatible `/chat/completions`。
- AI 语音转写：按配置调用 `/audio/transcriptions` 或 `/chat/completions` 音频输入。
- 内容库加载与内容版本检查：请求内容 API，结果会缓存到本地。
- 登录、刷新登录、设备绑定。
- 工单提交：优先提交到远端；失败时会保存本地 ticket，稍后可再同步。
- 版本检查、更新包下载、镜像线路切换。
- 轻量使用统计：本地缓冲后发送，不包含完整练习回答。

## 清空数据

- 清空练习数据：只重置 `progress_map`、`sessions`、`practice_attempts`、`mock_interview_sessions`，用于用户试用后重新开始学习；保留 AI 配置、同步配置、内容缓存和个人资料。
- 清除所有本地数据：清空本机全部存储，包括配置、缓存、资料和登录状态。该入口属于隐私/数据管理操作。

# 历史改造分工记录

> 此文件是前一轮执行记录，不代表代理当前仍在运行或完整 V1 已完成。当前状态以 [落地审计](coach-implementation-audit.md) 为准。

用户授权：完整 V1 落地，使用较低模型分层实现，困难逐级升级，根代理最终验收。已停止使用并移除 cli-agent-orchestrator；直接使用原生 collaboration 子代理。

| 代理 | 模型 | 本轮边界 | 状态 |
| --- | --- | --- | --- |
| runtime_lead | gpt-5.6-sol | 教练/学习/回测/模拟/工作流及页面闭环 | 历史分工，交付未验收 |
| persistence_core | gpt-5.6-terra | 原生/Web数据库、生命周期、备份同步、迁移 | 历史分工，交付未验收 |
| imports_ui | gpt-5.6-luna | JD、岗位搜索、PDF/DOCX、简历/项目资料闭环 | 历史分工，交付未验收 |
| 根代理 | 当前会话模型 | 共享装配、依赖、CI、最终审查与验收 | 历史记录 |

并发上限：3个实现代理。升级顺序：Luna → Terra → Sol → 根代理。子代理不得用未实现的接口、隐藏入口或假响应宣称实际完成；不得提交/发布。

代码验收清单：[coach-v1-acceptance.json](coach-v1-acceptance.json)。现成外部配置可以联调，没有则按用户授权本地模拟，并保留区分。

## 根代理已完成的共享基础

- 跨平台 HTTP 适配器（package:http AbortableRequest），等待 runtime CancelToken 信号接线。
- 收紧原生 AI 密钥写入：安全存储失败时报告错误，不回退 SharedPreferences 明文；31 项存储/隐私相关测试通过。
- 发布教练规则文件白名单检查脚本通过，实际隐私语义检查仍需最终核对。

# 测试策略与设计原则

本项目的测试目标：**防止核心功能、核心流程、核心业务偏离预期**。重点放在最容易出回归、又最稳定可测的**业务/数据层**，UI 层只对关键控件做少量冒烟兜底。

## 分层与取舍

| 层次 | 覆盖什么 | 取舍 |
|---|---|---|
| 单元测试 | 纯函数/单一类的逻辑：合并算法（LWW + 墓碑）、路线组装（`RouteComposer`）、领域匹配、推荐排序、今日计划等 | 最稳定，优先且密集覆盖 |
| **业务层端到端**（`test/integration/`） | 用**真实** `ContentApiService → ContentProvider` 管线加载贴真内容，跑通：内容加载 → 路线生成 → 范围解析 → 目录 → 掌握度/今日计划 → 练习抽题 | **主力**。这层是历史 bug 高发区（路线一致性、范围解析、统计口径），且不依赖像素布局，稳定 |
| UI 冒烟（`test/widget/`） | 关键小控件的 scope→展示接线（如 `ScopeSelectorChip`） | **少量兜底**。整页（Catalog/Dashboard）的像素级 widget 测试在测试视口下布局约束脆（unbounded `RenderFlex`），性价比低，不追求；其数据正确性由业务层端到端覆盖 |

设计原则：**优先在业务层用真实数据端到端验证；纯 UI 只做关键控件冒烟。** 一个稳定的业务层测试，胜过十个脆弱的整页 widget 测试。

## 内容是单一事实源：贴真 fixture + 假传输层

核心约束（与 [design.md](design.md) 一致）：内容（领域 / 分类 / 知识点 / learningPath / 编号）由内容库定义，App 不另立一套。测试必须用**和内容契约同构**的数据，否则测了个寂寞。

做法：

- `test/fixtures/content_full/`：从真实 content 仓库精简出的 **java / agent / python** 三领域快照——保留真实 `learningPaths`、分类、`order`、`interviewFrequency` 等结构，只裁掉 `learningCards` 等大体积正文。
  - `manifest.json` / `domains/*.json`：原样结构。
  - `topics.json`：`topicRef → 精简 topic` 的映射（共 115 个 topic）。
- `test/helpers/fake_content_client.dart`（`FakeContentClient`）：实现 `http.Client`，按请求路径从上面的 fixture 返回 JSON。这样跑的是**真实的** `ContentApiService` 与 `ContentProvider`（解析、缓存、双键、并发去重全部真实执行），而不是 mock 掉业务层。

> 为什么不直接 mock ContentProvider：mock 掉业务层就测不到真正的链路（加载/缓存/去重/范围解析）。用假传输层 + 真实 provider，才能复现并守住像 issue 4/5（跨域路线只显示一个领域）这类链路 bug。

### 重新生成 fixture

内容库结构变化时，从本地 content 仓库（默认 `../../mianshi-zhilian-content` 或实际路径）重新生成：对 java/agent/python 三领域，拷贝 `domains/<id>.json`，遍历其 learningPath/分类引用的每个 topic，抽取关键字段（`id/domain/category/title/summary/order/difficulty/interviewFrequency/tags/recommendWeight/status/prerequisites`）写入 `topics.json`，并据引用数写 `manifest.json` 的 `topicCount`。保持 fixture 与契约同构即可。

## 已覆盖的核心流程

- **内容加载**（`integration/core_flows_test.dart`）：三领域计数与契约一致、`topics.values` 无重复（R-1）、按内容 `order` 升序。
- **路线生成 + 组装一致性**：多领域目标覆盖全部相关领域、单领域只覆盖一个；**「声称领域」恒等于「有内容领域」**（`effectiveDomainIds` == phases 推导，回归 issue 4/5）。
- **范围解析**：路线跨域解析出全部 topic、单领域、全部领域。
- **练习抽题口径**（`integration/practice_review_mastery_test.dart`）：弱项强化（`getWeakTopics`）、高频过滤、模拟面试/复述抽题池 == `resolveScopedTopics`（统一口径 A-1/L-2）。
- **复习队列**：复习间隔随分数增大、今日到期项进入队列。
- **跨域掌握度**：按领域分组计数、分领域掌握度独立计算、薄弱 TOP5 跨域取低分。
- **路线编辑重排**（issue 3）：调整领域顺序 → 阶段顺序随之变化、topic 集合不变。
- **同步合并**：`merge_progress_map_test`（progress_map 按 `lastPracticeAt` LWW）、`learning_scope_provider_test`（删除墓碑、去重）等。

## 运行

```bash
cd apps/client
flutter test                              # 全部
flutter test test/integration/            # 业务层端到端
flutter test test/widget/                 # UI 冒烟
flutter test test/services/route_composer_test.dart   # 单个文件
```

新增/修改测试后，按 [CLAUDE.md](../CLAUDE.md) 跑 `flutter analyze --no-fatal-infos`、`python3 lib/l10n/check_l10n_keys.py`、`flutter test`，或一把梭 `./scripts/pre-commit-check.sh`。

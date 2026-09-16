/// 合成验收样本（§5.1、§14 个人信息隔离检查）。
///
/// 全部为从零编写的**虚构数据**，标注“演示数据”，与任何真实用户档案隔离。
/// 不得包含开发者姓名、联系方式、真实简历、城市/薪资目标、项目细节或成绩。
/// 用于确定性规则单测与回归，不抽取个人历史再匿名化。
library;

import 'package:mianshi_zhilian/coach/domain/common.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/knowledge.dart';
import 'package:mianshi_zhilian/coach/domain/resume.dart';
import 'package:mianshi_zhilian/coach/domain/evidence.dart';
import 'package:mianshi_zhilian/coach/domain/session.dart';

const String demoProfileId = 'profile-demo';
const String demoGoalId = 'goal-demo-java-backend';
const String demoResumeId = 'resume-demo-v1';
const String demoProjectId = 'project-demo-order-idempotency';
const String demoKnowledgeId = 'knowledge-demo-hashmap';
const String demoReviewPointId = 'rp-demo-hashmap-resize';

/// 虚构 JD：Java 后端开发工程师（演示数据）。
Goal buildDemoGoal({required DateTime now}) => Goal(
  id: demoGoalId,
  profileId: demoProfileId,
  title: 'Java 后端开发工程师（演示数据）',
  originalText:
      '负责服务端接口开发；精通 Java 与 Spring Boot；'
      '熟悉 MySQL 事务与索引；有高并发经验者优先；'
      '了解 Redis 缓存与接口幂等设计。',
  originalUrl: 'https://example.com/jobs/demo-123',
  platform: 'demo-board',
  externalJobId: 'demo-123',
  company: '示例科技有限公司',
  location: '杭州',
  salaryText: '20-30K',
  contentHash: 'demo-hash-001',
  active: true,
  createdAt: now,
  updatedAt: now,
);

List<GoalRequirement> buildDemoRequirements({required DateTime now}) => [
  GoalRequirement(
    id: 'req-demo-java',
    goalId: demoGoalId,
    profileId: demoProfileId,
    type: RequirementType.hardRequirement,
    title: '精通 Java 与 Spring Boot',
    jdSourceSpan: '精通 Java 与 Spring Boot',
    importance: Importance.high,
    createdAt: now,
  ),
  GoalRequirement(
    id: 'req-demo-mysql',
    goalId: demoGoalId,
    profileId: demoProfileId,
    type: RequirementType.hardRequirement,
    title: '熟悉 MySQL 事务与索引',
    jdSourceSpan: '熟悉 MySQL 事务与索引',
    importance: Importance.high,
    createdAt: now,
  ),
  GoalRequirement(
    id: 'req-demo-idempotent',
    goalId: demoGoalId,
    profileId: demoProfileId,
    type: RequirementType.niceToHave,
    title: '了解接口幂等设计',
    jdSourceSpan: '了解 Redis 缓存与接口幂等设计',
    importance: Importance.medium,
    inferred: false,
    createdAt: now,
  ),
];

/// 虚构简历：含一个项目主张（演示数据，非真实经历）。
Resume buildDemoResume({required DateTime now}) => Resume(
  id: demoResumeId,
  profileId: demoProfileId,
  versionLabel: 'v1（演示数据）',
  originalText:
      '项目：订单重复提交处理。负责订单重复提交处理，'
      '使用唯一请求号区分重复请求，保证接口幂等。',
  fileName: 'demo-resume.txt',
  parsedAt: now,
  createdAt: now,
);

List<ResumeClaim> buildDemoClaims() => [
  ResumeClaim(
    id: 'claim-demo-idempotent',
    profileId: demoProfileId,
    resumeId: demoResumeId,
    projectId: demoProjectId,
    statement: '负责订单重复提交处理，使用唯一请求号区分重复请求',
    originalSpan: '负责订单重复提交处理，使用唯一请求号区分重复请求',
    status: ClaimStatus.confirmed,
    confidence: 0.9,
  ),
];

Project buildDemoProject() => Project(
  id: demoProjectId,
  profileId: demoProfileId,
  resumeId: demoResumeId,
  name: '订单重复提交处理（演示数据）',
  goal: '保证下单接口幂等，防止重复扣款',
  responsibilities: '设计唯一请求号机制，前端携带 token，后端去重',
  techStack: 'Java / Spring Boot / Redis',
  metrics: '重复提交率下降 99%',
  timeRange: '2024-2025',
);

KnowledgeItem buildDemoKnowledge({required DateTime now}) => KnowledgeItem(
  id: demoKnowledgeId,
  profileId: demoProfileId,
  title: 'HashMap 扩容机制（演示数据）',
  aliases: ['哈希表扩容', 'hashmap resize'],
  contentStatus: 'verified',
  createdAt: now,
  updatedAt: now,
);

ReviewPoint buildDemoReviewPoint({required DateTime now}) => ReviewPoint(
  id: demoReviewPointId,
  profileId: demoProfileId,
  knowledgeItemId: demoKnowledgeId,
  label: '扩容阈值与迁移',
  aliases: const [],
  createdAt: now,
);

ReviewState buildDemoReviewState({ReviewStatus status = ReviewStatus.unseen}) =>
    ReviewState(
      reviewPointId: demoReviewPointId,
      profileId: demoProfileId,
      knowledgeItemId: demoKnowledgeId,
      status: status,
    );

/// 构造一次评估事件的便捷方法。
AssessmentEvent buildAssessmentEvent({
  required SessionId sessionId,
  required SessionMode mode,
  required ReviewOutcome result,
  String hintLevel = 'none',
  bool independentEligible = false,
  bool isSpacedEligible = false,
  EvidenceValidity validity = EvidenceValidity.accepted,
  required DateTime now,
}) => AssessmentEvent(
  id: 'assess-${now.microsecondsSinceEpoch}',
  profileId: demoProfileId,
  sessionId: sessionId,
  turnGroupId: 'tg-1',
  knowledgeItemId: demoKnowledgeId,
  reviewPointId: demoReviewPointId,
  questionMessageId: 'q-1',
  answerMessageIds: const ['a-1'],
  assessmentMode: mode,
  askedDimensions: const ['mechanism'],
  result: result,
  hintLevel: hintLevel,
  independentEligible: independentEligible,
  isSpacedEligible: isSpacedEligible,
  validity: validity,
  sourceRevisionIds: const ['src-1'],
  rubricVersion: 'rubric-v1',
  rulesVersion: 'coach-v1',
  createdAt: now,
);

CoachSession buildDemoSession({
  required SessionId id,
  required SessionMode mode,
  required DateTime now,
}) => CoachSession(
  id: id,
  profileId: demoProfileId,
  mode: mode,
  createdAt: now,
  goalId: demoGoalId,
  resumeId: demoResumeId,
  projectIds: const [demoProjectId],
  knowledgeItemId: demoKnowledgeId,
  reviewPointId: demoReviewPointId,
);

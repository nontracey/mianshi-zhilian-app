/// Captures the values used in a session, not just IDs that could later change.
library;

import '../domain/goal.dart';
import '../domain/knowledge.dart';
import '../domain/resume.dart';
import '../domain/evidence.dart';
import '../domain/session.dart';
import '../persistence/coach_store.dart';

class SessionScopeService {
  const SessionScopeService(this.store);
  final CoachStore store;

  Future<SessionCoverageSnapshot> capture({
    required String profileId,
    String? goalId,
    String? resumeId,
    List<String> projectIds = const [],
    String? knowledgeItemId,
    List<String> reviewPointIds = const [],
    int? maxQuestions,
    String? planItemId,
    String? parentSessionId,
  }) async {
    final goal = goalId == null ? null : await store.getGoal(goalId);
    final resume = resumeId == null ? null : await store.getResume(resumeId);
    if ((goalId != null && goal?.profileId != profileId) ||
        (resumeId != null && resume?.profileId != profileId)) {
      throw StateError('Session source removed or belongs to another profile');
    }
    final requirements = goal == null
        ? <GoalRequirement>[]
        : await store.listGoalRequirements(goal.id);
    final links = goal == null
        ? <GoalKnowledgeLink>[]
        : await store.listGoalKnowledgeLinks(goal.id);
    final scope = <String>{
      if (knowledgeItemId != null) knowledgeItemId,
      if (knowledgeItemId == null) ...links.map((l) => l.knowledgeItemId),
    };
    // Explicit review groups may span multiple knowledge items.
    final allKnowledge = await store.listKnowledgeItems(profileId);
    final allPoints = <ReviewPoint>[];
    for (final k in allKnowledge) {
      allPoints.addAll(await store.listReviewPoints(k.id));
    }
    for (final id in reviewPointIds) {
      final matching = allPoints.where(
        (p) => p.id == id && p.profileId == profileId,
      );
      if (matching.isEmpty) throw StateError('Unknown review point');
      scope.add(matching.first.knowledgeItemId);
    }
    final knowledge = (await store.listKnowledgeItems(
      profileId,
    )).where((k) => scope.contains(k.id)).toList();
    if (knowledge.length != scope.length)
      throw StateError('Knowledge source removed');
    final points = <ReviewPoint>[];
    for (final item in knowledge) {
      points.addAll(
        (await store.listReviewPoints(item.id)).where(
          (p) =>
              p.profileId == profileId &&
              (reviewPointIds.isEmpty || reviewPointIds.contains(p.id)),
        ),
      );
    }
    final projects = resume == null
        ? <Project>[]
        : (await store.listProjects(resume.id))
              .where(
                (p) =>
                    p.profileId == profileId &&
                    (projectIds.isEmpty || projectIds.contains(p.id)),
              )
              .toList();
    if (!projects.map((p) => p.id).toSet().containsAll(projectIds)) {
      throw StateError('Project source removed');
    }
    final claims = resume == null
        ? <ResumeClaim>[]
        : (await store.listResumeClaims(resume.id))
              .where(
                (c) =>
                    c.profileId == profileId &&
                    (projectIds.isEmpty || projectIds.contains(c.projectId)),
              )
              .toList();
    return SessionCoverageSnapshot(
      requirementIds: requirements.map<String>((r) => r.id).toList(),
      knowledgeItemIds: knowledge.map((k) => k.id).toList(),
      reviewPointIds: points.map((p) => p.id).toList(),
      projectIds: projects.map<String>((p) => p.id).toList(),
      claimIds: claims.map<String>((c) => c.id).toList(),
      requirements: requirements
          .map<Map<String, dynamic>>(
            (r) => Map<String, dynamic>.from(r.toJson()),
          )
          .toList(),
      projects: projects
          .map<Map<String, dynamic>>(
            (p) => Map<String, dynamic>.from(p.toJson()),
          )
          .toList(),
      claims: claims
          .map<Map<String, dynamic>>(
            (c) => Map<String, dynamic>.from(c.toJson()),
          )
          .toList(),
      reviewPoints: points
          .map((p) => Map<String, dynamic>.from(p.toJson()))
          .toList(),
      knowledgeItems: knowledge
          .map((k) => Map<String, dynamic>.from(k.toJson()))
          .toList(),
      knowledgeLinks: links
          .map<Map<String, dynamic>>(
            (l) => Map<String, dynamic>.from(l.toJson()),
          )
          .toList(),
      maxQuestions: maxQuestions,
      planItemId: planItemId,
      parentSessionId: parentSessionId,
    );
  }
}

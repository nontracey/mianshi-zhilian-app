/// Deterministic import of user-authored legacy materials. Old scores stay
/// in the archive and never become independent assessment evidence.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/common.dart';
import '../domain/goal.dart';
import '../domain/profile.dart';
import '../domain/resume.dart';
import '../domain/session.dart';
import 'coach_store.dart';
import 'extension_records.dart';

class LegacyMaterialMigrator {
  const LegacyMaterialMigrator({required this.store, required this.profileId});
  final CoachStore store;
  final String profileId;
  String _id(String kind, String oldId) =>
      'legacy.${sha256.convert(utf8.encode(jsonEncode([profileId, kind, oldId])))}';

  Future<void> migrate(
    Map<String, Object?> snapshot,
  ) => store.transaction(() async {
    if ((await store.listTombstones(
      profileId,
    )).any((m) => m.entityType == 'profile_reset')) {
      return;
    }
    final now = DateTime.now();
    if (await store.getProfile(profileId) == null) {
      await store.putProfile(
        Profile(id: profileId, createdAt: now, updatedAt: now),
      );
    }
    final encoded = jsonEncode(snapshot);
    final hash = sha256.convert(utf8.encode(encoded)).toString();
    final previous = await store.getExtension(
      profileId,
      CoachExtensionKind.legacyMigration,
      'legacy.materials.v1',
    );
    if (previous?.value['snapshotHash'] == hash) return;
    // Retain the first complete snapshot, even after later incremental imports.
    if (await store.getExtension(
          profileId,
          CoachExtensionKind.legacyMigration,
          'legacy.upgrade.snapshot.v1',
        ) ==
        null) {
      await store.putExtension(
        CoachExtensionRecord(
          profileId: profileId,
          kind: CoachExtensionKind.legacyMigration,
          id: 'legacy.upgrade.snapshot.v1',
          revision: 1,
          value: {
            'schemaVersion': 1,
            'snapshotJson': encoded,
            'snapshotHash': hash,
            'counts': snapshot.map(
              (k, v) => MapEntry(
                k,
                v is List || v is Map ? (v as dynamic).length as int : 1,
              ),
            ),
          },
          updatedAt: now,
        ),
      );
    }
    final plan = snapshot['prep_plan'];
    if (plan is Map) {
      final text = (plan['jobDescription'] ?? '').toString();
      final role = (plan['targetRole'] ?? '').toString();
      final id = _id('goal', 'prep_plan');
      if ((text.trim().isNotEmpty || role.trim().isNotEmpty) &&
          await store.getGoal(id) == null &&
          !(await store.listTombstones(
            profileId,
          )).any((m) => m.entityType == 'goal' && m.entityId == id)) {
        await store.putGoal(
          Goal(
            id: id,
            profileId: profileId,
            title: role.isEmpty ? 'Legacy target' : role,
            originalText: text,
            company: plan['company'] as String?,
            platform: 'legacy',
            extractionStatus: 'pending',
            contentHash: sha256.convert(utf8.encode(text)).toString(),
            active: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }
    for (final table in ['project_library', 'project_dig_projects']) {
      for (final raw in snapshot[table] as List? ?? const []) {
        if (raw is! Map) continue;
        final oldId =
            (raw['id'] ?? sha256.convert(utf8.encode(jsonEncode(raw))))
                .toString();
        // A project library is not a full resume: keep an explicitly labelled
        // source record for each project and preserve only supplied fields.
        final resumeId = _id('resume.$table', oldId);
        if (await store.getResume(resumeId) != null) continue;
        final original = jsonEncode(raw);
        await store.putResume(
          Resume(
            id: resumeId,
            profileId: profileId,
            versionLabel: 'Legacy project',
            originalText: original,
            createdAt: now,
          ),
        );
        final tech = raw['techStack'];
        await store.putProject(
          Project(
            id: _id('project.$table', oldId),
            profileId: profileId,
            resumeId: resumeId,
            name: (raw['name'] ?? '').toString(),
            originalSpan: original,
            goal: raw['background']?.toString(),
            responsibilities: [
              raw['role'],
              raw['task'],
              raw['action'],
            ].whereType<String>().join('\n'),
            metrics: raw['result']?.toString(),
            techStack: tech is List ? tech.join(', ') : tech?.toString(),
          ),
        );
      }
    }
    for (final raw
        in snapshot['mock_interview_sessions'] as List? ?? const []) {
      if (raw is! Map || raw['id'] == null) continue;
      final oldId = raw['id'].toString();
      final id = _id('mock', oldId);
      if (await store.getSession(id) != null) continue;
      final started =
          DateTime.tryParse(raw['startedAt']?.toString() ?? '') ?? now;
      var sequence = 0;
      final messages = <CoachMessage>[];
      for (final attempt in raw['attempts'] as List? ?? const []) {
        if (attempt is! Map) continue;
        for (final entry in {
          'assistant': 'question',
          'user': 'answer',
        }.entries) {
          final text = attempt[entry.value]?.toString() ?? '';
          if (text.trim().isEmpty) continue;
          sequence++;
          messages.add(
            CoachMessage(
              id: _id('mock.message.$oldId', '$sequence'),
              profileId: profileId,
              sessionId: id,
              role: entry.key,
              content: text,
              turnId: _id(
                'mock.turn.$oldId',
                (attempt['id'] ?? sequence).toString(),
              ),
              sequence: sequence,
              createdAt: started,
            ),
          );
        }
      }
      await store.putSession(
        CoachSession(
          id: id,
          profileId: profileId,
          mode: SessionMode.interview,
          status: RuntimeStatus.completed,
          createdAt: started,
          startedAt: started,
          endedAt:
              DateTime.tryParse(raw['completedAt']?.toString() ?? '') ??
              started,
          partial: raw['completedAt'] == null,
          stopReason: 'legacy_import',
          turnSequence: sequence,
        ),
      );
      for (final message in messages) {
        await store.putMessage(message);
      }
    }
    await store.putExtension(
      CoachExtensionRecord(
        profileId: profileId,
        kind: CoachExtensionKind.legacyMigration,
        id: 'legacy.materials.v1',
        revision: (previous?.revision ?? 0) + 1,
        value: {
          'schemaVersion': 1,
          'snapshotJson': encoded,
          'snapshotHash': hash,
        },
        updatedAt: now,
      ),
    );
  });
}

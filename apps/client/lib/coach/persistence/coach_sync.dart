/// Entity/event union for coach V2. Original messages are immutable; derived
/// review state is replayed, never added together from two devices.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../policies/evidence_replay.dart';
import 'coach_backup.dart';
import 'coach_store.dart';

Map<String, Object?> coachBackupFromData(Map<String, Object?> data) {
  Object? canonical(Object? value) {
    if (value is Map) {
      return {
        for (final key in value.keys.map((k) => k.toString()).toList()..sort())
          key: canonical(value[key]),
      };
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return {
    'app': 'mianshi-zhilian',
    'kind': 'coach-backup',
    'schemaVersion': 2,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'counts': data.map((k, v) => MapEntry(k, (v as List).length)),
    'contentHash': sha256
        .convert(utf8.encode(jsonEncode(canonical(data))))
        .toString(),
    'data': data,
  };
}

String _id(String table, Map row) => switch (table) {
  'goalKnowledgeLinks' => '${row['goalId']}:${row['knowledgeItemId']}',
  'goalResumeLinks' => '${row['goalId']}:${row['resumeId']}',
  'claimRequirementLinks' => '${row['claimId']}:${row['requirementId']}',
  'reviewStates' => '${row['reviewPointId']}',
  'tombstones' => '${row['profileId']}:${row['entityType']}:${row['entityId']}',
  'extensions' => '${row['profileId']}:${row['kind']}:${row['id']}',
  'assessmentEvents' =>
    '${row['profileId']}:${row['sessionId']}:${row['turnGroupId']}:${row['assessmentRevision']}',
  _ => '${row['id']}',
};

Future<Map<String, Object?>> mergeCoachBackups(
  Map<String, Object?> local,
  Map<String, Object?>? remote,
) async {
  // Validate both envelopes before accepting network data or constructing a new hash.
  await restoreCoachBackup(InMemoryCoachStore(), local);
  if (remote == null) return local;
  await restoreCoachBackup(InMemoryCoachStore(), remote);
  final left = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(local['data'])) as Map,
  );
  final right = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(remote['data'])) as Map,
  );
  _restoreRedactionMarkers(left);
  _restoreRedactionMarkers(right);
  int generation(Map data, String profile) => (data['tombstones'] as List)
      .where(
        (t) => t['profileId'] == profile && t['entityType'] == 'profile_reset',
      )
      .fold<int>(
        0,
        (v, t) => (t['generation'] as int) > v ? t['generation'] as int : v,
      );
  final out = <String, Object?>{};
  final conflicts = <Map<String, Object?>>[];
  final sourceOwners = <String, Map>{};
  final sourceRemaps = <Map, Map<String, String>>{left: {}, right: {}};
  for (final table in left.keys) {
    final rows = <String, Map<String, Object?>>{};
    for (final side in [left, right]) {
      for (final raw in side[table] as List? ?? []) {
        final row = Map<String, Object?>.from(raw as Map);
        String? profile = table == 'profiles'
            ? row['id'] as String?
            : row['profileId'] as String?;
        if (table == 'sourceChunks') {
          final parent = (side['sources'] as List).where(
            (s) => s['id'] == row['sourceId'],
          );
          profile = parent.isEmpty
              ? null
              : parent.first['profileId'] as String?;
          final remapped =
              sourceRemaps[side]!['${row['sourceId']}:${row['sourceRevision']}'];
          if (remapped != null) row['sourceId'] = remapped;
        }
        if (profile != null &&
            table != 'tombstones' &&
            generation(side, profile) <
                (generation(left, profile) > generation(right, profile)
                    ? generation(left, profile)
                    : generation(right, profile))) {
          continue;
        }
        final key = _id(table, row);
        final previous = rows[key];
        if (previous == null) {
          rows[key] = row;
          if (table == 'sources') sourceOwners[key] = side;
          continue;
        }
        if (previous['profileId'] != row['profileId']) {
          throw const FormatException(
            'Sync identity collision across profiles',
          );
        }
        _fillRedactedFields(previous, row);
        _fillRedactedFields(row, previous);
        if (table == 'sources' &&
            previous['revision'] == row['revision'] &&
            (previous['contentHash'] != row['contentHash'] ||
                (previous['content'] is String &&
                    row['content'] is String &&
                    previous['content'] != row['content']))) {
          final existingVariant = rows.values
              .where(
                (candidate) =>
                    candidate['id'].toString().startsWith(
                      '${row['id']}.conflict.',
                    ) &&
                    candidate['revision'] == row['revision'] &&
                    candidate['contentHash'] == row['contentHash'],
              )
              .firstOrNull;
          if (existingVariant != null) {
            sourceRemaps[side]!['${row['id']}:${row['revision']}'] =
                existingVariant['id'] as String;
            continue;
          }
          final variants = [previous, row]
            ..sort((a, b) => _stable(a).compareTo(_stable(b)));
          final variant = variants.last;
          final suffix = sha256
              .convert(utf8.encode(_stable(variant)))
              .toString()
              .substring(0, 12);
          final variantId = '${row['id']}.conflict.$suffix';
          final variantSide = identical(variant, previous)
              ? sourceOwners[key]!
              : side;
          sourceRemaps[variantSide]!['${row['id']}:${row['revision']}'] =
              variantId;
          rows[key] = {...variants.first, 'status': 'pending'};
          rows[_id(table, {...variant, 'id': variantId})] = {
            ...variant,
            'id': variantId,
            'status': 'pending',
          };
          conflicts.add({
            'profileId': profile,
            'kind': 'syncMetadata',
            'id': 'conflict.source.$suffix',
            'revision': 1,
            'updatedAt':
                variant['fetchedAt'] ??
                variant['createdAt'] ??
                '1970-01-01T00:00:00.000Z',
            'value': {
              'table': 'sources',
              'entityId': row['id'],
              'variantId': variantId,
            },
          });
          continue;
        }
        if (table == 'sources' &&
            previous['revision'] == row['revision'] &&
            previous['contentHash'] == row['contentHash'] &&
            (previous['status'] == 'pending' || row['status'] == 'pending')) {
          rows[key] = previous['status'] == 'pending' ? previous : row;
          continue;
        }
        if (table == 'assessmentEvents' && _stable(previous) != _stable(row)) {
          if (previous['rationale'] == 'sync_conflict_pending') {
            if ((row['assessmentRevision'] as int? ?? 0) >
                (previous['assessmentRevision'] as int? ?? 0)) {
              rows[key] = row;
            }
            continue;
          }
          if (row['rationale'] == 'sync_conflict_pending') {
            if ((row['assessmentRevision'] as int? ?? 0) >=
                (previous['assessmentRevision'] as int? ?? 0)) {
              rows[key] = row;
            }
            continue;
          }
          final variants = [previous, row]
            ..sort((a, b) => _stable(a).compareTo(_stable(b)));
          final suffix = sha256
              .convert(
                utf8.encode(
                  '${_stable(variants.first)}:${_stable(variants.last)}',
                ),
              )
              .toString()
              .substring(0, 12);
          rows[key] = {
            ...variants.first,
            'validity': 'pending',
            'independentEligible': false,
            'isSpacedEligible': false,
            'rationale': 'sync_conflict_pending',
          };
          conflicts.add({
            'profileId': profile,
            'kind': 'syncMetadata',
            'id': 'conflict.assessment.$suffix',
            'revision': 1,
            'updatedAt': variants.first['createdAt'],
            'value': {
              'table': table,
              'entityId': variants.first['id'],
              'variantId': variants.last['id'],
              'primary': variants.first,
              'variant': variants.last,
            },
          });
          continue;
        }
        if (table == 'messages') {
          if (previous['content'] != row['content'] &&
              previous['content'] != '' &&
              row['content'] != '') {
            throw const FormatException(
              'Conflicting original messages; neither copy was overwritten',
            );
          }
          if (previous['content'] == '' && row['content'] != '') {
            rows[key] = row;
          }
          continue;
        }
        int version(Map r) =>
            (r['turnSequence'] ??
                    r['version'] ??
                    r['revision'] ??
                    r['generation'] ??
                    0)
                as int;
        final v = version(row).compareTo(version(previous));
        final timestamp = (row['updatedAt'] ?? row['createdAt'] ?? '')
            .toString()
            .compareTo(
              (previous['updatedAt'] ?? previous['createdAt'] ?? '').toString(),
            );
        if ((table == 'dailyPlans' ||
                (table == 'extensions' && row['kind'] == 'workflowTemplate')) &&
            v == 0 &&
            _stable(previous) != _stable(row)) {
          final variants = [previous, row]
            ..sort((a, b) => _stable(a).compareTo(_stable(b)));
          rows[key] = variants.first;
          final variant = variants.last;
          final suffix = sha256
              .convert(utf8.encode(_stable(variant)))
              .toString()
              .substring(0, 12);
          final copy = <String, Object?>{
            ...variant,
            'id': '${variant['id']}.conflict.$suffix',
          };
          if (table == 'dailyPlans') {
            copy['revisionNote'] = 'sync_conflict:${row['id']}';
          }
          if (table == 'extensions' && variant['value'] is Map) {
            copy['value'] = {...variant['value'] as Map, 'id': copy['id']};
          }
          rows[_id(table, copy)] = copy;
          conflicts.add({
            'profileId': profile,
            'kind': 'syncMetadata',
            'id': 'conflict.$suffix',
            'revision': 1,
            'updatedAt':
                (row['updatedAt'] ??
                row['frozenAt'] ??
                row['createdAt'] ??
                previous['updatedAt'] ??
                previous['frozenAt'] ??
                '1970-01-01T00:00:00.000Z'),
            'value': {
              'table': table,
              'entityId': row['id'],
              'variantId': copy['id'],
            },
          });
          continue;
        }
        if (v > 0 ||
            (v == 0 &&
                (timestamp > 0 ||
                    (timestamp == 0 &&
                        _stable(row).compareTo(_stable(previous)) > 0)))) {
          rows[key] = row;
        }
      }
    }
    out[table] = rows.values.toList();
  }
  final extensions = {
    for (final row in out['extensions'] as List) _id('extensions', row): row,
  };
  for (final conflict in conflicts) {
    extensions[_id('extensions', conflict)] = conflict;
  }
  out['extensions'] = extensions.values.toList();
  final markers = out['tombstones'] as List;
  bool deleted(String profile, String kind, Object? id) => markers.any(
    (t) =>
        t['profileId'] == profile &&
        t['entityType'] == kind &&
        t['entityId'] == id,
  );
  for (final table in [
    'goals',
    'goalRequirements',
    'goalKnowledgeLinks',
    'goalResumeLinks',
    'knowledgeItems',
    'sourceChunks',
  ]) {
    (out[table] as List).removeWhere((r) {
      final profile = r['profileId'] as String?;
      if (table == 'sourceChunks') {
        final owner = _profileOf(out, table, r);
        return owner != null &&
            deleted(owner, 'knowledge', r['knowledgeItemId']);
      }
      if (profile == null) return false;
      if (table == 'goals') return deleted(profile, 'goal', r['id']);
      if (table == 'knowledgeItems') {
        return deleted(profile, 'knowledge', r['id']) &&
            r['contentStatus'] != 'removed';
      }
      return deleted(profile, 'goal', r['goalId']);
    });
  }
  _writeRedactionLedger(out);
  for (final table in out.entries) {
    (table.value as List).sort(
      (a, b) => _id(table.key, a).compareTo(_id(table.key, b)),
    );
  }
  replayCoachReviewStates(out);
  final merged = coachBackupFromData(out);
  await restoreCoachBackup(InMemoryCoachStore(), merged);
  return merged;
}

/// Privacy is applied after every merge, including conflict retries. Keep IDs
/// and timestamps, not private text, when the corresponding switch is disabled.
Map<String, Object?> redactCoachBackup(
  Map<String, Object?> backup, {
  required bool fullText,
  required bool privateMaterials,
  bool configMetadata = false,
}) {
  final data = Map<String, Object?>.from(
    jsonDecode(jsonEncode(backup['data'])) as Map,
  );
  _restoreRedactionMarkers(data);
  final before = jsonDecode(jsonEncode(data)) as Map;
  if (!fullText || !privateMaterials) {
    for (final m in data['messages'] as List) {
      m['content'] = '';
      m['_coachRedacted'] = true;
    }
    for (final c in data['checkpoints'] as List) {
      c['taughtScope'] = '';
      c['openQuestions'] = [];
      c['nextPosition'] = null;
    }
  }
  if (!privateMaterials) {
    for (final rows in data.values) {
      for (final row in rows as List) {
        row['_coachRedacted'] = true;
      }
    }
    for (final r in data['goalRequirements'] as List) {
      r['title'] = '';
      r['summary'] = null;
      r['jdSourceSpan'] = null;
      r['inferenceRationale'] = null;
      r['suggestedDepth'] = null;
    }
    for (final c in data['claimRequirementLinks'] as List) {
      c['rationale'] = null;
    }
    for (final g in data['goals'] as List) {
      g['originalText'] = '';
      g['title'] = '';
      g['description'] = null;
      g['company'] = null;
      g['location'] = null;
      g['salaryText'] = null;
      g['originalUrl'] = null;
      g['canonicalUrl'] = null;
    }
    for (final r in data['resumes'] as List) {
      r['originalText'] = '';
      r['fileName'] = null;
    }
    for (final p in data['projects'] as List) {
      for (final key in [
        'name',
        'originalSpan',
        'goal',
        'responsibilities',
        'techStack',
        'metrics',
        'timeRange',
      ]) {
        if (p.containsKey(key)) p[key] = key == 'name' ? '' : null;
      }
    }
    for (final c in data['resumeClaims'] as List) {
      c['statement'] = '';
      c['originalSpan'] = null;
    }
    for (final s in data['sessions'] as List) {
      s['coverageSnapshot'] = null;
    }
    for (final s in data['sources'] as List) {
      s['content'] = null;
      s['url'] = null;
      s['title'] = '';
    }
    for (final c in data['sourceChunks'] as List) {
      c['content'] = '';
      c['titlePath'] = null;
      c['sourceLocation'] = null;
    }
    for (final p in data['profiles'] as List) {
      p['displayName'] = null;
      p['teachingPreference'] = null;
      p['baseLevel'] = null;
    }
    for (final k in data['knowledgeItems'] as List) {
      k['title'] = '';
      k['aliases'] = [];
    }
    for (final r in data['reviewPoints'] as List) {
      r['label'] = '';
      r['aliases'] = [];
    }
    for (final r in data['resumes'] as List) {
      r['versionLabel'] = '';
    }
    for (final e in data['assessmentEvents'] as List) {
      e['rationale'] = null;
    }
    for (final p in data['dailyPlans'] as List) {
      p['revisionNote'] = null;
      for (final item in p['planItems'] as List? ?? []) {
        item['title'] = '';
      }
    }
    for (final j in data['ingestionJobs'] as List) {
      j['error'] = null;
    }
    for (final j in data['cleanupTasks'] as List) {
      j['error'] = null;
    }
    data['goalRevisions'] = [];
    data['extensions'] = (data['extensions'] as List)
        .where((e) => e['kind'] == 'syncMetadata')
        .toList();
  } else {
    data['extensions'] = (data['extensions'] as List)
        .where(
          (e) => !['legacyMigration', 'deletionOperation'].contains(e['kind']),
        )
        .toList();
  }
  if (!configMetadata) {
    data['extensions'] = (data['extensions'] as List)
        .where(
          (e) => ![
            'mcpConfigMetadata',
            'embeddingConfigMetadata',
            'providerConfigMetadata',
          ].contains(e['kind']),
        )
        .toList();
  }
  if (!privateMaterials || !fullText) {
    for (final extension in data['extensions'] as List) {
      if (extension['kind'] != 'syncMetadata') continue;
      final value = extension['value'];
      if (value is! Map || value['table'] != 'assessmentEvents') continue;
      for (final side in ['primary', 'variant']) {
        final event = value[side];
        if (event is Map) event['rationale'] = null;
      }
    }
  }
  for (final table in data.keys) {
    final originals = {
      for (final row in before[table] as List) _id(table, row): row,
    };
    for (final row in data[table] as List) {
      final prior = originals[_id(table, row)];
      if (prior == null) continue;
      final fields = <String>{
        ...(row['_coachRedactedFields'] as List? ?? []).cast<String>(),
      };
      for (final key in row.keys.cast<String>()) {
        if (!key.startsWith('_coach') &&
            jsonEncode(prior[key]) != jsonEncode(row[key])) {
          fields.add(key);
        }
      }
      if (fields.isNotEmpty) {
        row['_coachRedactedFields'] = fields.toList()..sort();
      }
    }
  }
  _writeRedactionLedger(data);
  return coachBackupFromData(data);
}

String _stable(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      return {
        for (final k in v.keys.map((k) => k.toString()).toList()..sort())
          if (!k.startsWith('_coachRedacted')) k: sorted(v[k]),
      };
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

// Redaction provenance survives a database restore/export. Missing private
// fields must never become authoritative deletions on another device.
const _redactionLedgerId = 'privacy.redacted_fields.v1';

void _restoreRedactionMarkers(Map data) {
  final extensions = data['extensions'] as List;
  for (final record in extensions.where(
    (e) => e['kind'] == 'syncMetadata' && e['id'] == _redactionLedgerId,
  )) {
    final rows = (record['value'] as Map)['rows'];
    if (rows is! Map) continue;
    for (final table in rows.keys) {
      if (data[table] is! List || rows[table] is! Map) continue;
      for (final row in data[table] as List) {
        if (_profileOf(data, table, row) != record['profileId']) continue;
        final fields = (rows[table] as Map)[_id(table, row)];
        if (fields is List) {
          row['_coachRedactedFields'] = fields.whereType<String>().toList();
        }
      }
    }
  }
  extensions.removeWhere(
    (e) => e['kind'] == 'syncMetadata' && e['id'] == _redactionLedgerId,
  );
}

String? _profileOf(Map data, String table, Map row) {
  if (table == 'profiles') return row['id'] as String?;
  if (table == 'sourceChunks') {
    final parents = (data['sources'] as List).where(
      (s) => s['id'] == row['sourceId'],
    );
    return parents.isEmpty ? null : parents.first['profileId'] as String?;
  }
  return row['profileId'] as String?;
}

void _fillRedactedFields(Map target, Map source) {
  final fields = <String>{
    ...(target['_coachRedactedFields'] as List? ?? []).cast<String>(),
  };
  // Read old, pre-ledger envelopes too, without losing existing private data.
  if (fields.isEmpty && target['_coachRedacted'] == true) {
    fields.addAll(
      target.keys.whereType<String>().where(
        (k) =>
            !k.startsWith('_coach') &&
            (target[k] == null ||
                target[k] == '' ||
                (target[k] is List && (target[k] as List).isEmpty)),
      ),
    );
  }
  final sourceFields = (source['_coachRedactedFields'] as List? ?? []).toSet();
  for (final field in fields.toList()) {
    if (source.containsKey(field) &&
        !sourceFields.contains(field) &&
        !(source['_coachRedacted'] == true &&
            (source[field] == null ||
                source[field] == '' ||
                (source[field] is List && (source[field] as List).isEmpty)))) {
      target[field] = source[field];
      fields.remove(field);
    }
  }
  target.remove('_coachRedacted');
  if (fields.isEmpty) {
    target.remove('_coachRedactedFields');
  } else {
    target['_coachRedactedFields'] = fields.toList()..sort();
  }
}

void _writeRedactionLedger(Map data) {
  final byProfile = <String, Map<String, Map<String, List<String>>>>{};
  for (final table in data.keys.cast<String>()) {
    for (final row in data[table] as List) {
      final fields =
          (row['_coachRedactedFields'] as List? ?? [])
              .whereType<String>()
              .toList()
            ..sort();
      final profile = _profileOf(data, table, row);
      if (fields.isNotEmpty && profile != null) {
        final tables = byProfile.putIfAbsent(profile, () => {});
        tables.putIfAbsent(table, () => {})[_id(table, row)] = fields;
      }
      row.remove('_coachRedacted');
    }
  }
  final extensions = data['extensions'] as List;
  extensions.removeWhere(
    (e) => e['kind'] == 'syncMetadata' && e['id'] == _redactionLedgerId,
  );
  for (final profile in byProfile.keys.toList()..sort()) {
    extensions.add({
      'profileId': profile,
      'kind': 'syncMetadata',
      'id': _redactionLedgerId,
      'revision': 1,
      'updatedAt': '1970-01-01T00:00:00.000Z',
      'value': {'rows': byProfile[profile]},
    });
  }
}

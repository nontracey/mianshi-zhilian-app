import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/pages/practice/project_dig_page.dart';
import 'package:mianshi_zhilian/pages/prep/project_library_page.dart';

void main() {
  test(
    'buildProjectPayload preserves identity while updating editable fields',
    () {
      final now = DateTime.parse('2026-06-11T10:00:00.000');
      final project = buildProjectPayload(
        existingProject: {
          'id': 'project-1',
          'createdAt': '2026-01-01T00:00:00.000',
          'customField': 'keep',
        },
        name: '  New name  ',
        role: 'architect',
        scale: 'large',
        techStack: ['java', 'redis'],
        background: '  bg  ',
        task: 'task',
        action: 'action',
        result: 'result',
        now: now,
      );

      expect(project['id'], 'project-1');
      expect(project['createdAt'], '2026-01-01T00:00:00.000');
      expect(project['updatedAt'], now.toIso8601String());
      expect(project['customField'], 'keep');
      expect(project['name'], 'New name');
      expect(project['techStack'], 'java, redis');
    },
  );

  test('normalizeProjectLibraryRecord uses fallback identity on edit', () {
    final now = DateTime.parse('2026-06-11T10:00:00.000');
    final normalized = normalizeProjectLibraryRecord(
      {'name': 'edited', 'updatedAt': now.toIso8601String()},
      fallback: {
        'id': 'project-1',
        'createdAt': '2026-01-01T00:00:00.000',
        'name': 'old',
      },
      now: now,
    );

    expect(normalized['id'], 'project-1');
    expect(normalized['createdAt'], '2026-01-01T00:00:00.000');
    expect(normalized['updatedAt'], now.toIso8601String());
    expect(normalized['name'], 'edited');
  });

  test('parseProjectTechStack accepts legacy string and list shapes', () {
    expect(parseProjectTechStack('java, redis,  mq '), ['java', 'redis', 'mq']);
    expect(parseProjectTechStack(['java', ' redis ', '']), ['java', 'redis']);
  });
}

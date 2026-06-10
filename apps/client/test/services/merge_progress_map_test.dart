import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/data_sync_service.dart';

/// progress_map 合并：按 lastPracticeAt 做 last-write-wins（最近一次练习胜出），
/// practiceCount 取较大值，时间戳缺失/并列时本地优先。
void main() {
  Map<String, dynamic> entry({
    required int score,
    required int practiceCount,
    String? lastPracticeAt,
    String? nextReviewAt,
  }) =>
      {
        'score': score,
        'status': 'learning',
        'practiceCount': practiceCount,
        if (lastPracticeAt != null) 'lastPracticeAt': lastPracticeAt,
        if (nextReviewAt != null) 'nextReviewAt': nextReviewAt,
      };

  group('mergeProgressMaps — time LWW by lastPracticeAt', () {
    test('later lastPracticeAt wins even if its score is lower', () {
      // 远端：旧的高分；本地：更近一次练习但低分（真实退步）
      final remote = {
        'java.a': entry(score: 90, practiceCount: 3, lastPracticeAt: '2026-01-01T10:00:00.000'),
      };
      final local = {
        'java.a': entry(score: 50, practiceCount: 4, lastPracticeAt: '2026-02-01T10:00:00.000'),
      };

      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['score'], 50, reason: '最近一次练习胜出');
      expect((merged['java.a'] as Map)['practiceCount'], 4);
    });

    test('older local does not override newer remote', () {
      final remote = {
        'java.a': entry(score: 70, practiceCount: 5, lastPracticeAt: '2026-03-01T10:00:00.000'),
      };
      final local = {
        'java.a': entry(score: 95, practiceCount: 2, lastPracticeAt: '2026-01-01T10:00:00.000'),
      };

      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['score'], 70, reason: '远端更近一次练习胜出');
      // practiceCount 取较大值，不回退
      expect((merged['java.a'] as Map)['practiceCount'], 5);
    });

    test('practiceCount is the max of both sides (monotonic)', () {
      final remote = {
        'java.a': entry(score: 60, practiceCount: 9, lastPracticeAt: '2026-01-01T10:00:00.000'),
      };
      final local = {
        'java.a': entry(score: 80, practiceCount: 3, lastPracticeAt: '2026-02-01T10:00:00.000'),
      };
      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['practiceCount'], 9);
    });

    test('equal timestamps prefer local', () {
      const ts = '2026-02-01T10:00:00.000';
      final remote = {'java.a': entry(score: 70, practiceCount: 2, lastPracticeAt: ts)};
      final local = {'java.a': entry(score: 88, practiceCount: 2, lastPracticeAt: ts)};
      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['score'], 88);
    });

    test('local with timestamp beats remote without timestamp', () {
      final remote = {'java.a': entry(score: 99, practiceCount: 1)};
      final local = {
        'java.a': entry(score: 40, practiceCount: 1, lastPracticeAt: '2026-02-01T10:00:00.000'),
      };
      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['score'], 40);
    });

    test('remote with timestamp beats local without timestamp', () {
      final remote = {
        'java.a': entry(score: 99, practiceCount: 1, lastPracticeAt: '2026-02-01T10:00:00.000'),
      };
      final local = {'java.a': entry(score: 40, practiceCount: 1)};
      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect((merged['java.a'] as Map)['score'], 99);
    });

    test('remote-only and local-only entries both survive', () {
      final remote = {
        'java.a': entry(score: 70, practiceCount: 1, lastPracticeAt: '2026-01-01T10:00:00.000'),
      };
      final local = {
        'java.b': entry(score: 80, practiceCount: 1, lastPracticeAt: '2026-01-01T10:00:00.000'),
      };
      final merged = DataSyncService.mergeProgressMaps(remote, local);
      expect(merged.keys, containsAll(['java.a', 'java.b']));
    });

    test('null inputs are handled gracefully', () {
      expect(DataSyncService.mergeProgressMaps(null, null), isEmpty);
      final onlyLocal = DataSyncService.mergeProgressMaps(null, {
        'x': entry(score: 1, practiceCount: 1),
      });
      expect(onlyLocal.keys, contains('x'));
    });
  });
}

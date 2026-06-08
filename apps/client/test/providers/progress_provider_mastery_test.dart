import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/models/user_progress.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';

void main() {
  group('computeMastery', () {
    test('returns new_ for null progress', () {
      final result = ProgressProvider.computeMastery(
        't1',
        progressMap: {},
        attempts: [],
      );
      expect(result, MasteryStatus.new_);
    });

    test('returns new_ for score < 60', () {
      final result = ProgressProvider.computeMastery(
        't1',
        progressMap: {'t1': _progress(50)},
        attempts: [],
      );
      expect(result, MasteryStatus.new_);
    });

    test('returns learning for single high score', () {
      final result = ProgressProvider.computeMastery(
        't1',
        progressMap: {'t1': _progress(85)},
        attempts: [_attempt(85, -1)],
      );
      expect(result, MasteryStatus.learning);
    });

    test('returns learning when two high scores are within 1 hour', () {
      final result = ProgressProvider.computeMastery(
        't1',
        progressMap: {'t1': _progress(90)},
        attempts: [
          _attempt(90, -2),
          _attempt(90, -1),
        ],
      );
      expect(result, MasteryStatus.learning);
    });

    test('returns skilled for two high scores > 1 hour apart', () {
      final result = ProgressProvider.computeMastery(
        't1',
        progressMap: {'t1': _progress(90)},
        attempts: [
          _attempt(90, -120),
          _attempt(90, 0),
        ],
      );
      expect(result, MasteryStatus.skilled);
    });
  });
}

TopicProgress _progress(int score) {
  return TopicProgress(
    topicId: 't1',
    score: score,
    status: score >= 85 ? 'mastered' : (score >= 60 ? 'learning' : 'new'),
    practiceCount: 1,
    lastPracticeAt: DateTime.now(),
    nextReviewAt: DateTime.now().add(const Duration(days: 7)),
  );
}

PracticeAttempt _attempt(int score, int minutesAgo) {
  return PracticeAttempt(
    id: 'a1',
    topicId: 't1',
    promptId: 'p1',
    mode: 'recall',
    question: 'q',
    answer: 'a',
    createdAt: DateTime.now().add(Duration(minutes: minutesAgo)),
    score: score,
    aiEvaluated: true,
    localOnly: true,
  );
}

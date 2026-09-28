/// Store 契约一致性测试：同一套断言同时跑 [InMemoryCoachStore] 与
/// [DriftCoachStore]（真实内存 SQLite）。
///
/// 测试长期跑在内存实现上、生产跑在 SQLite 上，两者行为分歧是最隐蔽的
/// bug 温床；这里锁定双方必须一致的语义：
/// 1. 事务失败整体回滚；
/// 2. 扩展记录按 updatedAt 升序返回；
/// 3. 墓碑修剪保留每实体最新代次与全部 profile_reset；
/// 4. 删除来源级联清理分块与入库任务。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/coach/domain/goal.dart';
import 'package:mianshi_zhilian/coach/domain/profile.dart';
import 'package:mianshi_zhilian/coach/knowledge/source.dart';
import 'package:mianshi_zhilian/coach/persistence/coach_store.dart';
import 'package:mianshi_zhilian/coach/persistence/drift_store_native.dart';
import 'package:mianshi_zhilian/coach/persistence/extension_records.dart';

const profileId = 'p-contract';

void runContractTests(CoachStore Function() factory, {bool closeAfter = false}) {
  late CoachStore store;

  setUp(() => store = factory());

  tearDown(() async {
    if (closeAfter) await (store as dynamic).close();
  });

  test('transaction failure rolls back every write inside', () async {
    await store.putProfile(_profile());
    expect(
      () => store.transaction(() async {
        await store.putGoal(_goal('g-rollback'));
        await store.putGoal(_goal('g-rollback-2'));
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(await store.getGoal('g-rollback'), isNull);
    expect(await store.getGoal('g-rollback-2'), isNull);
  });

  test('listExtensions returns records ordered by updatedAt asc', () async {
    final late = DateTime(2026, 9, 11, 10);
    final early = DateTime(2026, 9, 11, 9);
    // 先写晚的再写早的：插入顺序与时间顺序相反，排序必须由 store 保证。
    await store.putExtension(_ext('late', late));
    await store.putExtension(_ext('early', early));
    await store.putExtension(_ext('middle', early.add(const Duration(minutes: 30))));

    final records = await store.listExtensions(
      profileId,
      CoachExtensionKind.modelTurn,
    );
    expect(records.map((r) => r.id).toList(), ['early', 'middle', 'late']);
  });

  test('pruneTombstones keeps latest generation per entity and profile_reset',
      () async {
    await store.putTombstone(_tomb('goal', 'g1', 1));
    await store.putTombstone(_tomb('goal', 'g1', 2));
    await store.putTombstone(_tomb('goal', 'g2', 1));
    await store.putTombstone(_tomb('profile_reset', profileId, 7));

    final removed = await store.pruneTombstones(profileId);

    expect(removed, 1);
    final left = await store.listTombstones(profileId);
    expect(left, hasLength(3));
    expect(
      left.where((t) => t.entityId == 'g1').every((t) => t.generation == 2),
      isTrue,
    );
    expect(left.where((t) => t.entityType == 'profile_reset'), hasLength(1));
  });

  test('deleteSource cascades chunks and ingestion jobs', () async {
    final source = Source(
      id: 'src-1',
      profileId: profileId,
      title: 'Demo material',
      type: SourceType.paste,
      contentHash: 'hash',
      status: IngestionStatus.ready,
      content: 'private body text',
      createdAt: DateTime(2026, 9, 11),
    );
    await store.putSource(source);
    await store.putSourceChunk(
      SourceChunk(
        id: 'chunk-1',
        sourceId: source.id,
        sourceRevision: 1,
        index: 0,
        content: 'private chunk',
        titlePath: null,
        hash: 'h1',
      ),
    );
    await store.putIngestionJob(
      IngestionJob(
        id: 'job-1',
        profileId: profileId,
        sourceId: source.id,
        status: IngestionStatus.ready,
        createdAt: DateTime(2026, 9, 11),
      ),
    );

    await store.deleteSource(source.id);

    expect(await store.getSource(source.id), isNull);
    expect(await store.listSourceChunks(source.id), isEmpty);
    expect(await store.listIngestionJobs(source.id), isEmpty);
  });
}

void main() {
  group('Store contract - InMemoryCoachStore', () {
    runContractTests(InMemoryCoachStore.new);
  });

  group('Store contract - DriftCoachStore (in-memory SQLite)', () {
    runContractTests(openNativeCoachStoreMemory, closeAfter: true);
  });
}

Profile _profile() => Profile(
  id: profileId,
  displayName: 'Contract',
  baseLevel: '中级',
  teachingPreference: '追问原理',
  createdAt: DateTime(2026, 9, 11),
  updatedAt: DateTime(2026, 9, 11),
);

Goal _goal(String id) => Goal(
  id: id,
  profileId: profileId,
  title: 'Demo goal',
  originalText: 'body',
  contentHash: 'h-$id',
  active: true,
  createdAt: DateTime(2026, 9, 11),
  updatedAt: DateTime(2026, 9, 11),
);

CoachExtensionRecord _ext(String id, DateTime at) => CoachExtensionRecord(
  profileId: profileId,
  kind: CoachExtensionKind.modelTurn,
  id: id,
  revision: 1,
  value: const {'turn': 1},
  updatedAt: at,
);

CoachTombstone _tomb(String entity, String entityId, int generation) =>
    CoachTombstone(
      profileId: profileId,
      entityType: entity,
      entityId: entityId,
      generation: generation,
      deletedAt: DateTime(2026, 9, 11).add(Duration(minutes: generation)),
      operationId: 'op-$entity-$entityId-$generation',
    );

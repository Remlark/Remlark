import 'package:remlark_sync_server/remlark_sync_server.dart';
import 'package:test/test.dart';

void main() {
  late SyncDatabase db;
  late SyncRepository repository;

  setUp(() {
    db = SyncDatabase.memory();
    repository = SyncRepository(db);
  });
  tearDown(() => db.close());

  test('新增主机只保存一条记录，索引不暴露密文载荷', () async {
    expect(
      await repository.put('space', 'h1', 100, 'cipher'),
      PutResult.stored,
    );
    final index = await repository.index('space');
    expect(index, [
      {'uuid': 'h1', 'updatedAt': 100, 'deleted': false},
    ]);
    expect((await repository.fetch('space', ['h1'])).single.payload, 'cipher');
  });

  test('较新版本可以替换，较旧版本不会覆盖服务端主机', () async {
    await repository.put('space', 'h1', 100, 'first');
    expect(
      await repository.put('space', 'h1', 200, 'latest'),
      PutResult.stored,
    );
    expect(
      await repository.put('space', 'h1', 150, 'stale'),
      PutResult.conflict,
    );
    expect((await repository.fetch('space', ['h1'])).single.payload, 'latest');
  });

  test('同版本不同密文返回冲突，避免并发修改覆盖已提交版本', () async {
    await repository.put('space', 'h1', 100, 'first');
    expect(
      await repository.put('space', 'h1', 100, 'different'),
      PutResult.conflict,
    );
    expect((await repository.fetch('space', ['h1'])).single.payload, 'first');
  });

  test('同版本同密文重复请求幂等，不产生额外记录', () async {
    await repository.put('space', 'h1', 100, 'cipher');
    expect(
      await repository.put('space', 'h1', 100, 'cipher'),
      PutResult.stored,
    );
    expect((await repository.index('space')).length, 1);
  });

  test('相同 UUID 在不同用户空间相互隔离', () async {
    await repository.put('space-a', 'h1', 100, 'a-cipher');
    await repository.put('space-b', 'h1', 200, 'b-cipher');
    expect(
      (await repository.fetch('space-a', ['h1'])).single.payload,
      'a-cipher',
    );
    expect(
      (await repository.fetch('space-b', ['h1'])).single.payload,
      'b-cipher',
    );
    expect(await repository.fetch('space-c', ['h1']), isEmpty);
    await repository.delete('space-a', 'h1');
    expect((await repository.fetch('space-b', ['h1'])).single.deleted, isFalse);
  });

  test('删除保留标记并清空载荷，再次显式上传可恢复主机', () async {
    await repository.put('space', 'h1', 100, 'cipher');
    expect(await repository.delete('space', 'h1'), isTrue);
    final deleted = (await repository.fetch('space', ['h1'])).single;
    expect(deleted.deleted, isTrue);
    expect(deleted.payload, isEmpty);
    expect(
      await repository.put(
        'space',
        'h1',
        deleted.updatedAt + 1,
        'stale-device',
      ),
      PutResult.conflict,
    );
    expect(
      await repository.put(
        'space',
        'h1',
        200,
        'restored',
        restoreDeleted: true,
      ),
      PutResult.stored,
    );
    expect((await repository.fetch('space', ['h1'])).single.deleted, isFalse);
  });

  test('删除不存在的主机返回未找到，不影响其他主机', () async {
    await repository.put('space', 'h1', 100, 'cipher');
    expect(await repository.delete('space', 'missing'), isFalse);
    expect((await repository.index('space')).length, 1);
  });

  test('多个客户端并发上传同一主机，最终保留最后配置修改版本', () async {
    final otherClient = SyncRepository(db);
    final versions = [20, 100, 5, 99, 1, 200, 30, 150];
    await Future.wait([
      for (var i = 0; i < versions.length; i++)
        (i.isEven ? repository : otherClient).put(
          'space',
          'h1',
          versions[i],
          'cipher-${versions[i]}',
        ),
    ]);
    final latest = (await repository.fetch('space', ['h1'])).single;
    expect(latest.updatedAt, 200);
    expect(latest.payload, 'cipher-200');
  });

  test('不同客户端、主机和空间同时提交，各自主机版本独立且不会丢失', () async {
    final otherClient = SyncRepository(db);
    await Future.wait([
      for (var i = 0; i < 40; i++)
        (i.isEven ? repository : otherClient).put(
          'space-${i % 2}',
          'h${i % 5}',
          i,
          'cipher-$i',
        ),
    ]);
    for (var space = 0; space < 2; space++) {
      final records = await repository.fetch('space-$space', [
        for (var h = 0; h < 5; h++) 'h$h',
      ]);
      expect(records.length, 5);
      for (final record in records) {
        final expected = [
          for (var i = 0; i < 40; i++)
            if (i % 2 == space && 'h${i % 5}' == record.uuid) i,
        ].last;
        expect(record.updatedAt, expected);
      }
    }
  });

  test('写入、读取、删除、再读取按入队顺序执行', () async {
    final write = repository.put('space', 'h1', 100, 'cipher');
    final beforeDelete = repository.fetch('space', ['h1']);
    final delete = repository.delete('space', 'h1');
    final afterDelete = repository.fetch('space', ['h1']);
    await write;
    expect((await beforeDelete).single.deleted, isFalse);
    expect(await delete, isTrue);
    expect((await afterDelete).single.deleted, isTrue);
  });

  test('某个客户端数据库操作失败后，全局队列仍继续处理其他客户端', () async {
    final closedDatabase = SyncDatabase.memory();
    final badClient = SyncRepository(closedDatabase);
    await badClient.index('space');
    await closedDatabase.close();
    await expectLater(badClient.index('space'), throwsA(anything));
    expect(
      await repository.put('space', 'h1', 100, 'cipher'),
      PutResult.stored,
    );
  });
}

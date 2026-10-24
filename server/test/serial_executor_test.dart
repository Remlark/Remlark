import 'dart:async';

import 'package:remlark_sync_server/src/utils/serial_executor.dart';
import 'package:test/test.dart';

void main() {
  test('后续任务等待前一任务完成，并按请求进入顺序执行', () async {
    final queue = SerialExecutor();
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final first = queue.run(() async {
      events.add('first-start');
      entered.complete();
      await release.future;
      events.add('first-end');
      return 1;
    });
    final second = queue.run(() async {
      events.add('second');
      return 2;
    });
    await entered.future;
    expect(events, ['first-start']);
    release.complete();
    expect(await Future.wait([first, second]), [1, 2]);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('大量异步任务的最大并行数始终为一', () async {
    final queue = SerialExecutor();
    var active = 0;
    var maximum = 0;
    final futures = [
      for (var i = 0; i < 100; i++)
        queue.run(() async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          return i;
        }),
    ];
    expect(await Future.wait(futures), List.generate(100, (i) => i));
    expect(maximum, 1);
  });

  test('同步或异步任务失败会通知调用方，但不阻断后续任务', () async {
    final queue = SerialExecutor();
    final synchronous = queue.run<int>(() => throw StateError('sync failure'));
    final asynchronous = queue.run<int>(
      () async => throw StateError('async failure'),
    );
    final success = queue.run(() async => 42);
    await expectLater(synchronous, throwsStateError);
    await expectLater(asynchronous, throwsStateError);
    expect(await success, 42);
  });
}

// 启动外部进程，ARM runner 上进程启动慢，放宽默认 30 秒时限。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-24：Actions 临时包保留策略与安全清理范围。
void main() {
  test('分页删除仅覆盖当前运行的中转包，不触碰历史运行', () async {
    final result = await Process.run('python3', [
      'tools/testing/artifact_cleanup_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('仅构建不上传压缩包，中转保留七天，发布成功后才清理', () {
    final workflow = File('.github/workflows/release.yml')
        .readAsLinesSync()
        .join('\n');
    for (final name in ['Upload packages', 'Upload server package']) {
      expect(
        workflow,
        contains('''- name: $name
        if: github.event_name != 'workflow_dispatch' || !inputs.build_only
        uses: actions/upload-artifact@v4'''),
      );
    }
    // 失败时其他平台包必须留存，才能 Re-run failed jobs；重跑同名包覆盖旧包。
    expect('retention-days: 7'.allMatches(workflow).length, 2);
    expect('overwrite: true'.allMatches(workflow).length, 2);
    expect(workflow, isNot(contains('retention-days: 1')));
    expect(workflow, isNot(contains('name: Upload native build logs')));
    final cleanup = workflow.substring(workflow.indexOf('  cleanup:'));
    expect(cleanup, contains('needs: [publish]'));
    expect(cleanup, contains("if: needs.publish.result == 'success'"));
    expect(cleanup, isNot(contains('always()')));
    expect(cleanup, contains('actions: write'));
    expect(cleanup, contains('python3 tools/release/cleanup_artifacts.py'));
  });
}

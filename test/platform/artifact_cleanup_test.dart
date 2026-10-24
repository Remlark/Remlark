import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 多平台测试 P-24：Actions 临时包保留策略与安全清理范围。
void main() {
  test('分页删除仅覆盖本工作流已结束运行及当前中转包', () async {
    final result = await Process.run('python3', [
      'tools/testing/artifact_cleanup_test.py',
      '-v',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('仅构建不上传压缩包，正式发布中转一天且始终执行清理', () {
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
    expect('retention-days: 1'.allMatches(workflow).length, 2);
    expect(workflow, isNot(contains('name: Upload native build logs')));
    final cleanup = workflow.substring(workflow.indexOf('  cleanup:'));
    expect(cleanup, contains('needs: [build, server, publish]'));
    expect(cleanup, contains('if: always()'));
    expect(cleanup, contains('actions: write'));
    expect(cleanup, contains('python3 tools/release/cleanup_artifacts.py'));
  });
}

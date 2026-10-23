import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/utils/network/connect_error_policy.dart';
import 'package:remlark/utils/network/connect_error_policy_linux.dart';
import 'package:remlark/utils/network/connect_error_policy_macos.dart';
import 'package:remlark/utils/network/connect_error_policy_windows.dart';
import 'package:remlark/utils/network/connect_retry.dart';

/// P-20：三平台不可达分类、首次失败恢复、有限重试及总超时预算。
void main() {
  final platforms = [
    ('macOS', const MacosConnectErrorPolicy(), [51, 65], [61, 60, 13, 101, 113, 10065]),
    ('Linux', const LinuxConnectErrorPolicy(), [101, 113], [111, 110, 13, 51, 65, 10065]),
    ('Windows', const WindowsConnectErrorPolicy(), [10051, 10065], [10061, 10060, 10013, 51, 65, 113]),
  ];

  /// 生成系统异常，错误文案刻意不使用英文系统消息。
  SocketException failure(int code) => SocketException('测试错误', osError: OSError('测试', code));

  for (final (name, policy, retryCodes, otherCodes) in platforms) {
    group(name, () {
      test('只识别本平台网络/主机不可达', () {
        for (final code in retryCodes) {
          expect(policy.isUnreachable(failure(code)), isTrue);
        }
        for (final code in otherCodes) {
          expect(policy.isUnreachable(failure(code)), isFalse);
        }
        expect(policy.isUnreachable(const SocketException('No route to host')), isFalse);
      });

      test('第一次不可达后恢复，成功结果只返回一次', () async {
        for (final code in retryCodes) {
          var calls = 0;
          final pauses = <Duration>[];
          final budgets = <Duration>[];
          final result = await ConnectRetry.run(
            (remaining) async {
              budgets.add(remaining);
              if (++calls == 1) throw failure(code);
              return 'connected';
            },
            timeout: const Duration(seconds: 15),
            policy: policy,
            wait: (delay) async {
              pauses.add(delay);
            },
          );
          expect(result, 'connected');
          expect(calls, 2);
          expect(pauses, [const Duration(milliseconds: 500)]);
          expect(budgets.last, lessThanOrEqualTo(budgets.first));
        }
      });

      test('持续不可达最多四次并保留原异常', () async {
        var calls = 0;
        final pauses = <Duration>[];
        final error = failure(retryCodes.last);
        await expectLater(
          ConnectRetry.run(
            (_) async {
              calls++;
              throw error;
            },
            timeout: const Duration(seconds: 15),
            policy: policy,
            wait: (delay) async {
              pauses.add(delay);
            },
          ),
          throwsA(same(error)),
        );
        expect(calls, 4);
        expect(pauses, [const Duration(milliseconds: 500), const Duration(seconds: 1), const Duration(seconds: 2)]);
      });

      test('连接拒绝、超时、权限错误不重试', () async {
        for (final code in otherCodes) {
          var calls = 0;
          final error = failure(code);
          await expectLater(
            ConnectRetry.run(
              (_) async {
                calls++;
                throw error;
              },
              timeout: const Duration(seconds: 15),
              policy: policy,
              wait: (_) async {
                fail('非不可达错误不能等待重试');
              },
            ),
            throwsA(same(error)),
          );
          expect(calls, 1);
        }
      });

      test('预算不足以等待时立即保留系统错误', () async {
        var calls = 0;
        final error = failure(retryCodes.first);
        await expectLater(
          ConnectRetry.run(
            (_) async {
              calls++;
              throw error;
            },
            timeout: const Duration(milliseconds: 100),
            policy: policy,
            wait: (_) async {
              fail('不能延长总超时');
            },
          ),
          throwsA(same(error)),
        );
        expect(calls, 1);
      });

      test('正常连接不等待，非 Socket 异常不重试', () async {
        expect(
          await ConnectRetry.run(
            (_) async => 42,
            timeout: const Duration(seconds: 15),
            policy: policy,
            wait: (_) async => fail('正常连接不能等待'),
          ),
          42,
        );
        final error = StateError('非 TCP 错误');
        await expectLater(
          ConnectRetry.run(
            (_) async => throw error,
            timeout: const Duration(seconds: 15),
            policy: policy,
            wait: (_) async => fail('非 Socket 错误不能重试'),
          ),
          throwsA(same(error)),
        );
      });
    });
  }

  test('当前平台选择正确策略', () {
    final current = ConnectErrorPolicy.current();
    if (Platform.isMacOS) expect(current, isA<MacosConnectErrorPolicy>());
    if (Platform.isLinux) expect(current, isA<LinuxConnectErrorPolicy>());
    if (Platform.isWindows) expect(current, isA<WindowsConnectErrorPolicy>());
    expect(const UnsupportedConnectErrorPolicy().isUnreachable(failure(65)), isFalse);
  });
}

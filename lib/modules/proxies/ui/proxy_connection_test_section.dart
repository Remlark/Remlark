import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/network_endpoint.dart';
import '../../hosts/host_model.dart';
import '../proxy_connection_test.dart';

/// 可选的代理连接检测：结果不参与保存校验，修改参数即使旧结果失效。
class ProxyConnectionTestSection extends StatefulWidget {
  const ProxyConnectionTestSection({
    super.key,
    required this.config,
    this.enabled = true,
    this.connectionTest,
  });
  final ProxyConfig config;
  final bool enabled;
  final ProxyConnectionTest? connectionTest;

  /// 创建一次弹窗范围内的测试状态。
  @override
  State<ProxyConnectionTestSection> createState() =>
      _ProxyConnectionTestSectionState();
}

class _ProxyConnectionTestSectionState
    extends State<ProxyConnectionTestSection> {
  final _target = TextEditingController(text: 'example.com:443');
  late final _connectionTest =
      widget.connectionTest ?? SocketProxyConnectionTest();
  int _request = 0;
  bool _testing = false;
  ProxyTestResult? _result;
  String? _targetError;

  /// 代理参数或保存状态变化时取消检测，防止旧结果套用到新配置。
  @override
  void didUpdateWidget(covariant ProxyConnectionTestSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.config.sameConnectionAs(oldWidget.config) || !widget.enabled) {
      _invalidate();
    }
  }

  /// 关闭弹窗时释放连接和目标输入框。
  @override
  void dispose() {
    _connectionTest.cancel();
    _target.dispose();
    super.dispose();
  }

  /// 递增请求标识，晚到的结果不再更新界面。
  void _invalidate() {
    _request++;
    _connectionTest.cancel();
    _testing = false;
    _result = null;
    _targetError = null;
  }

  /// 只验证代理连接参数和测试目标，不要求代理名称，也不影响保存按钮。
  Future<void> _run() async {
    final target = NetworkEndpoint.tryParse(_target.text);
    if (target == null) {
      setState(() => _targetError = context.tr('proxy.test.target_invalid'));
      return;
    }
    if (!widget.config.enabled || widget.config.port > 65535) {
      setState(
        () => _result = const ProxyTestResult(
          ProxyTestStatus.invalid,
          Duration.zero,
        ),
      );
      return;
    }
    final request = ++_request;
    setState(() {
      _testing = true;
      _result = null;
      _targetError = null;
    });
    ProxyTestResult result;
    try {
      result = await _connectionTest.check(widget.config, target);
    } catch (_) {
      result = const ProxyTestResult(ProxyTestStatus.connection, Duration.zero);
    }
    if (!mounted || request != _request) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  /// 使用语义状态、图标与中英文文案，不直接显示未经处理的服务端错误。
  Widget _feedback(BuildContext context) {
    final p = context.palette;
    final status = _result?.status;
    final success = status == ProxyTestStatus.success;
    final color = success ? p.success : p.danger;
    final key = switch (status) {
      ProxyTestStatus.success => 'proxy.test.success',
      ProxyTestStatus.timeout => 'proxy.test.timeout',
      ProxyTestStatus.authentication => 'proxy.test.authentication',
      ProxyTestStatus.invalid => 'proxy.test.invalid_proxy',
      _ => 'proxy.test.failed',
    };
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_testing)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('proxy.test.running'),
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
              ],
            )
          else if (status != null && status != ProxyTestStatus.cancelled)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  success ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(key, {'ms': _result!.elapsed.inMilliseconds}),
                    style: TextStyle(fontSize: 14, color: color),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Text(
            context.tr('proxy.test.hint'),
            style: TextStyle(fontSize: 12, color: p.textMuted),
          ),
        ],
      ),
    );
  }

  /// 测试目标与按钮合成一行，进度及结果占用紧凑的说明区。
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('proxy.test.title'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      Text(
        context.tr('proxy.test.target'),
        style: TextStyle(fontSize: 12, color: context.palette.textMuted),
      ),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('proxy-test-target'),
              controller: _target,
              enabled: widget.enabled,
              decoration: InputDecoration(errorText: _targetError),
              onChanged: (_) => setState(_invalidate),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: widget.enabled && !_testing ? _run : null,
              child: Text(context.tr('proxy.test.action')),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _feedback(context),
    ],
  );
}

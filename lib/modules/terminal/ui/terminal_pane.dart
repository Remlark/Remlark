import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../settings/settings_controller.dart';
import '../../workspace/workspace_tab.dart';
import '../terminal_session.dart';
import 'terminal_themes.dart';
import 'upload_helper.dart';

/// 终端面板：xterm 视图 + 拖拽上传 + 右键（有选区复制 / 无选区粘贴：文本输入、文件上传）
/// + 快捷键复制粘贴 + 连接状态遮罩
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session, this.autofocus = true});

  final TerminalSession session;
  final bool autofocus;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _focus = FocusNode();
  bool _dragging = false;
  Timer? _copyDebounce;

  TerminalSession get s => widget.session;

  bool get _isApple => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    s.controller.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalPane old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.controller.removeListener(_onSelectionChanged);
      widget.session.controller.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    s.controller.removeListener(_onSelectionChanged);
    _copyDebounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// “选中即复制”设置开启时，选区稳定后自动复制
  void _onSelectionChanged() {
    if (!context.read<SettingsController>().copyOnSelect) return;
    _copyDebounce?.cancel();
    _copyDebounce = Timer(const Duration(milliseconds: 400), () {
      final t = s.selectedText();
      if (t != null) Clipboard.setData(ClipboardData(text: t));
    });
  }

  /// 复制选区
  bool _copy() {
    final t = s.selectedText();
    if (t == null) return false;
    Clipboard.setData(ClipboardData(text: t));
    s.controller.clearSelection();
    UiUtils.toast(context.tr('common.copied'));
    return true;
  }

  /// 粘贴：剪贴板为文件时上传，为文本时输入
  Future<void> _paste() async {
    List<String> files = const [];
    try {
      files = await Pasteboard.files();
    } catch (_) {}
    if (!mounted) return;
    if (files.isNotEmpty) {
      await UploadHelper.upload(context, s, files);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) s.pasteText(text);
  }

  /// 拦截粘贴快捷键（macOS: Cmd+V，其他: Ctrl+Shift+V / Shift+Insert）
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    final isPaste = _isApple
        ? (k.isMetaPressed && e.logicalKey == LogicalKeyboardKey.keyV)
        : ((k.isControlPressed && k.isShiftPressed && e.logicalKey == LogicalKeyboardKey.keyV) ||
              (k.isShiftPressed && e.logicalKey == LogicalKeyboardKey.insert));
    if (isPaste) {
      _paste();
      return KeyEventResult.handled;
    }
    final isCopy = !_isApple && k.isControlPressed && e.logicalKey == LogicalKeyboardKey.insert;
    if (isCopy && _copy()) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  Map<ShortcutActivator, Intent> get _shortcuts => _isApple
      ? {
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopySelectionTextIntent.copy,
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): const SelectAllTextIntent(
            SelectionChangedCause.keyboard,
          ),
        }
      : {
          const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): CopySelectionTextIntent.copy,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): const SelectAllTextIntent(
            SelectionChangedCause.keyboard,
          ),
        };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final theme = TerminalThemesX.byId(settings.terminalTheme);
    final family = settings.terminalFontFamily.trim();
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        UploadHelper.upload(context, s, d.files.map((f) => f.path).toList());
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: theme.background,
              padding: const EdgeInsets.only(left: 6, top: 4),
              child: TerminalView(
                s.terminal,
                controller: s.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                theme: theme,
                textStyle: TerminalStyle(
                  fontSize: settings.terminalFontSize,
                  fontFamily: family.isEmpty ? (_isApple ? 'Menlo' : 'monospace') : family,
                ),
                shortcuts: _shortcuts,
                onKeyEvent: _onKey,
                onSecondaryTapDown: (details, offset) {
                  if (!_copy()) _paste();
                },
              ),
            ),
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    context.tr('upload.drop_here'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ListenableBuilder(
            listenable: s,
            builder: (context, _) => _StateOverlay(session: s),
          ),
        ],
      ),
    );
  }
}

/// 连接中 / 失败 / 断开时的遮罩
class _StateOverlay extends StatelessWidget {
  const _StateOverlay({required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    if (st == SessionState.connected) return const SizedBox.shrink();
    if (st == SessionState.connecting) {
      return Positioned(
        right: 16,
        top: 12,
        child: Chip(
          avatar: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text(context.tr('terminal.connecting', {'name': session.progress ?? session.host.name})),
        ),
      );
    }
    final cancelled = session.error == 'cancelled';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  st == SessionState.failed ? Icons.error_outline : Icons.link_off,
                  color: st == SessionState.failed ? Colors.red : Colors.orange,
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    cancelled
                        ? context.tr('terminal.cancelled')
                        : st == SessionState.failed
                        ? context.tr('terminal.failed')
                        : context.tr('terminal.disconnected'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(context.tr('terminal.reconnect')),
                  onPressed: session.reconnect,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

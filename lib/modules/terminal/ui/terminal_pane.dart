import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../../ui_kit/file_drop_target.dart';
import '../../../app/nav_controller.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../../settings/settings_controller.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/workspace_tab.dart';
import '../terminal_session.dart';
import 'terminal_themes.dart';
import 'upload_helper.dart';
import '../../../ui_kit/app_menu.dart';

/// 终端面板：xterm 视图 + 拖拽上传 + 右键菜单（复制 / 粘贴：文本输入、文件上传）
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
  NavController? _nav;
  WorkspaceController? _workspace;
  bool _visible = false;

  TerminalSession get s => widget.session;

  bool get _isApple => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    s.controller.addListener(_onSelectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<NavController>();
    final ws = context.read<WorkspaceController>();
    if (nav != _nav || ws != _workspace) {
      _nav?.removeListener(_onVisibilityChanged);
      _workspace?.removeListener(_onVisibilityChanged);
      _nav = nav..addListener(_onVisibilityChanged);
      _workspace = ws..addListener(_onVisibilityChanged);
      _visible = _isVisible();
    }
  }

  /// 本终端当前是否对用户可见且处于激活状态（工作区页 + 当前标签）
  bool _isVisible() => _nav?.page == AppPage.sessions && _workspace?.active == s;

  /// 从其他页面 / 其他标签切回本终端时，把键盘焦点还给终端；
  /// 只在“不可见 → 可见”时触发，避免抢走 AI 输入框等其他控件的焦点
  void _onVisibilityChanged() {
    final v = _isVisible();
    if (v && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isVisible()) _focus.requestFocus();
      });
    }
    _visible = v;
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
    _nav?.removeListener(_onVisibilityChanged);
    _workspace?.removeListener(_onVisibilityChanged);
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

  /// 右键菜单：复制选区、粘贴（剪贴板为文件时显示为“粘贴并上传”）
  Future<void> _contextMenu(Offset pos) async {
    // 先记下选区，避免弹出菜单期间选区变化
    final selected = s.selectedText();
    List<String> files = const [];
    var hasText = false;
    try {
      files = await Pasteboard.files();
    } catch (_) {}
    try {
      hasText = await Clipboard.hasStrings();
    } catch (_) {}
    if (!mounted) return;
    final connected = s.state == SessionState.connected;
    final r = await AppMenu.showAt<String>(context, pos, [
      AppMenuItem(
        value: 'copy',
        label: context.tr('common.copy'),
        shortcut: _isApple ? '⌘C' : 'Ctrl+Shift+C',
        enabled: selected != null,
      ),
      AppMenuItem(
        value: 'paste',
        label: files.isNotEmpty
            ? context.tr('terminal.menu.paste_upload', {'count': files.length})
            : context.tr('terminal.menu.paste'),
        shortcut: _isApple ? '⌘V' : 'Ctrl+Shift+V',
        enabled: connected && (files.isNotEmpty || hasText),
      ),
    ]);
    if (!mounted) return;
    switch (r) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: selected!));
        s.controller.clearSelection();
        UiUtils.toast(context.tr('common.copied'));
      case 'paste':
        await _paste();
    }
    _focus.requestFocus();
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
    final theme = TerminalThemesX.byId(settings.terminalTheme, Theme.of(context).brightness);
    return FileDropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        UploadHelper.upload(context, s, d.files.map((f) => f.path).toList());
      },
      // 必须撑满父级：连接成功后遮罩返回非定位的 SizedBox.shrink，
      // 若 Stack 按子组件定尺寸，在 Row 等宽松约束下高度会塌缩为 0，终端内容溢出绘制到中间且无法点击聚焦
      child: Stack(
        fit: StackFit.expand,
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
                  // 使用系统等宽字体（macOS 为 Menlo），不提供自定义
                  fontFamily: _isApple ? 'Menlo' : 'monospace',
                ),
                shortcuts: _shortcuts,
                onKeyEvent: _onKey,
                // 远程程序开启鼠标上报（vim、tmux 等）时右键交给远程，不弹菜单
                onSecondaryTapDown: (details, offset) => _contextMenu(details.globalPosition),
              ),
            ),
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.palette.accent.withValues(alpha: 0.10),
                    border: Border.all(color: context.palette.accent, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    context.tr('upload.drop_here'),
                    style: TextStyle(color: context.palette.text, fontSize: 18, fontWeight: FontWeight.w600),
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
    final p = context.palette;
    if (st == SessionState.connected) return const SizedBox.shrink();
    if (st == SessionState.connecting) {
      return Positioned(
        right: 16,
        top: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.panelRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(
                context.tr('terminal.connecting', {'name': session.progress ?? session.host.name}),
                style: TextStyle(fontSize: 13, color: p.text),
              ),
            ],
          ),
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
          elevation: 6,
          color: p.panelRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: p.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  st == SessionState.failed ? Icons.error_outline : Icons.link_off,
                  color: st == SessionState.failed ? p.danger : p.warning,
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
                FilledButton.icon(
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

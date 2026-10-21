import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/sync/sync_service.dart';
import '../../modules/workspace/workspace_controller.dart';
import '../../ui_kit/nav_tile.dart';
import '../../utils/format_utils.dart';
import '../../utils/ui_utils.dart';
import '../nav_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// 应用导航栏：品牌、五个主入口、设置与同步状态
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final nav = context.watch<NavController>();
    final sessions = context.select<WorkspaceController, int>((w) => w.tabs.length);
    final items = <(AppPage, IconData, String)>[
      (AppPage.hosts, Icons.desktop_windows_outlined, context.tr('nav.hosts')),
      (AppPage.sessions, Icons.folder_open_outlined, context.tr('nav.sessions')),
      (AppPage.snippets, Icons.terminal_rounded, context.tr('nav.snippets')),
      (AppPage.keys, Icons.vpn_key_outlined, context.tr('nav.keys')),
      (AppPage.ai, Icons.auto_awesome_outlined, context.tr('nav.ai')),
    ];
    return Container(
      width: AppSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: p.sidebar,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                for (final (page, icon, label) in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: NavTile(
                      icon: icon,
                      label: label,
                      height: 48,
                      selected: nav.page == page,
                      onTap: () => nav.go(page),
                      // 工作区显示打开的会话数量
                      trailing: page == AppPage.sessions && sessions > 0 ? _CountBadge(sessions) : null,
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: NavTile(
              icon: Icons.settings_outlined,
              label: context.tr('nav.settings'),
              height: 48,
              selected: nav.page == AppPage.settings,
              onTap: () => nav.go(AppPage.settings),
            ),
          ),
          const SizedBox(height: 8),
          const _SyncStatus(),
        ],
      ),
    );
  }
}

/// 品牌标识
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 16, 22),
      child: Row(
        children: [
          // 品牌图片与平台应用图标共享母版，旁边已有品牌文本，无需重复朗读。
          Image.asset(
            'assets/branding/app_icon.png',
            width: 30,
            height: 30,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 12),
          // 系统字体和缩放可能使品牌文字变宽，在剩余宽度内按需缩小。
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Remlark',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数量徽标
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: p.accentFill, borderRadius: BorderRadius.circular(10)),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.onAccent),
      ),
    );
  }
}

/// 同步状态：已同步 / 同步中 / 失败 / 未启用。点击立即同步；未配置时跳到同步设置
class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  Future<void> _onTap(BuildContext context, SyncService sync) async {
    if (!sync.config.isConfigured) {
      context.read<NavController>().goSettings(SettingsSection.sync);
      return;
    }
    if (sync.syncing) return;
    final tr = S.of(context);
    try {
      final r = await sync.syncNow();
      UiUtils.toast(tr.t('sync.done', {'pushed': r.pushed, 'pulled': r.pulled}));
    } catch (e) {
      UiUtils.toast(tr.t(sync.lastError ?? '$e'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sync = context.watch<SyncService>();
    final last = sync.config.lastSyncAt;
    final lastText = last == null
        ? context.tr('sync.never')
        : context.tr('sync.last', {'time': FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(last))});
    final (Widget icon, String title, String sub) = !sync.config.isConfigured
        ? (
            Icon(Icons.cloud_off_outlined, size: 20, color: p.textFaint),
            context.tr('sync.off'),
            context.tr('sync.off.hint'),
          )
        : sync.syncing
        ? (
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
            context.tr('sync.syncing'),
            lastText,
          )
        : sync.lastError != null
        ? (Icon(Icons.error_rounded, size: 20, color: p.danger), context.tr('sync.failed'), context.tr(sync.lastError!))
        : (Icon(Icons.check_circle_rounded, size: 20, color: p.success), context.tr('sync.state.synced'), lastText);
    return Tooltip(
      message: sync.config.isConfigured ? context.tr('sync.now') : context.tr('sync.off.hint'),
      child: InkWell(
        onTap: () => _onTap(context, sync),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 18),
          child: Row(
            children: [
              SizedBox(width: 22, child: Center(child: icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, color: p.text, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: p.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

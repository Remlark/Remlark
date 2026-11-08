// README 界面图：设置环境变量 README_SHOTS=1 时，用模拟数据渲染中英文界面图到 docs/images/<语言>/
// 用法：make readme-shots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:remlark/app/app.dart';
import 'package:remlark/app/app_services.dart';
import 'package:remlark/app/nav_controller.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_config.dart';
import 'package:remlark/modules/ai/chat_controller.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/ssh/ui/ssh_dialogs.dart';
import 'package:remlark/modules/terminal/terminal_session.dart';
import 'package:remlark/modules/terminal/ui/terminal_tab_view.dart';
import 'package:remlark/modules/workspace/workspace_tab.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';
import 'package:remlark/utils/ui_utils.dart';

import 'helpers/test_fonts.dart';

/// 单个语言的模拟文案：分组名、AI 对话内容
class _Copy {
  const _Copy({
    required this.groups,
    required this.askDisk,
    required this.diskIntro,
    required this.diskAnswer,
    required this.askNginx,
    required this.nginxIntro,
  });

  final List<String> groups;
  final String askDisk;
  final String diskIntro;
  final String diskAnswer;
  final String askNginx;
  final String nginxIntro;
}

const _copies = {
  'en': _Copy(
    groups: ['Production', 'Staging', 'Office'],
    askDisk: 'How much disk space is left on this server?',
    diskIntro: 'Check the size and usage of each mounted filesystem.',
    diskAnswer:
        'The root volume **/dev/vda1** is **99G** in total: 41G used (44%), 54G free. '
        'The data volume **/dev/vdb1** is at 71%, worth keeping an eye on.',
    askNginx: 'Restart nginx please',
    nginxIntro: 'Restart the nginx service and show its status.',
  ),
  'zh': _Copy(
    groups: ['生产环境', '测试环境', '办公网络'],
    askDisk: '帮我看下这台服务器硬盘还剩多少',
    diskIntro: '查看各分区的容量与使用情况',
    diskAnswer: '系统盘 **/dev/vda1** 共 **99G**，已用 41G（44%），剩余 54G；数据盘 **/dev/vdb1** 已用 71%，建议关注。',
    askNginx: '把 nginx 重启一下',
    nginxIntro: '重启 nginx 服务并查看状态',
  ),
};

/// 模拟主机：名称、系统、系统名称、协议、分组下标、地址、额外协议、最近连接（小时前）
const _hosts = [
  ('web-01', 'ubuntu', 'Ubuntu 24.04.1 LTS', HostProtocol.ssh, 0, '10.0.1.11', false, 1),
  ('web-02', 'ubuntu', 'Ubuntu 24.04.1 LTS', HostProtocol.ssh, 0, '10.0.1.12', false, 5),
  ('db-master', 'rhel', 'Red Hat Enterprise Linux 9.4', HostProtocol.ssh, 0, '10.0.2.10', false, 2),
  ('k8s-node-1', 'rocky', 'Rocky Linux 9.4', HostProtocol.ssh, 0, '10.0.3.21', false, 26),
  ('bastion', 'debian', 'Debian GNU/Linux 12', HostProtocol.ssh, 0, '203.0.113.8', false, 0),
  ('ci-runner', 'fedora', 'Fedora Linux 41', HostProtocol.ssh, 1, '10.1.0.30', false, 50),
  ('staging-app', 'alpine', 'Alpine Linux 3.20', HostProtocol.ssh, 1, '10.1.0.12', false, null),
  ('win-build', null, null, HostProtocol.rdp, 1, '10.1.0.40', true, 3),
  ('design-mac', 'macos', 'macOS 15.1', HostProtocol.vnc, 2, '192.168.1.20', true, 30),
];

/// ANSI 颜色与清屏序列（清屏并回到左上角，去掉之前其他尺寸下写入的内容）
const _g = '\x1b[1;32m', _b = '\x1b[1;34m', _y = '\x1b[33m', _gr = '\x1b[32m', _r = '\x1b[0m';
const _clear = '\x1b[2J\x1b[3J\x1b[H';

/// 带颜色的 shell 提示符
String _prompt(String host) => '${_g}root@$host$_r:$_b~$_r# ';

/// 把多行文本转为终端输出（换行使用 \r\n）
String _lines(List<String> lines) => lines.map((l) => '$l\r\n').join();

/// 单窗口终端（AI 助手旁，约 93×44）中 bastion 的模拟输出，每行不超过 90 列
String _terminalText() {
  final p = _prompt('bastion');
  return _clear +
      _lines([
        'Linux bastion 6.1.0-26-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.112-1 x86_64',
        'Last login: Fri Nov  8 13:52:41 2026 from 198.51.100.24',
        '${p}uptime',
        ' 14:28:17 up 23 days,  4:12,  2 users,  load average: 0.08, 0.11, 0.09',
        '${p}df -h',
        'Filesystem      Size  Used Avail Use% Mounted on',
        'udev            3.9G     0  3.9G   0% /dev',
        'tmpfs           795M  1.1M  794M   1% /run',
        '/dev/vda1        99G   41G   54G  44% /',
        '/dev/vdb1       500G  355G  145G  71% /data',
        'tmpfs           3.9G     0  3.9G   0% /dev/shm',
        '${p}systemctl restart nginx && systemctl status nginx',
        '$_gr●$_r nginx.service - A high performance web server and a reverse proxy server',
        '     Loaded: loaded (/lib/systemd/system/nginx.service; enabled; preset: enabled)',
        '     Active: ${_gr}active (running)$_r since Fri 2026-11-08 14:28:31 CST; 2s ago',
        '       Docs: man:nginx(8)',
        '   Main PID: 48213 (nginx)',
        '      Tasks: 5 (limit: 9387)',
        '     Memory: 6.4M',
        '        CPU: 41ms',
        '     CGroup: /system.slice/nginx.service',
        '             ├─48213 "nginx: master process /usr/sbin/nginx -g daemon on;"',
        '             ├─48214 "nginx: worker process"',
        '             └─48217 "nginx: worker process"',
        '',
        'Nov 08 14:28:31 bastion systemd[1]: Starting nginx.service - A high performance web...',
        'Nov 08 14:28:31 bastion systemd[1]: Started nginx.service - A high performance web s...',
      ]) +
      p;
}

/// 网格窗格（约 69×21）中每台主机的模拟输出：每行不超过 64 列，
/// 最后一条为广播输入的同一命令
String _gridText(String name) {
  final p = _prompt(name);
  final body = switch (name) {
    'bastion' => [
        '${p}who',
        'root     pts/0        2026-11-08 13:52 (198.51.100.24)',
        'deploy   pts/1        2026-11-08 14:02 (198.51.100.31)',
        '${p}ss -tln',
        'State   Recv-Q  Send-Q   Local Address:Port   Peer Address:Port',
        'LISTEN  0       511            0.0.0.0:80          0.0.0.0:*',
        'LISTEN  0       511            0.0.0.0:443         0.0.0.0:*',
        'LISTEN  0       128            0.0.0.0:22          0.0.0.0:*',
        '${p}ls /etc/nginx/sites-enabled',
        'api.conf  default  shop.conf  status.conf',
      ],
    'web-01' => [
        '${p}docker ps --format "{{.Names}}\\t{{.Status}}"',
        'api-gateway     Up 6 days (${_gr}healthy$_r)',
        'web-frontend    Up 6 days (${_gr}healthy$_r)',
        'worker          Up 6 days',
        'redis           Up 12 days',
        '${p}curl -sI localhost | head -3',
        'HTTP/1.1 200 OK',
        'Server: nginx/1.26.2',
        'Date: Fri, 08 Nov 2026 06:28:17 GMT',
        '${p}df -h /',
        'Filesystem      Size  Used Avail Use% Mounted on',
        '/dev/vda1        79G   23G   53G  31% /',
      ],
    'db-master' => [
        '${p}systemctl is-active postgresql',
        '${_gr}active$_r',
        '${p}psql -U app -Atc "select count(*) from orders"',
        '1284213',
        '${p}du -sh /var/lib/pgsql/16/data',
        '182G    /var/lib/pgsql/16/data',
        '${p}ls /var/lib/pgsql/16/backups | tail -3',
        'base-20261106.tar.zst',
        'base-20261107.tar.zst',
        'base-20261108.tar.zst',
      ],
    _ => [
        '${p}kubectl get nodes',
        'NAME         STATUS   ROLES           AGE   VERSION',
        'k8s-node-1   Ready    control-plane   92d   v1.31.2',
        'k8s-node-2   Ready    <none>          92d   v1.31.2',
        'k8s-node-3   Ready    <none>          41d   v1.31.2',
        '${p}kubectl get pods -n shop',
        'NAME                       READY   STATUS    AGE',
        'cart-6d9f7c8b5-2xkqp       1/1     ${_gr}Running$_r   3d',
        'checkout-5b7c9d4f8-r7m2t   1/1     ${_gr}Running$_r   3d',
        'search-7f8b6c5d9-p4hzl     0/1     ${_y}Pending$_r   12s',
      ],
  };
  final uptime = {
    'bastion': 'up 23 days, 4 hours, 12 minutes',
    'web-01': 'up 12 days, 2 hours, 41 minutes',
    'db-master': 'up 41 days, 7 hours, 2 minutes',
  }[name] ?? 'up 9 days, 22 hours, 15 minutes';
  return _clear + _lines([...body, '${p}uptime -p', uptime]) + p;
}

/// 截取整个应用画面写入 PNG
Future<void> _shot(WidgetTester tester, String dir, String name) async {
  // 不用 pumpAndSettle：光标闪烁等动画不会结束
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: tester.view.devicePixelRatio));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// 在内存数据库中写入模拟主机、分组与 Agent
Future<AppServices> _services(String lang) async {
  final copy = _copies[lang]!;
  SecretStore.initForTest(CryptoUtils.randomBytes(32));
  final services = AppServices(AppDatabase(NativeDatabase.memory()));
  await services.init(installKeySnippetName: lang == 'zh' ? '系统免密登录' : 'Install SSH key');
  await services.settings.setLocale(Locale(lang));
  final groups = [for (final n in copy.groups) await services.groupRepo.ensureByName(n)];
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final (i, (name, os, osName, proto, group, address, multi, hoursAgo)) in _hosts.indexed) {
    await services.hostRepo.save(
      HostEntry(
        uuid: 'host-$i',
        protocol: proto,
        name: name,
        groupUuid: groups[group].uuid,
        address: address,
        port: proto.defaultPort,
        username: proto == HostProtocol.rdp ? 'Administrator' : (os == 'macos' ? 'designer' : 'root'),
        // 桌面主机同时开启 SSH，卡片上显示多个连接入口
        extra: multi
            ? {
                'ssh': {'enabled': true, 'port': 22},
              }
            : const {},
        osId: os,
        osName: osName,
        syncEnabled: i < 5,
        syncedAt: i < 4 ? now : null,
        jumpChain: name == 'db-master' ? ['host-4'] : const [],
        updatedAt: now,
        createdAt: now,
        lastConnectedAt: hoursAgo == null ? null : now - hoursAgo * 3600000 - 120000,
      ),
      touch: false,
    );
  }
  await services.agents.save(
    const AgentSettings(uuid: 'a1', name: 'Ollama', kind: AgentKind.openaiApi, model: 'qwen3:32b', isActive: true, createdAt: 0),
  );
  await services.hosts.load();
  return services;
}

/// 渲染一种语言的全部 README 界面图
Future<void> _render(WidgetTester tester, String lang, String outRoot) async {
  final copy = _copies[lang]!;
  final dir = '$outRoot/$lang';
  Directory(dir).createSync(recursive: true);
  tester.view.physicalSize = const Size(2880, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final services = (await tester.runAsync(() => _services(lang)))!;
  await tester.pumpWidget(RepaintBoundary(child: RemlarkApp(services: services)));
  NavController nav() => UiUtils.navigatorKey.currentContext!.read<NavController>();

  // 1. 主机列表（深色）
  await tester.runAsync(() => services.settings.setThemeMode(ThemeMode.dark));
  nav().go(AppPage.hosts);
  await _shot(tester, dir, 'hosts');

  // 2. 工作区开始页：最近连接（浅色）
  await tester.runAsync(() => services.settings.setThemeMode(ThemeMode.light));
  nav().go(AppPage.sessions);
  await _shot(tester, dir, 'workspace');
  await tester.runAsync(() => services.settings.setThemeMode(ThemeMode.dark));

  // 3. 终端 + AI 助手：打开多个终端（不实际连接），写入模拟输出
  final dialogs = DialogInteraction();
  final byName = {for (final h in services.hosts.all) h.name: h};
  final sessions = <TerminalSession>[];
  for (final name in ['bastion', 'web-01', 'db-master', 'k8s-node-1']) {
    final t = TerminalSession(byName[name]!, services.connector, dialogs);
    t.setState(SessionState.connected);
    services.workspace.add(t);
    sessions.add(t);
  }
  final first = sessions.first;
  first.uiState['panel'] = SidePanel.ai;
  services.workspace.activate(first.id);
  nav().go(AppPage.sessions);
  await _shot(tester, dir, '_warmup');
  // 等 AI 面板展开、终端尺寸确定后再写入输出，避免按其他宽度折行
  first.terminal.write(_terminalText());
  final chat = first.uiState['chat'] as ChatController;
  chat.messages.addAll([
    UiChatMessage('user', copy.askDisk),
    UiChatMessage('assistant', '${copy.diskIntro}\n\n```bash\ndf -h\n```'),
    UiChatMessage(
      'terminal',
      'root@bastion:~# df -h\nFilesystem      Size  Used Avail Use% Mounted on\n/dev/vda1        99G   41G   54G  44% /\n'
          '/dev/vdb1       500G  355G  145G  71% /data\nroot@bastion:~# ',
    ),
    UiChatMessage('assistant', copy.diskAnswer),
    UiChatMessage('user', copy.askNginx),
    UiChatMessage('assistant', '${copy.nginxIntro}\n\n```bash\nsystemctl restart nginx && systemctl status nginx\n```'),
  ]);
  chat.notifyListeners();
  await _shot(tester, dir, 'terminal-ai');
  File('$dir/_warmup.png').deleteSync();

  // 4. 网格布局 + 广播输入：等网格完成布局（终端已缩小）后再写入输出
  first.uiState['panel'] = SidePanel.none;
  services.workspace.showGrid([for (final s in sessions) s.id]);
  services.workspace.startBroadcast(ids: [for (final s in sessions) s.id]);
  await tester.pump(const Duration(milliseconds: 200));
  for (final s in sessions) {
    s.terminal.write(_gridText(s.host.name));
  }
  await _shot(tester, dir, 'broadcast');
  services.workspace.stopBroadcast();

  await services.workspace.closeAll();
  services.updates.dispose();
}

void main() {
  final enabled = Platform.environment['README_SHOTS'] == '1';
  const outRoot = 'docs/images';
  for (final lang in _copies.keys) {
    testWidgets('README 界面图（$lang）', (tester) async {
      if (!enabled) return;
      await tester.runAsync(() => loadTestFonts(realMonospace: true));
      // 按 macOS 界面渲染（终端使用 Menlo 字体族、快捷键显示为 ⌘），测试结束前必须恢复
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _render(tester, lang, outRoot);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

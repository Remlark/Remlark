import '../data/database.dart';
import '../utils/app_log.dart';
import '../modules/ai/agent_options_controller.dart';
import '../modules/ai/agent_repository.dart';
import '../modules/ai/agents_controller.dart';
import '../modules/ai/chat_repository.dart';
import '../modules/ai/agent_config.dart';
import '../modules/ai/codex/codex_app_server.dart';
import '../modules/ai/codex/codex_runtime_controller.dart';
import '../modules/ai/dsh/dsh_acp_service.dart';
import '../modules/ai/dsh/dsh_runtime_controller.dart';
import '../modules/ai/runtime/agent_runtime.dart';
import '../modules/ai/token_repository.dart';
import '../modules/hosts/group_repository.dart';
import '../modules/hosts/host_repository.dart';
import '../modules/hosts/hosts_controller.dart';
import '../modules/import_export/import_export_service.dart';
import '../modules/keys/key_repository.dart';
import '../modules/settings/settings_controller.dart';
import '../modules/settings/settings_repository.dart';
import '../modules/snippets/snippet_repository.dart';
import '../modules/ssh/ssh_connector.dart';
import '../modules/sync/sync_service.dart';
import '../modules/workspace/workspace_controller.dart';

/// 应用依赖容器：集中创建仓库、服务与控制器，通过 Provider 注入 UI
class AppServices {
  AppServices(this.db)
    : settingsRepo = SettingsRepository(db),
      hostRepo = HostRepository(db),
      groupRepo = GroupRepository(db),
      keyRepo = KeyRepository(db),
      snippetRepo = SnippetRepository(db),
      agentRepo = AgentRepository(db),
      chatRepo = ChatRepository(db),
      tokenRepo = TokenRepository(db) {
    settings = SettingsController(settingsRepo);
    hosts = HostsController(hostRepo, groupRepo);
    connector = SshConnector(hostRepo, keyRepo);
    sync = SyncService(settingsRepo, hostRepo, groupRepo, keyRepo)..onHostsChanged = hosts.load;
    agents = AgentsController(agentRepo);
    dsh = DshRuntimeController();
    codex = CodexRuntimeController();
    runtimes = AgentRuntimes({AgentKind.deepseekCli: dsh, AgentKind.codex: codex});
    agentOptions = AgentOptionsController(runtimes);
    workspace = WorkspaceController();
    importExport = ImportExportService(hostRepo, groupRepo, keyRepo, snippetRepo);
  }

  final AppDatabase db;
  final SettingsRepository settingsRepo;
  final HostRepository hostRepo;
  final GroupRepository groupRepo;
  final KeyRepository keyRepo;
  final SnippetRepository snippetRepo;
  final AgentRepository agentRepo;
  final ChatRepository chatRepo;
  final TokenRepository tokenRepo;

  late final SettingsController settings;
  late final HostsController hosts;
  late final SshConnector connector;
  late final SyncService sync;
  late final AgentsController agents;
  late final DshRuntimeController dsh;
  late final CodexRuntimeController codex;

  /// 各类 Agent 的本地运行环境（新增需要安装的 Agent 时在此注册）
  late final AgentRuntimes runtimes;

  /// 各 Agent 可选的模型与推理强度
  late final AgentOptionsController agentOptions;
  late final WorkspaceController workspace;
  late final ImportExportService importExport;

  /// 启动时加载数据
  Future<void> init({required String installKeySnippetName}) async {
    await settings.load();
    await snippetRepo.seedDefaults(installKeyName: installKeySnippetName);
    await hosts.load();
    await agents.load();
    await sync.load();
  }

  /// 退出前按顺序释放资源：断开所有会话、结束 dsh / Codex 子进程、最后关闭数据库。
  ///
  /// 必须在引擎关闭前完成：否则数据库所在的后台 isolate 被直接销毁，sqlite 语句的清理回调
  /// 在连接释放后运行，退出时崩溃（EXC_BAD_ACCESS @ sqlite3_finalize）。
  /// 每一步单独限时并忽略错误，保证退出不会卡住
  Future<void> shutdown() async {
    Future<void> step(String name, Future<void> Function() action, Duration limit) async {
      try {
        await action().timeout(limit);
      } catch (e) {
        AppLog.w('app', '退出时$name失败：$e');
      }
    }

    AppLog.i('app', '退出：释放资源');
    sync.stop();
    await step('关闭会话', workspace.closeAll, const Duration(seconds: 3));
    await step('结束 dsh', DshAcpService.shared.shutdown, const Duration(seconds: 3));
    await step('结束 Codex', CodexAppServer.shared.shutdown, const Duration(seconds: 3));
    await step('关闭数据库', db.close, const Duration(seconds: 3));
  }
}

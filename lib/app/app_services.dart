import '../data/database.dart';
import '../modules/ai/agent_repository.dart';
import '../modules/ai/agents_controller.dart';
import '../modules/ai/chat_repository.dart';
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
}

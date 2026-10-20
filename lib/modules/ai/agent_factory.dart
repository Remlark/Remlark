import 'agent_config.dart';
import 'agent_interface.dart';
import 'agents/deepseek_harness_agent.dart';
import 'agents/openai_compatible_agent.dart';

/// 根据配置创建 Agent 实例；新增 Agent 类型时在此注册
class AgentFactory {
  AgentFactory._();

  static AiAgent create(AgentSettings s) {
    switch (s.kind) {
      case AgentKind.deepseekCli:
        return DeepSeekHarnessAgent(s);
      case AgentKind.openaiApi:
        return OpenAiCompatibleAgent(s);
    }
  }
}

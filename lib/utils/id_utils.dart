import 'package:uuid/uuid.dart';

/// 唯一 ID 工具
class IdUtils {
  IdUtils._();

  static const Uuid _uuid = Uuid();

  /// 生成 v4 uuid，用于主机、分组、快捷指令等实体的全局唯一标识（同步依据）
  static String newId() => _uuid.v4();
}

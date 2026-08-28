import 'package:drawing_notes_app/features/drawing/domain/page_connector.dart';

/// 连线创建所需的最小端点输入。
class EditorLinkMutation {
  const EditorLinkMutation._();

  /// 为两个不同的画布对象创建连接；相同端点不产生连接。
  static PageConnector? createConnector({
    required String? sourceId,
    required String targetId,
    required String connectorId,
  }) {
    if (sourceId == null || sourceId.isEmpty || sourceId == targetId) {
      return null;
    }
    if (targetId.isEmpty || connectorId.isEmpty) return null;

    return PageConnector(
      id: connectorId,
      fromItemId: sourceId,
      toItemId: targetId,
    );
  }
}

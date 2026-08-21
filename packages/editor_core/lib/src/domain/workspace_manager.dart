// editor_core——WorkspaceManager 工作区管理（AFFiNE 借鉴——2026-08-21）。
//
// AFFiNE Workspace Management（6.2）本地化——多工作区管理。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// AFFiNE 原版参考：
// - 6.2 Workspace and Document Management
// - 多工作区（personal/team/project）+ 工作区切换 + 文档组织
library;

/// 工作区类型（AFFiNE Workspace 借鉴）。
enum WorkspaceType {
  /// 个人工作区。
  personal,

  /// 团队工作区。
  team,

  /// 项目工作区。
  project,
}

/// 工作区（AFFiNE Workspace 本地化——不可变）。
class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    this.type = WorkspaceType.personal,
    this.description = '',
    this.color = '#4A90D9',
    this.icon = '📁',
    this.documentIds = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final WorkspaceType type;
  final String description;
  final String color;
  final String icon;
  final List<String> documentIds;
  final DateTime? createdAt;

  /// 文档数量。
  int get documentCount => documentIds.length;

  /// 是否为空（无文档）。
  bool get isEmpty => documentIds.isEmpty;

  /// 添加文档。
  Workspace addDocument(String docId) {
    if (documentIds.contains(docId)) return this;
    return copyWith(documentIds: [...documentIds, docId]);
  }

  /// 移除文档。
  Workspace removeDocument(String docId) {
    return copyWith(documentIds: documentIds.where((id) => id != docId).toList());
  }

  Workspace copyWith({
    String? name,
    WorkspaceType? type,
    String? description,
    String? color,
    String? icon,
    List<String>? documentIds,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      documentIds: documentIds ?? this.documentIds,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Workspace && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 工作区管理器（AFFiNE Workspace Management 本地化——积木式纯 Dart）。
///
/// 功能：
/// - 工作区注册表（add/remove/get）
/// - 工作区切换（switchTo）
/// - 文档组织（addDocument/removeDocument）
/// - 按类型过滤（byType）
class WorkspaceManager {
  const WorkspaceManager({
    this.workspaces = const [],
    this.activeWorkspaceId = '',
  });

  final List<Workspace> workspaces;
  final String activeWorkspaceId;

  /// 当前活动工作区。
  Workspace? get activeWorkspace =>
      workspaces.where((w) => w.id == activeWorkspaceId).firstOrNull;

  /// 注册工作区。
  WorkspaceManager add(Workspace workspace) {
    return WorkspaceManager(
      workspaces: [...workspaces, workspace],
      activeWorkspaceId: activeWorkspaceId.isEmpty ? workspace.id : activeWorkspaceId,
    );
  }

  /// 移除工作区。
  WorkspaceManager remove(String workspaceId) {
    final remaining = workspaces.where((w) => w.id != workspaceId).toList();
    final newActive = activeWorkspaceId == workspaceId
        ? (remaining.isNotEmpty ? remaining.first.id : '')
        : activeWorkspaceId;
    return WorkspaceManager(workspaces: remaining, activeWorkspaceId: newActive);
  }

  /// 获取工作区。
  Workspace? get(String workspaceId) {
    return workspaces.where((w) => w.id == workspaceId).firstOrNull;
  }

  /// 切换工作区（AFFiNE switchWorkspace）。
  WorkspaceManager switchTo(String workspaceId) {
    if (!workspaces.any((w) => w.id == workspaceId)) return this;
    return WorkspaceManager(workspaces: workspaces, activeWorkspaceId: workspaceId);
  }

  /// 更新工作区。
  WorkspaceManager update(Workspace workspace) {
    return WorkspaceManager(
      workspaces: workspaces.map((w) => w.id == workspace.id ? workspace : w).toList(),
      activeWorkspaceId: activeWorkspaceId,
    );
  }

  /// 在活动工作区添加文档。
  WorkspaceManager addDocumentToActive(String docId) {
    if (activeWorkspace == null) return this;
    return update(activeWorkspace!.addDocument(docId));
  }

  /// 在活动工作区移除文档。
  WorkspaceManager removeDocumentFromActive(String docId) {
    if (activeWorkspace == null) return this;
    return update(activeWorkspace!.removeDocument(docId));
  }

  /// 按类型过滤（AFFiNE getWorkspacesByType）。
  List<Workspace> byType(WorkspaceType type) {
    return workspaces.where((w) => w.type == type).toList();
  }

  int get count => workspaces.length;
  bool get isEmpty => workspaces.isEmpty;

  WorkspaceManager copyWith({List<Workspace>? workspaces, String? activeWorkspaceId}) {
    return WorkspaceManager(
      workspaces: workspaces ?? this.workspaces,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WorkspaceManager && count == other.count;

  @override
  int get hashCode => count.hashCode;
}

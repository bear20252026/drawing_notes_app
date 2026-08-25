import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——WorkspaceManager 工作区管理测试（纯逻辑——不搞崩）。
void main() {
  test('Workspace：默认值 + documentCount + isEmpty', () {
    const ws = Workspace(id: 'ws1', name: 'Personal');
    expect(ws.type, WorkspaceType.personal);
    expect(ws.documentCount, 0);
    expect(ws.isEmpty, true);
  });

  test('Workspace：addDocument/removeDocument 不可变', () {
    const ws = Workspace(id: 'ws1', name: 'Personal');
    final withDoc = ws.addDocument('doc1');
    expect(withDoc.documentCount, 1);
    expect(withDoc.documentIds, contains('doc1'));
    // 原实例不变。
    expect(ws.documentCount, 0);
    // 不重复添加。
    final again = withDoc.addDocument('doc1');
    expect(again.documentCount, 1);
    // 移除。
    final removed = withDoc.removeDocument('doc1');
    expect(removed.documentCount, 0);
  });

  test('Workspace：copyWith 不可变', () {
    const ws = Workspace(id: 'ws1', name: 'Personal');
    final renamed = ws.copyWith(name: 'New Name', color: '#FF0000');
    expect(ws.name, 'Personal'); // 原实例不变。
    expect(renamed.name, 'New Name');
    expect(renamed.color, '#FF0000');
  });

  test('WorkspaceManager：add/remove/get', () {
    const manager = WorkspaceManager();
    final withWs = manager.add(const Workspace(id: 'ws1', name: 'Personal'));
    expect(withWs.count, 1);
    expect(withWs.activeWorkspaceId, 'ws1'); // 自动激活。
    final removed = withWs.remove('ws1');
    expect(removed.count, 0);
    expect(removed.activeWorkspaceId, ''); // 清空激活。
  });

  test('WorkspaceManager：switchTo 切换工作区', () {
    final manager = WorkspaceManager().add(
      const Workspace(id: 'ws1', name: 'Personal'),
    ).add(
      const Workspace(id: 'ws2', name: 'Team'),
    );
    expect(manager.activeWorkspaceId, 'ws1');
    final switched = manager.switchTo('ws2');
    expect(switched.activeWorkspaceId, 'ws2');
    expect(switched.activeWorkspace!.name, 'Team');
  });

  test('WorkspaceManager：addDocumentToActive / removeDocumentFromActive', () {
    final manager = WorkspaceManager().add(
      const Workspace(id: 'ws1', name: 'Personal'),
    );
    final withDoc = manager.addDocumentToActive('doc1');
    expect(withDoc.activeWorkspace!.documentCount, 1);
    final without = withDoc.removeDocumentFromActive('doc1');
    expect(without.activeWorkspace!.documentCount, 0);
  });

  test('WorkspaceManager：byType 按类型过滤', () {
    final manager = WorkspaceManager().add(
      const Workspace(id: 'ws1', name: 'Personal', type: WorkspaceType.personal),
    ).add(
      const Workspace(id: 'ws2', name: 'Team', type: WorkspaceType.team),
    ).add(
      const Workspace(id: 'ws3', name: 'Project', type: WorkspaceType.project),
    );
    expect(manager.byType(WorkspaceType.personal).length, 1);
    expect(manager.byType(WorkspaceType.team).length, 1);
  });

  test('WorkspaceManager：remove 自动切换活动工作区', () {
    final manager = WorkspaceManager().add(
      const Workspace(id: 'ws1', name: 'Personal'),
    ).add(
      const Workspace(id: 'ws2', name: 'Team'),
    );
    expect(manager.activeWorkspaceId, 'ws1');
    final removed = manager.remove('ws1');
    expect(removed.activeWorkspaceId, 'ws2'); // 自动切换到下一个。
  });

  test('WorkspaceType 枚举', () {
    expect(WorkspaceType.values.length, 3);
  });
}

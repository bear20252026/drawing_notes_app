part of 'home_page.dart';

// 首页 Tab 布局域（行数门禁拆分）：_buildBody / 三个 Tab / 打开笔记本等。
// 从 home_page.dart 移出为 extension（行为零变化），保持主文件 < 500 逻辑行。

extension _HomePageTabs on _HomePageState {
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    return TabBarView(children: [_buildDrawingsTab()]);
  }

  // ---------------- 画作 Tab ----------------

  Widget _buildDrawingsTab() {
    if (_documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有无限画布，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          12,
          AppDesign.pagePadding,
          96,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 256,
          childAspectRatio: 0.82,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _documents.length,
        itemBuilder: (context, i) => _DrawingCard(
          meta: _documents[i],
          documentStorage: _docStorage,
          onTap: () => _openDrawing(_documents[i]),
          onDelete: () => _deleteDrawing(_documents[i]),
        ),
      ),
    );
  }
}

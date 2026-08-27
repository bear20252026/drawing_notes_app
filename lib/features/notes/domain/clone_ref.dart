/// 跨笔记本共享页面的定位引用。
///
/// [notebookId] 与 [pageId] 指向源页面；克隆条目本身不存内容，加载和写回
/// 仍由基础设施与页面协调逻辑负责。
class CloneRef {
  const CloneRef({required this.notebookId, required this.pageId});

  final String notebookId;
  final String pageId;

  Map<String, dynamic> toJson() => {'notebookId': notebookId, 'pageId': pageId};

  factory CloneRef.fromJson(Map<String, dynamic> json) => CloneRef(
    notebookId: json['notebookId'] as String,
    pageId: json['pageId'] as String,
  );
}

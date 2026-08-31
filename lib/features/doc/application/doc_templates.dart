// 由 Claude 团队生成 | Drawing Notes App
// 笔记模板库（M12.6，AFFiNE Templates 对齐）。
// 纯 Dart 构建器：返回模板化 body 块列表，供「新建笔记」选择。
// 模板是数据（非代码生成物），后续扩充只需加枚举项 + builder 分支。

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';

/// 内置笔记模板。
///
/// 注意：application 层不依赖 flutter/material——图标由展示层按枚举映射。
enum DocTemplate {
  blank('空白笔记', '从零开始'),
  meeting('会议纪要', '议题 · 决议 · 行动项'),
  daily('每日日志', '今日完成 · 明日计划'),
  todoList('待办清单', '预置待办块');

  const DocTemplate(this.label, this.description);

  final String label;
  final String description;
}

/// 按模板生成 body 块（id 由调用方注入器生成，保持块 id 风格统一）。
List<NoteBlock> buildTemplateBody(
  DocTemplate template,
  String Function() nextId,
) {
  switch (template) {
    case DocTemplate.blank:
      return [NoteBlock.textBlock(nextId(), text: '')];
    case DocTemplate.meeting:
      return [
        NoteBlock.headingBlock(nextId(), level: 2, text: '会议信息'),
        NoteBlock.textBlock(nextId(), text: '时间：\n参会人：'),
        NoteBlock.headingBlock(nextId(), level: 2, text: '议题'),
        NoteBlock.bulletBlock(nextId(), text: ''),
        NoteBlock.headingBlock(nextId(), level: 2, text: '决议'),
        NoteBlock.bulletBlock(nextId(), text: ''),
        NoteBlock.headingBlock(nextId(), level: 2, text: '行动项'),
        NoteBlock.todoBlock(nextId(), text: ''),
        NoteBlock.todoBlock(nextId(), text: ''),
      ];
    case DocTemplate.daily:
      return [
        NoteBlock.headingBlock(nextId(), level: 2, text: '今日完成'),
        NoteBlock.todoBlock(nextId(), text: ''),
        NoteBlock.headingBlock(nextId(), level: 2, text: '明日计划'),
        NoteBlock.todoBlock(nextId(), text: ''),
        NoteBlock.headingBlock(nextId(), level: 2, text: '记录'),
        NoteBlock.textBlock(nextId(), text: ''),
      ];
    case DocTemplate.todoList:
      return [
        NoteBlock.headingBlock(nextId(), level: 2, text: '待办'),
        NoteBlock.todoBlock(nextId(), text: ''),
        NoteBlock.todoBlock(nextId(), text: ''),
        NoteBlock.todoBlock(nextId(), text: ''),
      ];
  }
}

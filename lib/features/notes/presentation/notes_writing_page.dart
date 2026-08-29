import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 纯笔记页（导航目的地 4）：直接打字的笔记页面。
///
/// 设计说明：
/// - 当前为占位骨架；
/// - 后续在此接入富文本 / 块式笔记编辑（对齐 AFFiNE 的「文档 = 笔记」模型）。
class NotesWritingPage extends StatelessWidget {
  const NotesWritingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppleSpacing.md),
        children: [
          const SizedBox(height: AppleSpacing.md),
          // 分组头：Apple 灰字 + 字距
          const AppleSectionHeader(label: '最近'),
          const SizedBox(height: AppleSpacing.sm),
          // 空态
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppleSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_note_outlined,
                    size: 64,
                    color: AppleColor.inkSubtle,
                  ),
                  const SizedBox(height: AppleSpacing.sm),
                  Text(
                    '纯笔记（待完善）',
                    style: AppleType.bodyStyle(AppleColor.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

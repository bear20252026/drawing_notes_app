# 笔记编辑实现分析（AFFiNE BlockSuite / Saber 校验——2026-08-22）

> 用户需求：笔记区域就是一个笔记——像 Word 文档一样可以直接打字。
> 校验 Saber/AFFiNE 怎么使用笔记功能——本地化方案。

## 一、校验结论（两个项目怎么做笔记）

| 项目 | 笔记实现 | 是否符合"Word 文档直接打字" |
|------|---------|---------------------------|
| **AFFiNE Page Mode** | **块编辑器**（BlockSuite——直接打字——Paragraph/Headings/List/Quote/Code/LaTeX/Table 块 + 富文本 + Markdown 快捷 + Slash 命令） | ✅ **符合**——Word 文档式（直接打字 + 块组织） |
| **Saber** | 手写笔记为主（画布式手写笔——文本为辅） | ⚠️ 手写为主——非打字文档（笔记组织文件树可借鉴） |

**结论**：我们的**笔记本 = AFFiNE Page Mode 式文档编辑器**（Word 文档——直接打字——块组织）——画布保留 whiteboard（无限画布——手写/绘图）。

## 二、AFFiNE 笔记编辑器核心（本地化借鉴）

| AFFiNE 功能 | 说明 | 本地化（我们的 note 模式） |
|------------|------|--------------------------|
| **块类型** | Paragraph/Headings H1-H6/List（bullet/numbered/todo）/Quote/Code/LaTeX/Table/Divider | RichTextBlock（已搬——块模型）+ NoteEditorWidget（段落/标题/列表） |
| **富文本** | Bold/Italic/Underline/Strikethrough/Inline code/Text colors | TextSpan 格式（RichTextBlock 支持） |
| **Markdown 快捷** | # 标题/- 列表/[] todo/> 引用/``` 代码 | 输入快捷转换（后续） |
| **Slash 命令**（/ 键） | 双栏菜单——插入块 | 后续（块菜单） |
| **直接打字** | 光标编辑——Word 式 | TextEditingController + 段落列表（Word 式） |

## 三、本地化实施（note 模式 = Word 文档编辑器）

```
┌─────────────────────────────────────────────┐
│  NoteEditorWidget（Word 文档式——直接打字）    │
│  ├── 段落列表（RichTextBlock[]——可编辑）     │
│  ├── TextEditingController（直接打字——Word 式）│
│  ├── 格式工具栏（加粗/标题/列表——后续）       │
│  └── 共用核心（保存/加密/导出——DocumentV2）   │
└─────────────────────────────────────────────┘
note 模式（笔记本）：NoteEditorWidget（打字文档——Word 式）
whiteboard 模式（画布）：InfiniteCanvasWidget（无限画布——手写绘图）
（同一编辑器——共用核心——功能共通——不重复显示）
```

## 四、版权说明

- AFFiNE（BSL 1.1/MIT）——块编辑器概念借鉴——NOTICE 已记录
- Saber（GPL-3.0）——手写笔记——文件树组织——NOTICE 已记录

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)

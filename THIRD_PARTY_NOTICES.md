# 第三方组件与致谢（Third-Party Notices）

本项目的笔记/白板交互设计参照并部分复用以下开源项目的成果。感谢原作者。

## AFFiNE / BlockSuite

- 项目：<https://github.com/toeverything/AFFiNE>
- 版权所有 (c) 2020-present toeverything 及其贡献者
- 许可证：MIT（BlockSuite 及 AFFiNE 仓库声明部分）
- 使用方式：本应用的块编辑器交互（块模型、斜杠菜单、块句柄拖拽、
  浮动格式工具条、Page/Edgeless 双模、大纲等）参照 AFFiNE/BlockSuite
  的交互与信息架构实现；数据结构命名（如 `affine:connector`、
  `affine:group`）为对标说明而保留。
- 响应式布局（2026-08-31 追加）：移动端视图参照 AFFiNE
  `packages/frontend/core/src/mobile/` 的信息架构——设备级分流、桌面与
  移动端两棵独立视图树、侧栏功能拆进顶部 header（Tab/搜索/排序/更多菜单）、
  底部导航在输入法弹出时隐藏（VirtualKeyboardService 语义）。相关实现见
  `lib/features/all_docs/presentation/all_docs_page_mobile.dart` 与
  `lib/app/app_shell.dart`。

MIT 许可证文本（摘自 AFFiNE 仓库）：

```text
MIT License

Copyright (c) 2020-present toeverything

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 其他依赖

其余第三方依赖及其许可证见 `pubspec.yaml` 与 `pubspec.lock`
（Flutter/Dart 生态，多为 MIT/BSD/Apache-2.0）。

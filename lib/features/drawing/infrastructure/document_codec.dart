// 兼容导出：绘图工程 JSON 编解码现在由核心存储层拥有。
//
// 保留此路径以避免既有 feature 内调用方和测试因模块所有权迁移而中断；
// DocumentCodec 的实现、公共 API 和序列化格式均位于 core/storage。
export 'package:drawing_notes_app/core/storage/document_codec.dart';

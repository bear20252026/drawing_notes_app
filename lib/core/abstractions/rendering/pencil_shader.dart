// core/abstractions — 铅笔着色器抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:ui';

/// 铅笔着色器抽象接口
///
/// 提供铅笔纹理效果
abstract class PencilShader {
  /// 获取铅笔纹理着色器
  Shader createShader(Rect bounds);

  /// 更新着色器参数
  void updateParameters(Map<String, dynamic> params);
}

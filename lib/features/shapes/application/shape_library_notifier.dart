// shapes — Application 层：形状库状态管理
// 遵循 Clean Architecture：Application 层只依赖 Domain 层

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/shape_repository.dart';
import '../domain/shape_template.dart';
import '../infrastructure/local_shape_repository.dart';

/// 形状库状态管理器
///
/// 通过 [ShapeRepository] 接口存取形状模板
/// 不直接依赖任何具体存储实现
class ShapeLibraryNotifier extends AsyncNotifier<List<ShapeTemplate>> {
  late final ShapeRepository _repository;

  @override
  Future<List<ShapeTemplate>> build() async {
    _repository = ref.read(shapeRepositoryProvider);
    return _repository.listShapes();
  }

  /// 导入形状模板
  Future<void> importShape(ShapeTemplate shape) async {
    await _repository.addShape(shape);
    state = AsyncData(await _repository.listShapes());
  }

  /// 更新形状模板
  Future<void> updateShape(ShapeTemplate shape) async {
    await _repository.updateShape(shape);
    state = AsyncData(await _repository.listShapes());
  }

  /// 删除形状模板
  Future<void> deleteShape(String id) async {
    await _repository.deleteShape(id);
    state = AsyncData(await _repository.listShapes());
  }

  /// 重新加载所有形状
  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _repository.listShapes());
  }
}

/// ShapeLibraryNotifier Provider（供 Presentation 层使用）
final shapeLibraryNotifierProvider =
    AsyncNotifierProvider<ShapeLibraryNotifier, List<ShapeTemplate>>(
        ShapeLibraryNotifier.new);

/// ShapeRepository Provider（DI 入口——注入本地存储实现）
final shapeRepositoryProvider = Provider<ShapeRepository>((ref) {
  return LocalShapeRepository();
});

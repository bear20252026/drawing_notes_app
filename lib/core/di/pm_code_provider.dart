/// PM码服务依赖注入 Provider。
///
/// 注册 PM码 相关服务到 Riverpod 容器。
///
/// 版权声明：本实现借鉴了以下开源项目的设计理念：
/// - kurpod (github.com/srv1n/kurpod) — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — 项目自定义许可
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/interfaces/pm_code_service.dart';
import '../../features/security/application/pm_code_use_cases.dart';
import '../../features/security/infrastructure/pm_code_repository_impl.dart';
import '../../features/security/domain/repositories/pm_code_repository.dart';

/// PM码仓储 Provider。
final pmCodeRepositoryProvider = Provider<PmCodeRepository>((ref) {
  final PmCodeRepositoryImpl impl = PmCodeRepositoryImpl();
  return impl;
});

/// PM码服务 Provider。
///
/// 提供 PmCodeService 接口的默认实现（PmCodeUseCases）。
final pmCodeServiceProvider = Provider<PmCodeService>((ref) {
  final PmCodeRepository repository = ref.watch(pmCodeRepositoryProvider);
  return PmCodeUseCases(repository: repository);
});

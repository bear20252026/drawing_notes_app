// notes — Application 层：DI Providers（组合根）
// 遵循 Clean Architecture：在组合根处注入所有依赖

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notes_accessor.dart';
import '../../infrastructure/storage/storage_service.dart';
import '../../../core/storage/repository.dart';
import 'export_use_cases.dart';
import 'note_use_cases.dart';
import 'notebook_use_cases.dart';

/// NotebookRepository Provider（DI 入口——注入 StorageService 实现）
final notebookRepositoryProvider = Provider<NotebookRepository>((ref) {
  return StorageService();
});

/// NotebookAccessor Provider（DI 入口）
final notebookAccessorProvider = Provider<INotebookAccessor>((ref) {
  return StorageService();
});

/// NotebookUseCases Provider
final notebookUseCasesProvider = Provider<NotebookUseCases>((ref) {
  return NotebookUseCases(ref.read(notebookRepositoryProvider));
});

/// NoteUseCases Provider
final noteUseCasesProvider = Provider<NoteUseCases>((ref) {
  return NoteUseCases(ref.read(notebookRepositoryProvider));
});

/// ExportUseCases Provider
final exportUseCasesProvider = Provider<ExportUseCases>((ref) {
  return ExportUseCases(ref.read(notebookRepositoryProvider));
});

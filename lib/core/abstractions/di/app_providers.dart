// core/abstractions — DI Providers 抽象层
// 遵循 Clean Architecture：定义 Provider 抽象接口，实现由 core/di/ 提供
//
// features/ 模块应从此文件导入 Provider 类型引用，而非直接从 core/di/ 导入

// Re-export all providers from core/di/ for backward compatibility
// features/ should import from this file for type references

export '../../../infrastructure/di/providers.dart' show
    themeProvider,
    themeModeProvider,
    darkModeProvider,
    AppThemeNotifier,
    DarkModeNotifier;

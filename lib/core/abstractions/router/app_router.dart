// core/abstractions — 路由抽象层
// 遵循 Clean Architecture：定义路由路径常量和导航接口
// features/ 模块应从此文件导入路由路径，而非直接从 core/router/ 导入

/// 路由路径常量
///
/// 集中管理所有路由路径，避免硬编码
class RoutePaths {
  RoutePaths._();

  static const home = '/';
  static const editor = '/editor';
  static const editorV2 = '/editor-v2';
  static const notebook = '/notebook';
  static const passwordDisk = '/password-disk';
  static const appLock = '/app-lock';
  static const appLockSettings = '/app-lock-settings';
  static const settings = '/settings';
  static const shapes = '/shapes';
  static const search = '/search';
  static const presentation = '/presentation';
  static const onboarding = '/onboarding';
  static const pmCodeSetup = '/pm-code-setup';
  static const pmCodeInput = '/pm-code-input';
}

/// 路由名称常量
class RouteNames {
  RouteNames._();

  static const home = 'home';
  static const editor = 'editor';
  static const editorV2 = 'editor-v2';
  static const notebook = 'notebook';
  static const passwordDisk = 'password-disk';
  static const appLock = 'app-lock';
  static const appLockSettings = 'app-lock-settings';
  static const settings = 'settings';
  static const shapes = 'shapes';
  static const search = 'search';
  static const presentation = 'presentation';
  static const onboarding = 'onboarding';
  static const pmCodeSetup = 'pm-code-setup';
  static const pmCodeInput = 'pm-code-input';
}

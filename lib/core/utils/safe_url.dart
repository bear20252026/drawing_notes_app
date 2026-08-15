/// 超链接安全校验（审计修复 2026-08-15，命令注入面）。
///
/// 背景：编辑器超链接在 Windows 经 `cmd /c start` 打开，未校验的 href 可
/// 注入 cmd 元字符或 `javascript:`/`file:` 等危险 scheme。实测确认 cmd
/// 双引号内的 `&` 等元字符不会被解析，故净化策略：
/// 1. scheme 白名单（http/https/mailto）——拦截 javascript:/file:/data: 等；
/// 2. 拒绝含双引号 `"` 的输入——防止破坏 `start "" "url"` 的引号边界。
///
/// 合法 URL 的 `&`（查询参数分隔符）不会被误杀。
String? sanitizeHref(String? input) {
  final url = input?.trim() ?? '';
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') {
    return null;
  }
  if (url.contains('"')) return null;
  return url;
}

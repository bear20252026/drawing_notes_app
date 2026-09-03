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
  // P2 补强：换行/回车可截断 cmd 参数行或注入 mailto 正文（`mailto:?body=`
  // 嵌 `\n`），一律拒绝。
  if (url.contains('\n') || url.contains('\r')) return null;
  // 链 F 修复（军工审计 2026-08-15）：拒绝含 % 的 URL——Windows cmd
  // 打开链接时 %VAR% 会被展开为环境变量（双引号不阻止变量展开），
  // 攻击者可经 %PATH:~x,y% 逐字符构造任意字符突破引号边界（命令注入，
  // CVE-2024 类模式）。安全取舍：拒绝百分号编码 URL（%20 等）在画图
  // 应用超链接场景可接受。
  if (url.contains('%')) return null;
  return url;
}

/// 远端图片来源校验（P1 安全修复——`Image.network` 直通块 `props['src']`
/// 可致 SSRF/内网探测/IP 外泄/巨图 OOM）。
///
/// 比 [sanitizeHref] 更严：只允许 https（杜绝明文 http 内网探测与凭证
/// 泄露）；要求 host 非空；拒绝 userinfo（`user:pass@host`）；长度上限
/// 4096（argv/内存放大防护）。`%` 在此允许（图片签名 URL 常见；且
/// Image.network 不走 cmd，`%VAR%` 展开风险不存在）。
/// 不合法返回 null（调用方渲染占位图，不发起任何请求——fail-closed）。
String? sanitizeImageSrc(String? input) {
  final url = input?.trim() ?? '';
  if (url.isEmpty || url.length > 4096) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'https') return null;
  if (!uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (url.contains('"') || url.contains(' ') || url.contains('\n')) {
    return null;
  }
  return url;
}

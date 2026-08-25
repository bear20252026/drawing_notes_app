import 'package:material_ui/material_ui.dart';

/// 内容工作区的低对比环境背景。
///
/// 仅用于资料库与列表等导航场景，为局部玻璃控制层提供自然的明暗参照；
/// 编辑器画布与纸张内容保持独立，不使用该背景以避免影响创作判断。
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF000000), Color(0xFF0A0A0A), Color(0xFF000000)]
              : const [Color(0xFFF2F2F7), Color(0xFFF5F5F7), Color(0xFFF2F2F7)],
          stops: const [0, 0.52, 1],
        ),
      ),
      child: child,
    );
  }
}

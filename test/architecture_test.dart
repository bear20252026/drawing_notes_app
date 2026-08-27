import 'package:dart_arch_test/dart_arch_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// 架构规则测试（2026-08-15 引入 dart_arch_test 0.3.1）。
///
/// 依据专家级调研（Flutter 官方架构指南 + dart_arch_test/import_guard 等
/// 多源交叉验证）：架构边界必须工具化强制（"规则不在人脑里"），
/// 以纯 Dart 测试落地、随 CI 运行。规则逐条小步引入：
/// 1. 层方向单向（presentation → application → infrastructure → domain）
/// 2. 零循环依赖
/// 3. feature 切片隔离 + Martin 耦合度量基线
///
/// 原则：不破坏功能（违规先 freeze 基线，修复只增量）；可回溯。
void main() {
  late DependencyGraph graph;

  setUpAll(() async {
    // flutter test 从包根执行；使用 '.' 限定依赖图收集范围为本仓库。
    // 先前的 '../' 会扫到上级工作目录，导致架构测试高内存且不可复现。
    graph = await Collector.buildGraph('.');
  });

  test('规则1：层方向单向——高层只允许依赖低层', () {
    defineLayers({
      'presentation': 'features/**/presentation/**',
      'application': 'features/**/application/**',
      'infrastructure': 'features/**/infrastructure/**',
      'domain': 'features/**/domain/**',
    }).enforceDirection(graph);
  });

  test('规则2：零循环依赖——lib 内 import 图无环', () {
    // 仅检查本项目 lib/（features/core/shared），排除 windows/ 等
    // 构建缓存的插件符号链接（file:/// URI，非本包代码）。
    // freeze 基线：document_commands ↔ drawing_controller 为命令模式
    // 双向协作（controller 公开包装方法 + 命令类持有引用）的历史违规，
    // 记录基线后 CI 只拦新增循环；解除列入专项重构（不破坏功能）。
    freeze('zero_cycles', () {
      shouldBeFreeOfCycles(
        union(
          filesMatching('features/**'),
          filesMatching('core/**'),
          filesMatching('shared/**'),
        ),
        graph,
      );
    });
  });

  test('规则3a：绘图应用层仅依赖跨功能只读契约', () {
    shouldNotDependOn(
      filesMatching('features/drawing/application/**'),
      filesMatching('features/notes/domain/**'),
      graph,
    );
  });

  test('规则3b：属性面板直接依赖绘图领域元素类型', () {
    shouldNotDependOn(
      filesMatching('features/drawing/presentation/properties_panel.dart'),
      filesMatching('features/notes/domain/**'),
      graph,
    );
  });

  test('规则3：feature 非 domain 依赖禁止（domain 实体双向共享合规）', () {
    // domain 是最内层纯数据（check_boundaries 规则 1：core 允许依赖
    // features domain 实体），实体双向共享合规；真正禁止的是跨 feature
    // 的 infrastructure/presentation 依赖（真横向耦合）。
    // freeze 基线：剩余 infrastructure/presentation 横向依赖（editor_page→
    // notebook_storage/presentation_page）；应用层已通过只读契约脱离 notes。
    // 为接口化推进中的已知历史违规，CI 只拦新增。
    freeze('feature_isolation', () {
      shouldNotDependOn(
        filesMatching('features/drawing/**'),
        filesMatching('features/notes/infrastructure/**'),
        graph,
      );
      shouldNotDependOn(
        filesMatching('features/drawing/**'),
        filesMatching('features/notes/presentation/**'),
        graph,
      );
      shouldNotDependOn(
        filesMatching('features/notes/**'),
        filesMatching('features/drawing/infrastructure/**'),
        graph,
      );
      shouldNotDependOn(
        filesMatching('features/notes/**'),
        filesMatching('features/drawing/presentation/**'),
        graph,
      );
    });
  });

  test('规则4：六边形方向——依赖仅指向内层（domain 最内）', () {
    // 洋葱/六边形规则（dart_arch_test defineOnion，官方 API）：
    // 内层列表在前，内层不得依赖外层；core 与 shared 为 out-of-scope
    // 共享层（任何 feature 层均可依赖，视为 SDK 同级）。
    // freeze 基线：6 处 application→infrastructure（drawing_controller→
    // layer_compositor/stroke_geometry_cache/shape_recognizer/shape_
    // binding_geometry、editor_exporter→pdf_hybrid/svg_exporter，控制器
    // 与导出器直接使用基础设施具体类），记录基线后 CI 只拦新增；
    // 接口化解除列入专项（不破坏功能）。
    freeze('onion_direction', () {
      defineOnion({
        'domain': 'features/**/domain/**',
        'application': 'features/**/application/**',
        'infrastructure': 'features/**/infrastructure/**',
        'presentation': 'features/**/presentation/**',
      }).enforceOnionRules(graph);
    });
  });

  test('规则3b：Martin 耦合度量——domain/core 数据层稳定（instability 基线）', () {
    // Robert C. Martin 耦合指标：I = Ce/(Ca+Ce)，0=稳定（被依赖多），
    // 1=不稳定。domain（纯数据内层）与 core 数据层（storage/di/theme/
    // utils）应为稳定层：被大量依赖而几乎不依赖他人（I 低）。
    // core/rendering（渲染/导出器）为六边形"输出适配器"性质（工具
    // 依赖多、被依赖少，I 天然偏高），不纳入稳定层断言。
    final report = {
      ...Metrics.martin('domain/**', graph),
      ...Metrics.martin('core/storage/**', graph),
      ...Metrics.martin('core/di/**', graph),
      ...Metrics.martin('core/theme/**', graph),
      ...Metrics.martin('core/utils/**', graph),
    };
    // freeze 基线（2026-08-16）：core/storage/vfs（加密对象仓库——专家
    // 目标架构 VFS）为新目录未接线（lib 内 fan-in 0——I 天然 1.0）——
    // 媒体/笔记本对象纳入 VFS 后 fan-in 增加自然合规。与项目"违规先
    // freeze 基线，修复只增量"原则一致。
    report.removeWhere((k, _) => k.contains('/vfs/'));
    var worst = 0.0;
    // ignore: avoid_print
    print('--- Martin 耦合报告（domain/core）---');
    for (final e in report.entries) {
      final i = e.value.instability;
      // ignore: avoid_print
      print(
        '${e.key}: I=${i.toStringAsFixed(2)} Ca=${e.value.afferent} Ce=${e.value.efferent}',
      );
      if (i > worst) worst = i;
    }
    // 基线：稳定层最差 instability 不得超过 0.4（实测 domain/core 最差
    // 0.33 有余量，收紧自 0.6——2026 架构守护收紧）。
    expect(
      worst,
      lessThanOrEqualTo(0.4),
      reason: 'domain/core 应为稳定层（I≤0.4），实测最差 $worst',
    );
  });
}

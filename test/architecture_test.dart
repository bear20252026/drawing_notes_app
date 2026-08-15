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
    // 测试运行于 test/ 下，'../' 即包根（pubspec.yaml 所在目录）。
    graph = await Collector.buildGraph('../');
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

  test('规则3：feature 切片隔离——drawing/notes 仅允许单向依赖', () {
    // 项目既定规则（check_boundaries）：允许 notes → drawing
    // （共享 domain 实体）；drawing → notes 属横向依赖。
    // freeze 基线：9 处 drawing → notes 为 S4b 接口化推进中的已知历史
    // 违规（经 core/notes_accessor.dart 收敛），记录基线后 CI 只拦新增；
    // 解除列入 S4b 专项（不破坏功能）。
    freeze('feature_isolation', () {
      defineSlices({
        'drawing': 'features/drawing/**',
        'notes': 'features/notes/**',
      })
          .allowDependency('notes', 'drawing')
          .enforceIsolation(graph);
    });
  });

  test('规则3b：Martin 耦合度量——domain/core 稳定层（instability 基线）', () {
    // Robert C. Martin 耦合指标：I = Ce/(Ca+Ce)，0=稳定（被依赖多），
    // 1=不稳定。domain（纯数据内层）与 core 应为稳定层：被大量依赖
    // 而几乎不依赖他人（I 低）。先打印实测，阈值按小步基线收紧。
    final report = {...Metrics.martin('domain/**', graph), ...Metrics.martin('core/**', graph)};
    var worst = 0.0;
    // ignore: avoid_print
    print('--- Martin 耦合报告（domain/core）---');
    for (final e in report.entries) {
      final i = e.value.instability;
      // ignore: avoid_print
      print('${e.key}: I=${i.toStringAsFixed(2)} Ca=${e.value.afferent} Ce=${e.value.efferent}');
      if (i > worst) worst = i;
    }
    // 基线：稳定层最差 instability 不得超过 0.6（先宽松，后续按实测收紧）。
    expect(worst, lessThanOrEqualTo(0.6),
        reason: 'domain/core 应为稳定层（I≤0.6），实测最差 $worst');
  });
}

import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——FeatureFlagManager 特性标志测试（纯逻辑——不搞崩）。
void main() {
  test('FeatureFlag：默认值 + isAvailable', () {
    const experimental = FeatureFlag(id: 'f1', name: 'Feature 1');
    expect(experimental.enabled, false);
    expect(experimental.isAvailable, false); // experimental 默认不可用。

    const stable = FeatureFlag(id: 'f2', name: 'Feature 2', status: FeatureStatus.stable);
    expect(stable.isAvailable, true); // stable 默认可用。

    const enabled = FeatureFlag(id: 'f3', name: 'Feature 3', status: FeatureStatus.beta, enabled: true);
    expect(enabled.isAvailable, true); // beta + enabled = 可用。
  });

  test('FeatureFlag：copyWith 不可变', () {
    const original = FeatureFlag(id: 'f1', name: 'F1');
    final toggled = original.copyWith(enabled: true, status: FeatureStatus.stable);
    expect(original.enabled, false); // 原实例不变。
    expect(toggled.enabled, true);
    expect(toggled.status, FeatureStatus.stable);
  });

  test('FeatureFlagManager：add/remove/get', () {
    const manager = FeatureFlagManager();
    final withFlag = manager.add(const FeatureFlag(id: 'f1', name: 'F1'));
    expect(withFlag.count, 1);
    expect(withFlag.get('f1')!.name, 'F1');
    final removed = withFlag.remove('f1');
    expect(removed.count, 0);
  });

  test('FeatureFlagManager：isEnabled（stale 默认可用）', () {
    final manager = const FeatureFlagManager().add(
      const FeatureFlag(id: 'stable', name: 'S', status: FeatureStatus.stable),
    ).add(
      const FeatureFlag(id: 'beta', name: 'B', status: FeatureStatus.beta),
    );
    expect(manager.isEnabled('stable'), true);
    expect(manager.isEnabled('beta'), false); // beta 默认不可用。
    expect(manager.isEnabled('unknown'), false);
  });

  test('FeatureFlagManager：toggle/enable/disable', () {
    final manager = const FeatureFlagManager().add(
      const FeatureFlag(id: 'f1', name: 'F1'),
    );
    final toggled = manager.toggle('f1');
    expect(toggled.isEnabled('f1'), true);
    final disabled = toggled.disable('f1');
    expect(disabled.isEnabled('f1'), false);
    final enabled = disabled.enable('f1');
    expect(enabled.isEnabled('f1'), true);
  });

  test('FeatureFlagManager：byStatus/byGroup', () {
    final manager = const FeatureFlagManager().add(
      const FeatureFlag(id: 'f1', name: 'F1', status: FeatureStatus.stable, group: 'core'),
    ).add(
      const FeatureFlag(id: 'f2', name: 'F2', status: FeatureStatus.beta, group: 'experimental'),
    ).add(
      const FeatureFlag(id: 'f3', name: 'F3', status: FeatureStatus.stable, group: 'core'),
    );
    expect(manager.byStatus(FeatureStatus.stable).length, 2);
    expect(manager.byGroup('core').length, 2);
    expect(manager.byGroup('experimental').length, 1);
  });

  test('FeatureFlagManager：enableAllBeta / disableAllExperimental', () {
    final manager = const FeatureFlagManager().add(
      const FeatureFlag(id: 'beta1', name: 'B1', status: FeatureStatus.beta),
    ).add(
      const FeatureFlag(id: 'exp1', name: 'E1', enabled: true),
    );
    final enabledBeta = manager.enableAllBeta();
    expect(enabledBeta.isEnabled('beta1'), true);
    final disabledExp = manager.disableAllExperimental();
    expect(disabledExp.isEnabled('exp1'), false);
  });

  test('FeatureFlagManager：enabledCount', () {
    final manager = const FeatureFlagManager().add(
      const FeatureFlag(id: 'f1', name: 'F1', enabled: true),
    ).add(
      const FeatureFlag(id: 'f2', name: 'F2'),
    );
    expect(manager.enabledCount, 1);
  });

  test('FeatureStatus 枚举', () {
    expect(FeatureStatus.values.length, 4);
  });
}

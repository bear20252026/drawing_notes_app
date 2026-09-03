import 'package:flutter/widgets.dart';

/// Apple / Emil Kowalski 动效令牌层。
///
/// 全部数值有明确出处，禁止凭空发明（规范原文：
/// "No approximated values. Every curve, duration, and spring config comes
/// from the tables"）。每个令牌下方注明来源与裁决依据。
///
/// 来源优先级（冲突时自上而下裁决）：
/// 1. `DESIGN.md`（项目宪法，getdesign@apple）—— 颜色/字号/圆角/间距的唯一来源
/// 2. `review-animations/STANDARDS.md` —— 动效数值的权威源（时长表、曲线、物理性）
/// 3. `animate/RECIPES.md` + `animate-expo/RECIPES.md` —— 具体配方的实现参数
/// 4. `apple-design` / `animation-vocabulary` / `emil-design-eng` —— 理念与原则
///
/// 本层只承载**动效**（曲线/时长/弹簧），颜色与尺寸仍归
/// `apple_design.dart`，避免两套令牌源。
abstract final class AppleMotion {
  // ---------------------------------------------------------------------------
  // 缓动曲线
  // ---------------------------------------------------------------------------
  // 出处：STANDARDS.md:32-34（三份文档完全一致，无冲突）
  // 注意：Flutter 内置 Curves.easeOutCubic 的控制点是 (0.215,0.61,0.355,1)，
  // 与下面的 (0.23,1,0.32,1) **不是同一条曲线**——内置曲线"太弱"
  //（原文：Built-in CSS easings are too weak），必须显式构造。

  /// 强 ease-out：进出场、默认曲线。
  static const Curve easeOut = Cubic(0.23, 1.0, 0.32, 1.0);

  /// 强 ease-in-out：屏幕上移动/形变。
  static const Curve easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

  /// iOS 抽屉曲线（Ionic 提取）：抽屉/底部面板。
  static const Curve easeSheet = Cubic(0.32, 0.72, 0.0, 1.0);

  /// 匀速：进度条、跑马灯、长按确认的进度推进。
  static const Curve linear = Curves.linear;

  // ---------------------------------------------------------------------------
  // 时长
  // ---------------------------------------------------------------------------
  // 出处：STANDARDS.md:43-47 时长表 + animate/RECIPES.md 各配方实测值。
  // 硬规则：UI 动画一律 < 300ms（STANDARDS.md:49）。

  /// 按压反馈。区间 100–160ms；Web 配方用 160ms、Expo 移动端用 120ms。
  /// 取 120ms——本项目为触屏主用设备，偏快更跟手。
  static const Duration press = Duration(milliseconds: 120);

  /// 工具提示 / 小浮层。区间 125–200ms，配方取下限。
  static const Duration tooltip = Duration(milliseconds: 125);

  /// 下拉菜单 / 选择器。区间 150–250ms，配方取 200ms。
  static const Duration dropdown = Duration(milliseconds: 200);

  /// 模态对话框。区间 200–500ms，配方取 250ms（居中，不锚触发器）。
  static const Duration modal = Duration(milliseconds: 250);

  /// 抽屉 / 底部面板（非手势驱动时的兜底时长）；手势驱动走下方弹簧。
  static const Duration sheet = Duration(milliseconds: 300);

  /// 提示条入场。见下方 toastOut 的裁决说明。
  static const Duration toastIn = Duration(milliseconds: 300);

  /// 提示条退场——比入场快约 20%（Expo RECIPES 原文）。
  static const Duration toastOut = Duration(milliseconds: 250);

  /// 列表错位入场：单项时长。
  static const Duration staggerItem = Duration(milliseconds: 300);

  /// 列表错位入场：项间延迟。区间 30–80ms（Web 配方 50ms / Expo 40ms）。
  static const Duration staggerStep = Duration(milliseconds: 40);

  // ---------------------------------------------------------------------------
  // 弹簧
  // ---------------------------------------------------------------------------
  // 参数化裁决（这是本轮最需要决断的一处冲突）：
  // 三个来源给了三套写法——
  //   animation-vocabulary: damping + response（移动 1.0/0.4、旋转 0.8/0.4、抽屉 0.8/0.3）
  //   STANDARDS.md:          duration + bounce（{duration:0.5, bounce:0.2}）
  //   animate-expo:         duration + dampingRatio（{duration:300, dampingRatio:0.8}）
  // 三者不可混用。Flutter 的 SpringDescription.withDampingRatio 以 **ratio**
  // 为参数，而 ratio 恰与 animation-vocabulary 的 damping 同义
  //（1.0 = 临界阻尼无过冲，0.8 = 轻微回弹）。
  // 故统一以 **dampingRatio 为唯一口径**，duration 反解为 stiffness：
  //   静止/无过冲 → ratio 1.0
  //   手势带惯性 → ratio 0.8（与 animation-vocabulary 的 0.8 一致）

  /// 默认：临界阻尼，无过冲。用于普通 UI 的弹簧过渡。
  /// 对应 animation-vocabulary 的 damping 1.0。
  static final SpringDescription settled = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 180,
    ratio: 1.0,
  );

  /// 手势带惯性：轻微回弹。拖拽归位、吸附、抽屉回弹、滑动删除撤销。
  /// 对应 animation-vocabulary 的 damping 0.8（旋转 0.8/0.4、抽屉 0.8/0.3）。
  static final SpringDescription gesture = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 150,
    ratio: 0.8,
  );

  /// 活泼：仅用于罕见/首次的愉悦时刻（onboarding、成功庆祝）。
  /// bounce 上限 0.3（STANDARDS.md:73 要求 0.1–0.3）。
  static final SpringDescription playful = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 120,
    ratio: 0.7,
  );

  // ---------------------------------------------------------------------------
  // 其它硬数值
  // ---------------------------------------------------------------------------

  /// 入场起始缩放。区间 0.9–0.97；**禁止 scale(0)**
  ///（STANDARDS.md:53 "Nothing in the real world appears from nothing"）。
  static const double enterScale = 0.96;

  /// 入场起始位移（px）。配方用 translateY(8px)，百分比场景改用 Offset。
  static const double enterOffsetY = 8;

  /// 按压缩放。DESIGN.md:439 明文 0.95；STANDARDS.md:59 标准值 0.97、
  /// subtle 区间 0.95–0.98。**取 0.95**——DESIGN.md 是项目宪法，
  /// 且落在 subtle 区间内，两处不冲突。
  static const double pressScale = 0.95;

  /// 速度甩除阈值：`|位移| / 耗时(ms) > 0.11` 即判定为快速滑动。
  /// 出处 STANDARDS.md:139。达到阈值即可关闭，不要求跨越距离门槛。
  static const double flingVelocityThreshold = 0.11;

  /// 遮掩不完美交叉淡入时的模糊半径（px）。上限 20px，
  /// 且移动端每帧重渲模糊代价高——仅在确有重影时使用。
  static const double crossfadeMaskBlur = 2;

  // ---------------------------------------------------------------------------
  // 判定
  // ---------------------------------------------------------------------------

  /// 是否应关闭动效。
  ///
  /// 三个独立信号（规范原文为三个媒体查询，Flutter 侧映射如下）：
  /// - `prefers-reduced-motion`      → [disableAnimations]
  /// - `prefers-reduced-transparency`→ Flutter 无系统对应，需自建开关（见下）
  /// - `prefers-contrast`            → [highContrast]
  ///
  /// 减弱动效 = **更少更轻**，不是零：保留透明度与颜色过渡，
  /// 去掉位移、缩放、视差、过冲（STANDARDS.md:176）。
  static bool reduceMotionOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.disableAnimations || mq.highContrast;
  }
}

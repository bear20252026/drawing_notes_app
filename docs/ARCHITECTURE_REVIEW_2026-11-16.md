# 架构健康度审查报告（2026-11-16）

> 触发：业主「全面升级，重构审查架构代码，是否变成屎山」。
> 方法：两路只读勘察（架构健康度 / 代码质量热点）+ 主线程逐行复核高危发现
> + 全量门禁实测。基线 master `5e537cef`（material_ui 迁移完成后）。
> 结论先行：**宏观不是屎山，微观 editor_page 是「有治理的巨型泥球」。**

## 一、屎山判定：证据而非感觉

「屎山」的典型特征是：分层崩坏、循环依赖、无人敢动的巨型文件、门禁形同虚设、
满屏 TODO/HACK。逐项对照本项目：

| 屎山特征 | 本项目实测 | 判定 |
|---|---|---|
| 分层崩坏/跨层倒挂 | core→features 非 domain **0**、shared→features **0**、跨 feature 非 domain **0**、洋葱违规 **0** | ✅ 无 |
| 循环依赖 | 源码环 **0**（唯一环在 l10n 生成物，门禁豁免） | ✅ 无 |
| 门禁形同虚设 | 9 规则 + 14 专项门禁 + 边界脚本 + DCM，CI 真实跑、违规即红 | ✅ 真实 |
| 满屏 TODO/HACK | 真实 **0 处**（唯一命中是注释里的文件名占位） | ✅ 无 |
| 无人敢动的巨型文件 | editor_page 库 **7158 行**、扇出 **73** 全仓最高 | ⚠️ 局部是 |
| 死代码/重复堆积 | formatVersionOf 零引用（已删）、text_span_editor 约 40 行同构循环 | ⚠️ 少量 |

**结论**：这不是整体屎山——宏观结构干净且治理真实有效。问题集中在
**editor_page 这一个库**：它是「有治理的巨型泥球」——门禁钉住了它的总行数
（棘轮只减不许增），但内部职责切分是「切位置不切逻辑」（主文件 :96 自认），
15 个 part 里只有 4 个职责单一，导出/文本编辑/裁剪各散在 2-4 个 part。

## 二、规模与耦合（量化）

- lib 375 文件 10.29 万行：源码 8.84 万、l10n 生成 1.44 万（14%）。
- 四层占比：features 198 文件/50.1% 行、core 133/30.2%、shared 22/3.5%、app 7/1.6%。
  presentation 33287 行 vs domain 2825 行——展示层独大（绘图 App 的正常形态，
  但 editor_page 把过多业务逻辑也压在了 presentation）。
- >500 行 warn 档 **44 个**，>1000 行 error 档 **0 个**（单文件门禁有效）。
- **8 个 part 库合计破千**：editor_page 7158、doc_store 1600、notebook_storage
  1462、sync 1389、controller 1380、app_data_root 1259、webdav_settings 1052、
  app_lock_gate 1048。**单文件门禁对库总量失明，仅 editor_page 有库级棘轮。**
- 扇入 Top：app_localizations 62、apple_design 48、canvas_model/document 35
  （高扇入是稳定抽象，健康）。
- 扇出 Top：**editor_page 73**、app_shell 43、home_page 40、notebook_view_page 39
  （editor_page 73 远超其余，是耦合热点）。

## 三、本批已修复（高置信度，读码复核 + 回归护航）

1. **DEK 用完即焚补齐 5 处**（encryption_service）：新生/改密/重置盘/绑盘/
   块文档解密路径的 DEK 此前无 finally 零化，与 KEK/media 槽纪律不一致。
   只擦方法内独占副本；调用方传入的 rewrap DEK 未擦（回归钉住可二次复用）。
2. **明文外层取钥守卫**（notebook_storage_password.dart）：保险库有钥但笔记本
   未设密时外层明文，此前有钥即 decrypt 撞「不是 DNV 信封」抛错，阻断
   ensure/改密/绑盘。补 !isEncrypted 放行。
3. **死代码删除**：formatVersionOf 全仓零引用。
4. **mounted 守卫补齐**（editor_page 退出裁决第二异步间隙）。

新增回归 notebook_review_fixes_test 6 项。门禁：严格 analyze 零问题、
主套件 3068/5/0、KDF 97/1/0、架构+棘轮 154 项全过。

## 四、重构路线图（按收益/风险排序）

> 纪律前提：行数棘轮只减不许增；重构方向是**拆分/降复杂度/净删行**，不是加代码。
> 每项都须现有测试护航 + 黄金基线/门禁复验。
>
> **进度（2026-11-17）**：R2/R4 全部落地；R3 落地（命中几何纯函数 + 旋转
> 结束提交；「拖拽域统一入撤销」留待后续，见 R3 诚实边界）；R1 全部落地
> （导出/裁剪/文字编辑三域归并 + _applyState 收口单点 + 门禁钉死）；
> R5 仍待业主裁决。

### R1（最高优先）editor_page 库职责归并 —— ✅ 已落地（2026-11-17）
- **问题**：15 part 切位置不切逻辑；_applyState 散见 11 文件 92 处；
  editing 798 行混文字/图片/形状/分组/链接五类；actions 653 行是菜单/导出/
  图表/演示/统计/复制粘贴杂烩。
- **方向**：按职责归并 part（导出收敛一处、裁剪收敛一处、文本编辑收敛一处）；
  _applyState 收口单点；拆杂烩分支。目标是**净删行 + 扇出下降**。
- **风险**：高。手势/渲染回归面大，须现有 widget 测试 + 三平台构建护航。
  建议分多个小 PR，每个只动一个职责域，棘轮逐次下降。
- **已落地（首域）**：导出方法群（PNG/PDF/SVG/RTF/TXT）从 persistence 归并
  进 actions 导出域，与 PPTX/JSON 合一。逐字搬移零逻辑变更。
- **已落地（剩余域）**：① 裁剪交互域——手柄（drag_ops）/键盘平移与 Esc
  退出（shortcuts）搬入 persistence 与 _confirmCrop 团聚；② 文字编辑域——
  11 个纯文字方法（约 261 行）自 editing 搬入 text_overlays 与就地编辑渲染
  同域，editing 798→470 脱离五类杂烩；顺手归位缩放三法→input、分组两法→
  drag_ops；③ _applyState 收口——主文件 5 处裸 setState 收编、persistence
  的 notify() 第二包装删除，新增单点门禁测试钉死（作用域判定 + 塌空下限 +
  探针自证）。库总量 7149 不变（纯搬移）。
- **诚实边界（留档待裁决）**：文字新建的「提交+紧接刷新」双刷是有意时序
  （防输入框失焦）不合并；EditorViewModel.notifyListeners 全库无订阅者，
  VM 通知与页面刷新双轨是设计意图问题，同 R5 须业主裁决。

### R2（高优先）7 个无棘轮 part 库纳入治理 —— ✅ 已落地（2026-11-17）
- **问题**：doc_store 1600/notebook_storage 1462/sync 1389 等破千库无棘轮，
  单文件门禁对库总量失明。
- **方向**：先给这 7 个库补库级棘轮（钉住现状只减不许增，防继续膨胀），
  再逐个评估拆分。补棘轮是**零行为变更**的门禁投资，风险低，可先做。
- **风险**：低（补门禁）→ 中（后续拆分）。
- **落地形态**：test/architecture/part_library_ratchet_test.dart——7 库
  主文件 + part 合计行数台账（分母 7 防静默缩水），后续拆分只许降基线。

### R3（中优先）手势巨方法抽纯函数 + 旋转提交语义 —— ✅ 已落地（2026-11-17）
- **问题**：_onPointerUp ≈205 行、drag_ops ≈159 行多分支手势巨方法，测试盲区；
  旋转拖拽仅 onPanUpdate 每帧打保存链、无 onPanEnd 提交、不入撤销。
- **方向**：手势决策抽纯函数（可单测）；旋转改 onPanEnd 提交（撤销语义完整）。
- **风险**：中。手势回归面大，需 widget 测试护航。
- **落地形态**：框选/套索命中收敛进 infrastructure 纯函数
  MixedItemHitGeometry（+6 项单测钉边界口径）；旋转保存链通知移 onPanEnd
  （+onPanCancel 兜底），角度计算逐字未动。_onPointerUp 净降 20 行。
- **诚实边界**：「不入撤销」是整个混排拖拽域既有缺口（移动同样不入命令
  历史）——单独给旋转加撤销会造成语义分裂，留待拖拽域统一事务化。

### R4（低优先，净删行）重复与死码清理 —— ✅ 已落地（2026-11-17）
- text_span_editor toggleLink 约 40 行同构循环收敛进 _mapSelection；
  内部自用成员私有化（containsShape/containsImage/selectMixed，非死码）；
  skeleton 两份脉冲样板收敛进 _SkeletonPulseMixin。
- **风险**：低。全部净删行，棘轮下降。

### R5（待澄清）Riverpod 示范单元接线或删除
- drawing_notifiers 三域 Notifier + di_providers 派生 provider 生产零消费、
  仅测试在读（注释自认是示范单元）。
- **方向**：要么接线进生产（兑现示范价值），要么按棘轮删除（消除死代码）。
  这是设计意图问题，须业主裁决，不擅自删。

## 五、门禁盲区（建议补强）

1. ~~行数棘轮只钉 editor_page 1 库~~ → 已扩到其余 7 个破千库（R2 落地）。
2. 扇入/扇出无上限 → editor_page 73 无人管，建议加扇出棘轮。
3. DCM 仅开 avoid-unused-parameters/avoid-dynamic → 重复/死码无门禁，
   建议评估开 duplicate-code/dead-code 规则（先基线化存量再收紧）。
4. Martin「0.4 基线」实为硬约束 + 7 个 domain 具名棘轮（最高 I=1.00）——
   不稳定被钉住未修复，建议逐个评估降耦。

## 六、升级记录

- Flutter 3.50.0 已最新 stable（verify-only 确认，无需升）。
- pdfrx 链 2.12.1→2.13.0（pdfium_dart/pdfium_flutter 0.4.2→0.4.3、
  pdfrx_engine 0.9.2→0.9.3）。
- 7 个传递依赖受 SDK/约束钉住不可升（analyzer 14.7/qr 4.0.1/cross_file 0.4.0/
  package_config 3.0.0/test_api 0.7.15/material_color_utilities 0.13.1/
  _fe_analyzer_shared 111），非遗漏——升级须等上游约束放开。
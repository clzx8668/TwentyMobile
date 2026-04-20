# 筛选弹窗不显示（仅遮罩）修复与可观测性 Spec

## Why
真机上点击表格列标题的筛选图标后，仅出现遮罩层（除底部菜单外整体变暗），但筛选 BottomSheet 内容不出现且无报错，导致筛选功能不可用且难以定位根因。

## What Changes
- 增强筛选弹窗的打开策略：优先使用根 Navigator 的 Overlay 上下文打开，并提供可回退的弹窗实现以避免“只出遮罩不出内容”。
- 增加可观测性：在 Debug 下记录每次筛选弹窗打开尝试的关键诊断信息（上下文来源、路由信息、insets/尺寸、是否进入 builder、是否 pop 返回）。
- 捕获并上报异常：对弹窗打开过程中的同步/异步异常进行捕获记录（Debug 下可见），避免“无错但不显示”。
- 保持现有筛选交互不变：操作符（contains/equals/startsWith）、输入框、Apply/Clear/Cancel、筛选状态与 chips 展示逻辑不变。

## Impact
- Affected specs: 表格筛选弹窗稳定性、真机回归可验证性、调试效率
- Affected code:
  - `lib/presentation/shared/table/table_view.dart`（筛选打开逻辑与 BottomSheet 组件）
  - `lib/core/router/router.dart`（如需使用全局 navigatorKey 获取 overlay/context）

## ADDED Requirements
### Requirement: 筛选弹窗可观测性（Debug）
系统 SHALL 在 Debug 模式下为每次“打开筛选弹窗”的动作输出结构化诊断信息，至少包括：
- 触发列 key/label
- 使用的弹窗 context 来源（当前 context / root overlay context / 全局 navigatorKey context）
- 当前 MediaQuery insets（viewInsets.bottom 等）
- 是否进入 BottomSheet builder（可由埋点确认）
- 弹窗关闭结果（apply/clear/cancel）与耗时

#### Scenario: 打开成功
- **WHEN** 用户点击任意可筛选字段的筛选图标
- **THEN** 显示 BottomSheet（包含操作符与输入框），并输出一次 “open-start/open-builder/open-end” 诊断日志

#### Scenario: 打开失败（仅遮罩或无内容）
- **WHEN** 用户点击筛选图标后出现遮罩但未显示内容
- **THEN** 日志中必须能定位失败阶段（未进入 builder / builder 进入但布局高度异常 / 异常抛出）

### Requirement: 筛选弹窗打开回退策略
系统 SHALL 在主打开策略失败时自动尝试回退策略，以最大化“用户可见弹窗”的成功率。

#### Scenario: 主策略失败后回退
- **WHEN** 使用主策略打开 BottomSheet 未能进入 builder 或发生异常
- **THEN** 自动使用回退策略再次尝试打开（仅一次回退，避免循环），并记录回退路径日志

## MODIFIED Requirements
### Requirement: 筛选弹窗稳定可见
系统 SHALL 在 Android 真机上稳定显示筛选 BottomSheet，不得出现“只出遮罩、不出弹窗内容”的情况。

## REMOVED Requirements
无


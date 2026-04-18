# 回归用例清单（在线 / 断网 / 弱网 / 恢复网络）

本清单用于：
- Task 1：作为“现状可回归”的用例基线（主要覆盖在线链路与一致性）
- Task 4~7：作为“离线读/写 + outbox + 冲突处理”的验收用例（断网/弱网/恢复网络）

约定：
- 实体：Contacts / Companies / Tasks / Notes
- 网络状态：在线 / 断网 / 弱网（高延迟/丢包）/ 恢复网络（从断网→在线）
- 结果：UI 可见性、状态一致性、本地持久化、远端最终一致（如适用）

---

## A. 在线基础回归（当前实现应通过）

### A1. Contacts

- A1-1 列表加载与搜索
  - 步骤：进入 Contacts；输入关键字搜索；清空搜索
  - 期望：列表展示/刷新正常；空结果显示 EmptyState；无崩溃
- A1-2 分页/加载更多
  - 步骤：滚动到列表底部触发加载更多（如有）
  - 期望：加载更多指示器出现；追加数据；无重复/跳动异常
- A1-3 新建联系人（含邮箱/电话可选）
  - 步骤：Contacts 右下角 +；填 first/last；可选填 email/phone；保存
  - 期望：成功 toast；列表出现新联系人；进入详情能看到 email/phone（如填）
- A1-4 编辑联系人（含 company 绑定/清除）
  - 步骤：从联系人详情点编辑；修改 email/phone；选择 company；保存；再清除 company；保存
  - 期望：列表动态字段与详情一致更新；company 名称显示/隐藏符合预期
- A1-5 删除联系人
  - 步骤：列表 swipe 删除；或详情点删除并确认
  - 期望：联系人从列表消失；返回上一页；无残留崩溃

### A2. Companies

- A2-1 列表加载与搜索
  - 步骤：进入 Companies；搜索公司名/域名；清空搜索
  - 期望：列表更新；无崩溃
- A2-2 新建公司（domain 可选）
  - 步骤：Companies +；填 name；可选填 domain；保存
  - 期望：列表出现；详情展示 domain（如填）且可点击打开浏览器
- A2-3 编辑公司（domain 可清空）
  - 步骤：编辑公司；修改 name/domain；将 domain 清空保存
  - 期望：列表/详情同步更新；domain 清空后不展示链接
- A2-4 删除公司
  - 步骤：列表 swipe 删除；或详情删除并确认
  - 期望：公司消失；无崩溃
- A2-5 公司-联系人关联读取
  - 步骤：进入公司详情查看 Linked contacts
  - 期望：能加载并展示关联联系人；点击 chip 可跳转联系人详情

### A3. Tasks

- A3-1 列表加载与完成过滤
  - 步骤：进入 Tasks；切换 Filter completed；来回切换
  - 期望：列表根据完成状态过滤；UI 无异常
- A3-2 新建任务（title 必填；due/contact 可选）
  - 步骤：Tasks +；仅填 title 保存；再新建一个含 dueAt；再新建一个绑定 contact
  - 期望：创建成功；列表展示 due/contact chip（如有）；可编辑
- A3-3 编辑任务（title/due/完成状态）
  - 步骤：打开 EditTaskSheet；改 title；设置/清空 dueAt；勾选完成/取消完成
  - 期望：列表样式变化；dueAt 展示正确；无崩溃
- A3-4 删除任务（两入口一致）
  - 步骤：列表 swipe 删除；或编辑 sheet 内删除
  - 期望：任务消失；Home（Today）同步更新（如展示）

### A4. Notes（Contact 维度）

- A4-1 Contact 详情新增 note
  - 步骤：进入某 Contact 详情；New Note；输入文本保存
  - 期望：notes 列表立即出现；全屏打开渲染正常
- A4-2 编辑 note
  - 步骤：点开 note；Edit；修改文本保存
  - 期望：列表与全屏内容更新；无崩溃

### A5. Notes（Company 维度）

- A5-1 Company 详情新增 note（现状可能失败/不回显）
  - 步骤：进入某 Company 详情；New Note；输入文本保存
  - 期望：应当出现于 company notes 列表
  - 备注：当前实现存在已知缺口（见 [crud-gap-audit.md](file:///e:/devF/TwentyMobile/.trae/specs/enhance-crm-offline-sync/crud-gap-audit.md)），此用例用于验证修复完成与防回归

---

## B. 弱网与“single request 限制”回归（当前实现应尽量通过）

- B1 Contacts 列表在服务端报 “cannot be executed as a single request” 时降级
  - 步骤：模拟服务端返回 single request 限制（或用受限实例）
  - 期望：自动 fallback 到 simple query；列表仍可展示（可能字段减少）
- B2 Companies 列表/详情在 single request 限制时降级
  - 期望：同上

---

## C. 离线读回归（Task 4：Offline Read 引入后应通过）

- C1 断网启动/进入页面
  - 步骤：断网；启动 App；进入 Contacts/Companies/Tasks；进入某条详情
  - 期望：优先展示本地缓存；不白屏、不无限 loading；有“离线/未同步”提示（如设计）
- C2 在线→断网后回退
  - 步骤：在线浏览列表与详情；切断网络；再次进入同页面
  - 期望：仍可读；数据与上次同步一致；刷新行为给出明确反馈

---

## D. 离线写回归（Task 5：Outbox 引入后应通过）

- D1 断网新建 Contact
  - 步骤：断网；创建 Contact；返回列表
  - 期望：列表立即出现（本地落库）；标记为待同步；不阻塞用户继续操作
- D2 断网编辑 Contact / 绑定 Company
  - 期望：本地立即更新；操作进入 outbox；同一实体连续编辑会合并（如实现 coalesce）
- D3 断网删除 Contact
  - 期望：本地移除；outbox 入队；恢复网络后远端也被删除
- D4 断网新建 Company / 编辑 / 删除
  - 期望：同上
- D5 断网新建 Task（含 body、due、contact 绑定）
  - 期望：本地可见；恢复网络后远端创建且 target 绑定正确
- D6 断网新增/编辑/删除 Note（Contact/Company）
  - 期望：本地可见；恢复网络后远端一致；Company Note 不出现“孤儿”

---

## E. 恢复网络自动/手动同步回归（Task 6：同步引擎引入后应通过）

- E1 自动 flush：断网期间产生多条 outbox，恢复网络后自动同步
  - 期望：队列按序执行；失败有可见原因与可重试；最终一致
- E2 手动同步入口
  - 步骤：断网操作→恢复网络；手动点“立即同步”
  - 期望：展示进度；成功/失败明确

---

## F. 冲突回归（Task 6：冲突处理引入后应通过）

- F1 同一实体在远端被其他客户端更新，本地也有未同步更新
  - 步骤：A 端离线编辑；B 端在线修改并保存；A 端恢复网络触发 flush
  - 期望：检测冲突；不静默覆盖；提供“保留本地/采用远端”等可执行策略


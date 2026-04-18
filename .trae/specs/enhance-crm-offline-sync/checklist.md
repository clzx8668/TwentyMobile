* [x] 字段矩阵已完成，并覆盖 Contacts/Companies/Tasks/Notes 的“展示/编辑/空值策略/优先级”

* [x] Company 详情页新增 Note 可成功创建并正确关联到该 Company（非孤儿 Note）

* [x] Notes 在 Contact 与 Company 维度均支持创建、编辑、删除，并且 UI 有明确入口

* [x] 新建 Task 支持填写 body，且列表/详情能展示该字段

* [x] 无网络时，Contacts/Companies/Tasks/Notes 列表与详情可从本地缓存读取，不白屏、不无限 loading

* [x] 离线新增/编辑/删除会写入 outbox，网络恢复后可自动或手动 flush 到远端

* [x] 同步过程中发生冲突时不会静默覆盖，并提供可执行的处理策略

* [x] 所有远端请求与 outbox 操作均带 source 标记，错误可定位且可复现

* [x] 关键回归（在线/离线/恢复网络/冲突）通过，且无新增严重崩溃


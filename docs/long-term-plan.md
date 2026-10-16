# MoonPot 远期迭代计划（Long-Term Plan）

> 版本基线：v0.1.0 MVP（2026-10-16，全模块 selftest 20 块 + e2e 四通道全绿）。
> 节奏：以「季度里程碑 + 双周迭代」推进；每阶段出口以验收标准（DoD）为准。
> 原则：零依赖优先、`Store`/`AiProvider` trait 抽象不破坏、每环带测试落地（记/锁/回）。

---

## 测试基建基线（v0.1.x，已完成 2026-10-16）

| 层 | 载体 | 覆盖 |
| --- | --- | --- |
| 单元/集成 | `cmd/selftest` 20 块 | store CRUD/持久化、AI 边界与确定性、FakeProvider 替换、损坏快照容错、MCP 全方法+错误码、KB 空索引/CJK/topk 边界、CLI 错误路径、500-shape 规模+Unicode+深嵌套、HTML 转义、技能管线 |
| 端到端 | `e2e/run_e2e.sh` | REST 10 项断言、WebSocket JSON-RPC 往返、MCP 文件传输、CLI 全链路+快照落盘、selftest 终态校验 |

本阶段已修复缺陷：小画布（宽/高过小）`grid_cells` 空数组导致 `cells[i]` 越界 panic → 内容区钳制 ≥64px。

---

## v0.2 — AI 升级（目标：2026-11 中旬）

**主题：从"确定性 Mock"走向"真模型可插拔"，同时保持离线可跑。**

- [ ] `OpenAiCompatProvider`：实现 `AiProvider`（trait 已 `pub(open)`），OpenAI 兼容 chat/completions 端点，环境变量注入 key/base_url。
- [ ] 结构化输出契约：模型返回 JSON 设计树 → `@json.from_json` 校验，非法输出自动降级 Mock 重试（自愈式 fallback）。
- [ ] 流式生成：`/api/generate/stream`（SSE）与 `/ws` 进度帧（"adding a title block…"）。
- [ ] KB 升级：IDF 加权 + CJK 二元组（bigram）分词 + 增量 `add()` 保序测试。
- [ ] 测试：Provider 契约测试套件（Mock/Fake/真实 Provider 共享同一组断言）；快照对比防回归。

**验收**：真实 Provider 与 Mock 通过同一契约测试；断网时 `moonpot serve` 全功能可用。

## v0.3 — 持久化与协作（目标：2026-12）

**主题：把"单机快照"升级为"多端协作"。**

- [ ] PostgreSQL Store 实现（schema：projects/files/pages/shapes，JSONB 兜底列 + 关系列双写）。
- [ ] 文件修订链：`file_revisions` 表 + `ShapePatch` 补丁端点（模型已备），乐观锁 `rev` 字段。
- [ ] WS 协作房间：`/ws/:pid` 频道广播 shape 增删改；`WebSocketPeer::publish/subscribe` 已内置。
- [ ] 权限雏形：项目级 token（只读/读写），REST + WS 统一鉴权中间件。
- [ ] 测试：双客户端并发编辑 e2e；断线重连补发；修订回放一致性。

**验收**：两个浏览器标签页经 WS 同步编辑同一文件；重启服务数据不丢。

## v0.4 — 表面与生态（目标：2027-01）

**主题：让 MoonPot "看得见、进得来"。**

- [ ] 静态托管：`/preview/:pid/:fid` 直出渲染 HTML；SVG 导出端点。
- [ ] `moonpot render` CLI 子命令：设计树 → HTML/SVG 文件。
- [ ] MCP 规范对齐：tools/list 资源发现、能力协商（initialize handshake），对接 Claude/Cursor 实测。
- [ ] 前端阅读视图（只读画布预览，非交互编辑——仍不触碰交互式 canvas 红线）。
- [ ] 测试：视觉快照（渲染 HTML 规范化 diff）；MCP 官方客户端互操作清单。

**验收**：Claude Desktop 通过 MCP 直接调用 moonpot/list_projects 并生成设计。

## v0.5 — 运维与发布（目标：2027-02）

**主题：可部署、可观测、可升级。**

- [ ] Dockerfile（多阶段）+ docker-compose（server + postgres）；镜像 < 50MB。
- [ ] 优雅停机（crescent shutdown 队列）+ `/health` 就绪/存活分离。
- [ ] 结构化日志中间件（请求 ID、耗时、状态码）+ 最小指标端点（QPS/延迟分位数）。
- [ ] 快照自动保存策略（脏标记 + 定时刷盘）与损坏快照恢复演练（复用 [15] 用例）。
- [ ] CI：GitHub Actions 跑 `moon build`（0 警告门禁）+ selftest + e2e（容器内放宽沙箱）。

**验收**：一条 `docker compose up` 起全栈；CI 全绿门禁。

## v1.0 — 公开发布（目标：2027-Q1 末）

- 版本化 API（`/api/v1/` 前缀冻结）、语义化版本承诺、破坏性变更流程。
- 安全审计：输入校验上限（请求体大小/嵌套深度）、WS 帧率限制、依赖零审计基线。
- 文档站（README + docs 全量英文化）、示例库（5 个 prompt→设计案例）、录屏 Demo。
- 提交 MoonBit 生态 Showcase；视情况参加 2027 春季黑客松迭代赛道。

---

## 风险登记

| 风险 | 等级 | 缓解 |
| --- | --- | --- |
| MoonBit 工具链快速演进（API 破坏） | 高 | 锁定 0.1.20260920 基线；升级前跑全量 selftest+e2e 门禁 |
| crescent 上游 API 变动（如 try_json 可见性） | 中 | 自持 `parse_body` 等适配层，隔离外部 API 直呼 |
| 真实 LLM 输出不稳定 | 中 | 结构化校验 + Mock 自动降级；契约测试锁行为 |
| 单人节奏 vs 季度目标 | 中 | 每阶段只承诺 1 个主题；验收可裁剪，红线不裁剪（测试先行的记/锁/回） |
| Windows 沙箱限制（moon test 阻塞） | 低 | 维持 selftest+e2e 可执行验证通道；CI 内用原生 runner 补齐 |

## 度量

- 质量门禁：`moon build` 0 warning/0 error；selftest 全绿；`bash e2e/run_e2e.sh` PASS=FAIL=0。
- 每阶段追加 e2e 用例数 ≥ 该阶段新增端点/能力数。

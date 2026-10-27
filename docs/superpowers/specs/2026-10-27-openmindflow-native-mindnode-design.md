# OpenMindFlow 原生文稿与 MindNode v9 兼容设计

## 目标与判断

- 新建/编辑文稿默认保存为 **`.mflw` 普通文件**；不再产生新的 `.mindmap.json` 工作稿。旧 `.mindmap.json` 仅作为迁移输入，打开后首次 Save 转为 `.mflw`，不回写旧文件。
- 不选 `.omf`：该扩展名已经由 Open Media Framework Interchange 使用（[PRONOM](https://pronom.nationalarchives.gov.uk/fmt/1854)）。公开格式检索未见 `.mflw` 的明显主流冲突；这不是全球唯一性的数学保证。UTI 为 `local.openmindflow.document`，MIME 为 `application/vnd.openmindflow.mflw`。
- MindNode v9 目录包或普通二进制 plist 可以导入到可编辑画布；Cmd-S 保存为 `.mflw`。File → Export MindNode… 或 Save As MindNode Copy… 明确写一个**新的、未占用的** `.mindnode`，原导入文件始终不作为隐式写入目标。合成输出被我们的 importer 验证不等于原 MindNode 应用已经接受，必须单独实机验证。

## 方案取舍

1. **选用：版本化二进制 `.mflw`＋内嵌原 MindNode 来源快照。** 格式有独立魔数、版本、长度和 SHA-256 校验；负载为 binary property list，包含当前 `OwnMapDocument` 全部可编辑字段和可选的原始 v9 包字节/来源树/显示元数据。打开后可离线编辑并在来源消失后重新导出；数据量上限 128 MiB，严格拒绝未知版本、损坏/截断文件和不安全路径。
2. 不用换后缀的 JSON/ZIP 内 JSON：不符合用户的“不用 JSON”，并可能把纯文本数据误认成新格式。
3. 不以 `.mindnode` 作为唯一工作格式：该格式存在未知字段和未验证的附件/连接/主题编辑语义，直接覆盖会产生不可逆损失。

## 模块边界及数据流

- `Sources/OpenMindFlowFile.swift`：`readNativeMap(_:)`/`writeNativeMap(_:to:)`，二进制封装、校验及原子文件写入；只依赖现有 `OwnMapDocument` 验证，不修改 legacy JSON 编码。返回文稿与可选 `Data` 来源快照；不解析 MindNode。
- `Sources/MindNodeArchive.swift`：从 v9 来源捕获目录普通文件/目录路径或单文件字节（最多 64 MiB/1000 项），同时留存导入时的树和视觉元数据；独立解码/验证，拒绝路径逃逸、链接及损坏；向同一/不同父目录中的**新** `.mindnode` 原子发布。导出首先在私有暂存包里用 `MindNodeTitlePatch` 修补原始 binary plist，保留所有未知字典项、主题文件、附件、连接和不改动资源字节。`MindNodeWriter` 只作为**无导入来源且全部字段属于已验证简单树子集**的生成路径。
- `Sources/App.swift`：文件菜单提供 Open Map、Import MindNode、Save、Export MindNode；若提供 Save As MindNode Copy，同样明确为新副本而不把导入原件变成自动覆盖目标。`fileURL` 只跟踪 `.mflw`；实现 Finder 双击 `.mflw` 的 NSApplication 打开文件回调（含应用启动阶段排队及运行中已有脏文稿确认）。导入保存时附带来源快照；导出失败不得修改 dirty、选区、原始路径或用户文件。打开文件先验证，再询问已有未保存编辑是否丢弃，提交编辑器后才写盘。随系统语言更新中英提示与 About 文案。
- `scripts/build-openmindflow-local.sh` 在 bundle Info.plist 中声明 `.mflw` UTType/文稿角色；旧签名候选及原 `.mindnode`、历史包均不覆盖。

## MindNode 编辑兼容边界

第一阶段对已有节点的普通纯文本标题、折叠和同一主图内现有节点顺序进行保真更新，原主题/资源/未知字段原样保留；未修改的复杂富文本也保留原始字节。不清楚如何无损表达的编辑（如修改混排富文本、删除关联附件的节点、未知主题的改色、添加不受支持的跨连接/视频/备注）明确报错并**不生成损失性 `.mindnode`**，但它们仍可保存在 `.mflw` 中。随后以独立测试逐步扩展可验证的宽度、位置、字体、颜色和新节点写回；绝不将未支持字段静默丢弃。普通单文件 v9 走同样的二进制 plist 更新校验，目录来源保留非 `contents.xml` 文件。

## 测试与安全验收

1. TDD：先观测 RED：新 `.mflw` 魔数/版本/截断/篡改/超大/符号链接/`.mindnode` 内路径/原子读写；含图片、视频、备注、关系、主题的模型关闭后重开完全相等；旧 JSON 导入后新目标是 `.mflw`。
2. 合成 v9 目录含未知字段、主题、资源、连接/附件/富文本：不修改内容的导出与所支持标题/折叠改动后导出，都与原包逐文件比较非目标内容、重新导入核对，原包哈希未变；不支持的编辑、已占用目标、竞态变更和恶意路径必须失败且不产生部分交付。单文件同样覆盖。
3. 原生 `NSWindow` 可不显示、不得使用对当前用户应用的全局 HID/AX；测试菜单、脏标、打开→编辑→Save→重开、导出失败回滚。其结果是安全自动化测试，不代替真实 Finder/Open/原 MindNode 应用的手测。
4. 运行全部安全离屏套件；在新的 `/private/tmp/openmindflow-local-*` 独占暂存区构建/签名/验证后，只复制到新的 `build/`、`dist/` 名称并 `open -n`，旧窗口和旧包保持原样。版本属于本地候选，仍是 ad-hoc 签名、未经公证，不推送远端。

# MindNode v9 媒体与跨节点关联：静态证据和未解项

范围：只读检查安装的 `/Applications/MindNode.app`（版本 **2026.0.2**）及仓库中的合成 v9 测试；**未**读取用户 `.mindnode`、未操作原版 App 窗口，也未用原版 App 打开合成包。以下是当前版本二进制的键名线索，**不能直接当作 v9 序列化规范**。

## 可复核的静态线索

样本：`Contents/Frameworks/MindNodeCore_-250BE5B18F77775D_PackageProduct.framework/MindNodeCore_-250BE5B18F77775D_PackageProduct`；SHA-256 `dcfe6c7a4997f347910bf00feaaf0713cf89cfd95297ff8a1123a78254df8e14`。`nm -gU <binary> | xcrun swift-demangle` 返回这些**导出常量 getter 名称**；`strings -a <binary>` 另确认 `crossConnections`、`startNodeID`、`endNodeID`、`attachment`、`fileName`、`dashType`、`Assets`、`contents.xml` 的独立字面量：

| 位置线索 | 已证实的导出标识符 | 尚未证实 |
| --- | --- | --- |
| 画布关联 | `MNCCanvasKey.crossConnections`；`MNCConnectionKey.startNodeID`, `.endNodeID`, `.uuid`, `.connectionType`, `.pathStyle`, `.arrowStyle`, `.layout`, `.wayPoints`, `.wayPointOffset`, `.endPoints`, `.title` | plist 中的类型、必填集合、路径与 v9 兼容性 |
| 节点图片 | `MNCNodeKey.attachment`, `.attachmentPosition`；`MNCKey.Attachment.type`；`MNCKey.ImageAttachment.fileName`, `.tintKind`, `.tintColor`, `.mask`；`MNCImageFileManager.fileWrapper(ofImage:)` | 资源真实目录、文件名规则、引用/类型枚举、图片编码及回读 |
| 线型 | `MNCStrokeStyleKey.dashType`, `.color`, `.width` | dash 枚举值、v9 真实路径、支持的虚线语义 |
| 主题 | `MNCCanvasKey.theme`；`MNCThemeKey.themeVersion`, `.uuid`, `.backgroundColor`, `.mainNodes`, `.baseSubnode`, `.subnodeLevels`, `.crossConnections` 等 | 主题资源位置、字段值、与导入包的完整对应关系 |

当前二进制里可找到 `Assets/` 字符串，但这**不能证明** `.mindnode` 内图片必存放于该目录；没有找到可验证的视频包字段/示例。`MindNodeCoreObjC` 中还能看到 `MNCImageFileManager` 文件包装器相关符号，仍不足以重建可写包。

## 与本仓现有测试的边界

仓库 `Tests/MindNodePackageTests.swift` 的 `notes.attachment = "assets/note.bin"` 是**合成夹具**，只验证我们自己的无源读写与保留未知字段，不是原版 MindNode 的图片结构证据。`Tests/MindNodeWriterTests.swift` 只证明生成包可被**我们的** `MindNodeImporter` 回读；既没有原版应用打开验收，也没有媒体、主题或关系的编码验收。

**结论：暂不可把这些键名拼装成媒体/关系/主题 writer。** 保持 Writer 的 `unsupported` 拒绝；视频挂到 `MapNode` 后还需加显式拒绝。原版 v9 包的字段层级、必填默认值、资源引用、安全边界与原版 App 是否接受合成包仍未知。下一步需要获授权的**纯合成**原版 App 生成/打开媒体与关联样本，以及独立重导入对照；当前前台是 Google Chrome、MindNode 进程已存在但不属于本任务，未尝试启动、控制或附加它。

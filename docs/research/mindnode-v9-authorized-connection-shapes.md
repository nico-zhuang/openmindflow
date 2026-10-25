# 获授权 v9 关联字段形状（仅去敏类型）

来源为任务授权的私有 v9 **只读源副本**。每一次读取前均检验同目录 `.owner` 的精确字节、`realpath`、目录 `0700` 与 UID；通过 `openat` + `O_NOFOLLOW` 只读打开包和 `contents.xml`，限制大小。仅在进程内解析 plist，**未输出/复制标题、UUID、原始 plist、节点内容或具体字段值**；未修改源、App 或项目源码。此文也不包含可还原个体内容的关系记录数。

## 原 v9 的可验证类型与层级

`canvas.crossConnections` 是非空 `array<dict>`；观察到的条目具有以下**字段名和类型**。`all` 只表示此授权副本内观察到的记录均有此键，不能推断所有 MindNode v9 文档都必填。

| 路径 | 类型与本副本存在性 |
| --- | --- |
| `connectionID` | `string`（UUID **格式**，不记录其值）；all |
| `endPoints.startNodeID`、`endPoints.endNodeID` | `string`；all。所有观察到的两端标识均可在本包的节点 `nodeID` 集合中解析。 |
| `layout.wayPoints` | 非空 `array<dict>`；all |
| `layout.wayPoints[].wayPointOffset` | `string`，双数花括号元组的**语法类别**；all |
| `arrowStyle.startArrow`、`arrowStyle.endArrow` | `int`；all。值与枚举语义未记录、未证实。 |
| `pathStyle.strokeStyle.color` | `string`，四数花括号元组的**语法类别**；all |
| `pathStyle.strokeStyle.width` | `float`；all |
| `pathStyle.strokeStyle.dash` | `int`；all。值与对应线型未证实。 |
| `title.text` | `string`；all。**仅记录类型，绝无文本内容。** |
| `title.maxWidth`、`title.allowToShrinkWidth`、`title.fontStyle` | `float`、`bool`、`dict`；all。字体字典的内层格式仍须独立验证。 |

层级尤其重要：`startNodeID` / `endNodeID` **不在关系条目顶层**，而在 `endPoints`；`wayPointOffset` 位于 `layout.wayPoints[]`。与安装版 2026.0.2 中同名导出常量的静态线索相符，但上表的层级/类型仅来自这份获授权 v9 副本。

## 不能据此安全写入的部分

单一只读样本不足以判定字段必填规则、空关联、默认箭头和虚线的枚举值、端点顺序/路径几何语义、关系标题的完整富文本格式、ID 引用约束的普适性、原版 App 对**新造**包的接受性。没有写原版包或调用原版 App 作验收；现有 Writer 仍应对非空关系列 `unsupported`，直到自有合成包的原版应用验收和回读可证明无损。也不能以这份关联样本推断图片、视频或主题写法。

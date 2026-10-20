# MindNode 原版编译菜单静态盘点

来源：`/Applications/MindNode.app/Contents/Resources/Base.lproj/MainMenu.nib`；REA CLI `decode-interface-builder` Evidence `ev_8edbba1393dc332a57ef570d62842545cea8a7f7eaedfceee22e29eb84b8f512`；目标 SHA-256 `1e6eda8e897ff844c9dca4cc9dd4f7cba4f573187a53fc0a8d7fc21cf20abe12`。

共识别 220 项有标题的 `NSMenuItem`，其中 104 项带静态按键。主菜单以外还可能存在运行时动态菜单、上下文菜单和键盘事件处理；下表**不证明动作在运行时生效**。同一个组合在不同模式下可能复用。

按 nib 中 `NSMenu`／`NSSubmenu` 引用追踪父菜单（而非按下表对象 ID 猜测归属）：Node 21 项、View 20 项、Edit 19 项、Organize 13 项、File 11 项；还有 Fold、Select、Zoom、Font 等次级菜单。10 项归属未解析，含顶层入口；这些数字是静态条目计数，未去除条件菜单／模式菜单重复项。下表仍按对象 ID 排序，**不是运行时菜单层级或实际可见顺序**；当前保存的 REA 规范化记录把 `NSMenuItems` 指向未展开的集合对象（如 Node 菜单 1521 → 1524），无法从它恢复条目真实排列。抽查 New Child、New Parent、New Main Node、Detach、Indent/Outdent、Fold 和上下移动等条目，其解码 `nibValues` 未给出 `NSAction`/`NSTarget`；这不排除独立连接器或运行时接线，不能从标题推定具体调用。

**需要模式判定的静态复用**：`Tab` 同时列于 Node → New Child（对象 38）与 Organize → Indent（931）；`⌘1` 同时列于 View → Mind Map（1205）及另一个 Styles（1222）。可能由视图模式、焦点或菜单启用状态分流，静态 nib 无法回答。注意**大小写不能折叠**：Edit → Paste as Text 的 `NSKeyEquiv` 为大写 `V`（811），Paste 为小写 `v`（1009），两项掩码虽均为 Command，不能直接断言同键冲突；同理 Organize → Detach Node 的 `D`（850）与 Edit → Duplicate 的 `d`（1305）。表格特意保留原键大小写，Shift 解释尚无运行时对照。

| 对象 ID | 菜单标题（编译默认文本） | 静态快捷键 |
| ---: | --- | --- |
| 19 | New Mind Map | — |
| 32 | New Outline | — |
| 38 | New Child | Tab |
| 50 | Copy Purchase Support Information | — |
| 56 | Edit Title | ⌘Return |
| 66 | Export To | — |
| 75 | Meet the new MindNode | — |
| 84 | Open Quick Entry | — |
| 93 | New Main Node | ⇧Return |
| 103 | Open in Marked | ⌘M |
| 110 | Open Recent | — |
| 119 | Clear Menu | — |
| 126 | New Parent | ⌥Tab |
| 136 | Reset for Onboarding | — |
| 142 | Review on App Store | — |
| 148 | Save… | ⌘s |
| 155 | New Sibling | Return |
| 164 | Bring All to Front | — |
| 170 | Minimize | ⌘m |
| 177 | About MindNode Classic | — |
| 183 | Open… | ⌘o |
| 190 | Close | ⌘w |
| 199 | Page Setup… | ⌘⇧P |
| 206 | Print… | ⌘p |
| 213 | New Mind Map | ⌘n |
| 219 | Revert to Saved | — |
| 227 | Preferences… | ⌘, |
| 234 | Hide MindNode | ⌘h |
| 241 | Quit MindNode | ⌘q |
| 248 | Hide Others | ⌘⌥h |
| 254 | Show All | — |
| 260 | Stop Speaking | — |
| 266 | Start Speaking | — |
| 272 | Copy | ⌘c |
| 279 | Cut | ⌘x |
| 286 | Check Document Now | ⌘; |
| 293 | Delete | Delete |
| 303 | Show Spelling and Grammar | ⌘: |
| 310 | Undo | ⌘z |
| 317 | Find Next | ⌘g |
| 324 | Find… | ⌘f |
| 330 | Jump to Selection | ⌘j |
| 337 | Find Previous | ⌘⇧G |
| 343 | Redo | ⌘⇧Z |
| 350 | Check Spelling While Typing | — |
| 356 | Use Selection for Find | ⌘e |
| 362 | Zoom | ⌘⌥⇧0 |
| 369 | Check Grammar With Spelling | — |
| 375 | Smart Copy/Paste | — |
| 381 | Smart Quotes | — |
| 387 | Smart Links | — |
| 393 | Show Fonts | ⌘t |
| 403 | Bold | ⌘b |
| 410 | Italic | ⌘i |
| 416 | Underline | ⌘u |
| 423 | Show Colors | ⌘C |
| 430 | Copy Style | ⌘⌥c |
| 436 | Paste Style | ⌘⌥v |
| 443 | Use Default | — |
| 449 | Superscript | ⌘⌃+ |
| 456 | Subscript | ⌘⌃- |
| 463 | Raise | — |
| 469 | Lower | — |
| 475 | Use Default | — |
| 480 | Use None | — |
| 486 | Use All | — |
| 492 | Use Default | — |
| 497 | Use None | — |
| 502 | Tighten | — |
| 508 | Loosen | — |
| 514 | Make Upper Case | — |
| 520 | Make Lower Case | — |
| 526 | Capitalize | — |
| 532 | Show Substitutions | — |
| 538 | Text Replacement | — |
| 544 | Correct Spelling Automatically | — |
| 550 | Open User Guide | ⌘? |
| 557 | Align Left | ⌘{ |
| 567 | Align Center | ⌘\| |
| 577 | Justify | ⌘⌥\| |
| 586 | Align Right | ⌘} |
| 596 |     Default | — |
| 602 |     Left to Right | — |
| 608 |     Right to Left | — |
| 614 |     Default | — |
| 619 |     Left to Right | — |
| 624 |     Right to Left | — |
| 629 | Find and Replace… | ⌘⌥f |
| 634 | New Sibling Before | ⌥Return |
| 643 | Get Support | — |
| 649 | Select Previous Main Node | ⌥⌃p |
| 655 | Themes | — |
| 665 | Zoom Out | ⌘- |
| 671 | Force Restore Purchase… | — |
| 677 | Paste and Preserve Style | ⌘⌥V |
| 684 | Move Children to Right/Bottom | — |
| 693 | Move left of sibling | ⌘← |
| 703 | Show Toolbar | ⌘⌥t |
| 709 | All Nodes | — |
| 715 | What’s New | — |
| 721 | Show Emojis | — |
| 732 | Show Photos | — |
| 741 | Show Purchase Screen | — |
| 747 | Deselect All | ⌘A |
| 754 | Data Detectors | — |
| 760 | Zoom to Fit | ⌘= |
| 767 | Smaller | ⌘⌥- |
| 773 | Select All | ⌘a |
| 780 | Enter Full Screen | ⌘⌃f |
| 786 | Center Node | ⌘⌃r |
| 796 | Tags | — |
| 805 | Select All Sibling Nodes | — |
| 811 | Paste as Text | ⌘V |
| 817 | Show Presentation | ⌘⌥p |
| 823 | Sibling Nodes | — |
| 829 | Copy Selected Nodes | ⌘⌥C |
| 835 | New Connection | ⌘l |
| 845 | Meet the new MindNode | — |
| 850 | Detach Node | ⌘D |
| 860 | Notes | — |
| 869 | Add/Remove Boundary | ⌘B |
| 876 | Refresh License… | — |
| 882 | Open Privacy Policy | — |
| 888 | Strikethrough | ⌘⌥u |
| 894 | Select Next Main Node | ⌥⌃n |
| 900 | Zoom to Selection | ⌘* |
| 907 | Edit Notes | ⌘K |
| 914 | Open Linked File… | ⌘⌥⌃k |
| 924 | Mind Map & Outline | ⌘3 |
| 931 | Indent | Tab |
| 940 | Child Nodes | — |
| 947 | All Nodes (Transparent Background) | — |
| 952 | Outdent | ⇧Backtab |
| 962 | Nodes on Same Level | — |
| 967 | Show Stickers | — |
| 976 | Reset Waypoint | ⌘⌥l |
| 985 | Move Children to Left/Top | — |
| 994 | Styles | — |
| 1003 | Show MindNode Tips | — |
| 1009 | Paste | ⌘v |
| 1015 | Size to Fit Content | ⌘⌥= |
| 1024 | Bigger | ⌘⌥+ |
| 1029 | Fold/Unfold | ⌥. |
| 1036 | Unfold All | ⌥⇧. |
| 1044 | Show Image Playground | — |
| 1053 | Delete Image | — |
| 1063 | Duplicate Single Node | ⌘⌥D |
| 1069 | Check/Uncheck Task | ⌘⌃t |
| 1078 | Move right of sibling | ⌘→ |
| 1088 | Show Inspector | ⌘⌥i |
| 1098 | Select All Subnodes | ⌘⌥a |
| 1104 | Selected Nodes | — |
| 1110 | Package | — |
| 1116 | Entire Mind Map | — |
| 1121 | Restore Purchase… | — |
| 1127 | Add/Remove Task | ⌘T |
| 1136 | Open Link… | ⌘⌥k |
| 1147 | Unfold One Level | ⌥⌃. |
| 1155 | Single File | — |
| 1161 | Enter/Leave Focus Mode | ⌘F |
| 1171 | Show Tutorial | — |
| 1177 | Selected Nodes (Transparent Background) | — |
| 1182 | New Outline | ⌘⌃n |
| 1189 | License… | — |
| 1195 | Reset Style | — |
| 1205 | Mind Map | ⌘1 |
| 1212 | Smart Dashes | — |
| 1222 | Styles | ⌘1 |
| 1226 | Layout Children | ⌘⌥r |
| 1235 | Add Link… | ⌘k |
| 1244 | Copy Link for Opening Document | — |
| 1250 | Move above sibling | ⌘↑ |
| 1262 | Balance Children | ⌘⌥b |
| 1268 | Center Main Node | ⌘r |
| 1277 | MindNode Account… | — |
| 1283 | Hide Connections | ⌘⌥⌃l |
| 1293 | Customize Toolbar... | — |
| 1299 | Get MindNode PLUS | — |
| 1305 | Duplicate | ⌘d |
| 1312 | Add/Remove Node Group | ⌘J |
| 1319 | Delete Single Object | ⌥Delete |
| 1325 | Fold All Completed Tasks | — |
| 1331 | Extract Theme… | — |
| 1337 | Actual Size | ⌘0 |
| 1343 | Move below sibling | ⌘↓ |
| 1353 | Sort Children by Task State | ⌘⌥⌃t |
| 1362 | Outline | ⌘2 |
| 1369 | Sort Children Alphabetically | ⌘⌥⌃a |
| 1378 | Zoom In | ⌘+ |
| 1384 | Always Show Toolbar in Fullscreen | — |
| 1398 | MindNode | — |
| 1409 | Services | — |
| 1421 | File | — |
| 1431 | Advanced | — |
| 1439 | Change File Type | — |
| 1448 | Edit | — |
| 1457 | Copy as Image | — |
| 1465 | Select | — |
| 1475 | Find | — |
| 1483 | Spelling and Grammar | — |
| 1492 | Substitutions | — |
| 1501 | Transformations | — |
| 1509 | Speech | — |
| 1517 | Node | — |
| 1529 | Fold | — |
| 1538 | Organize | — |
| 1549 | Format | — |
| 1557 | Font | — |
| 1567 | Kern | — |
| 1575 | Ligatures | — |
| 1583 | Baseline | — |
| 1593 | Text | — |
| 1602 | Writing Direction | — |
| 1610 | Paragraph | — |
| 1615 | Selection | — |
| 1620 | Apply Style To | — |
| 1629 | View | — |
| 1639 | Zoom | — |
| 1650 | Window | — |
| 1661 | Help | — |

限制：菜单本地化标题、可用条件和实际事件路由未核对；这是一份原版安装包的静态清单，不包括原始源码、授权机制、私人导图正文。

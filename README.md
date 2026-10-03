# 月隐 · MOONVEIL

Flutter 经典狼人杀游戏。深蓝月夜、古铜装饰、六名角色的独立立绘、中文离线主持与原创环境音。桌面宽屏采用席位与技能分栏，手机竖屏采用紧凑席位和底部固定操作栏。身份选择使用六名英雄的手办陈列，技能与终局带动作、光效及音效。

## 运行

本项目通过 FVM 固定使用 Flutter **3.47.5 / Dart 3.13.4**。已生成 Android、iOS、macOS、Windows、Linux 和 Web 工程。VS Code 使用 `.vscode/settings.json` 中的项目 SDK 路径。

```sh
fvm use 3.47.5
fvm flutter pub get
fvm flutter run -d macos
# 连接手机后，用 fvm flutter devices 查找设备 ID
fvm flutter run -d <设备ID>
# 安装可从桌面图标独立启动的 iPhone 体验版本
fvm flutter run --release -d <设备ID>
# 浏览器预览
fvm flutter run -d chrome
```

如果本机配置的 pub.flutter-io.cn 镜像出现 525 错误，可仅对当前命令切换官方源：

```sh
PUB_HOSTED_URL=https://pub.dev fvm flutter pub get
```

macOS 最低版本 12，iOS 最低版本 15，Android 最低 API 24。针对本机 Xcode 27，Podfile 已统一设置部署版本。Android 使用 AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20，Java 编译目标为 17，符合项目 Flutter 3.47.5 的最低构建依赖要求。

## 玩法

- **单人历练**：你与离线规则 AI 对战，可以选择身份或随机身份；出局后可继续旁观到终局。AI 发言、查验、指认与投票基于规则和公共线索，并非在线大模型。
- **围炉聚会**：9 或 12 人同屏传递设备。每人独自查看身份，夜晚仅对应角色睁眼；狼人共同商议后由一名队友操作。白天面对面发言，依次秘密投票。必须由玩家共同遵守闭眼与传递规则。
- 9 人局：3 狼、3 民、预言家、女巫、猎人各 1。
- 12 人局：4 狼、4 民、预言家、女巫、猎人、守卫各 1。
- 无警长局可在设置中选择胜负规则（默认经典屠边）：好人放逐全部狼人获胜；屠边规则下狼人消灭全部村民或全部神职获胜；人数制下存活狼人数达到或超过存活好人数时狼人获胜。
- 女巫每夜最多用一瓶药、首夜可自救、解药用尽后不显示刀口；守卫不能连守，同守同救出局；被毒猎人不能开枪；平票无人出局。
- 出局后进入旁观，不能选择投票目标、投票或弃票；只能查看存活玩家的投票结果。
- 每天黎明先显示居中的大字结果公告，离线中文主持按顺序播报平安夜或具体出局号码，再进入白天发言、猎人行动或终局。
- 围炉夜间行动需要两步：提交技能后查看结果，点击「确认行动完成 · 闭眼」才会播报下一角色；下一角色仍需「独自查看」才能打开操作界面。确认状态和私密查验结果会保存。
- 单人 AI 为每位玩家保存六种性格之一及对你的好感（−100～100）。白天结算时，投他 −12、与他同票 +5、弃票/旁观不变；以实际计票结果为准，一轮只结算一次。点席位区的「村庄关系」可查看分数、性格和变化原因，出局 AI 的关系也保留到本局结束。新对局从中立开始，继续存档保留关系。
- AI 发言库含 74 条基础模板，按性格、关系、真实夜间公告、自己查验及上一轮公开投票组合；同类句子避免连续重复。发言会给出暂定投票意向；新证据出现时可以改票。好感适度影响对你的怀疑，明确的查验线索优先，不从好感推断真实阵营。
- 开局选择为六名英雄的透明手办卡，有铜制底座、角色技能、选中光效和鼠标悬停反馈。9 人局隐藏守卫，聚会模式保持随机分配身份。
- 行动演出覆盖狼人蓄势/跃起/扑咬、猎人准备/瞄准/开枪/后坐力、守护、解药、毒药、查验、出局破碎，以及好人/狼人终局。枪口闪光、弹道、受击震动与音效同步，所有演出可跳过；开启系统减少动态效果时缩短并减少移动。
- 演出是已接受行动的视觉反馈；跳过不重复结算。狼人扑咬只表示袭击目标，守卫和解药仍会影响最终结果。未知身份目标使用席位的中立形象，公开猎人或自己的已知角色使用对应角色形象。聚会守护和药剂演出不播放可辨识音效，查验结果不朗读。
- 主菜单内含完整规则、角色技能说明、声音设置、自动存档与最近 30 场战绩。查验等私密信息不会公开播报。

目前是完整离线游戏，未接入网络房间、远程语音聊天或账号服务。

## 素材与声音

- `assets/images/`：内置 ImageGen 生成的村庄背景、六张角色立绘、持枪猎人新立绘、狼人/猎人各三帧动作图及六英雄透明手办图。旧猎人原图保留作参考，运行时使用 `hunter-v2.png`。
- `assets/ART_PROMPTS.md`：实际生成提示词、来源与保存记录。
- `assets/audio/`：35 条中文主持 / 角色故事 / 出局号码音频、1 条原创合成氛围音、9 种原创合成战斗/技能音效及文字稿。主持使用本机 macOS Tingting 语音合成，经 FFmpeg 转成 MP3；运行时直接播放本地音频，无需密钥或联网。
- `tools/make_effects.py`：可重建枪声、扑咬、技能、出局和终局音效，使用原创噪声/振荡器合成，无外部采样。
- `tools/make_audio.py`：在 macOS 上重新合成配音和原创环境音。
- `tools/make_icons.swift`：将游戏自有月徽绘制为桌面、手机、Web 图标。
- `assets/fonts/NotoSerifSC.ttf`：Google Fonts 思源宋体简体中文，许可见同目录 `OFL.txt`。
- UI 图形由 Flutter Canvas 绘制，使用 Flutter 自带 Material Icons。

## 检查与构建

```sh
fvm flutter analyze
fvm flutter test
fvm flutter drive -d macos --target integration_test/audio_smoke_test.dart --driver tools/audio_driver.dart
fvm flutter build macos --release
# 重新封装本地签名并打包 macOS 体验包
./tools/package_macos.sh --skip-build
fvm flutter build apk --release
fvm flutter build ios --release --no-codesign
```

本机 Xcode 27 的 `lipo -verify_arch` 多架构检查异常，`tools/xcode27/lipo` 按架构分别验证，其他操作转交系统 lipo；仅 macOS 工程自己的 Flutter 构建阶段使用，不修改 Flutter SDK 或系统工具。macOS Release 保持 arm64 与 x86_64 双架构。`tools/package_macos.sh` 会重新签名 App.framework 和成品应用，再验证完整封装；解决增量构建替换框架后主应用仍保留旧封装签名的情况。生成包为本机 ad-hoc 签名。

`flutter test` 包含技能限制、夜晚结算、猎人链式结算、平票、存档恢复、200 场自动对局、320/390 像素竖屏、844 像素横屏、1360 像素桌面布局、同屏隐私遮挡与开局到存档恢复的操作链路检查。原生音频测试会验证中文配音、16 条公告片段和九种音效能解码播放，并实际播放包含两个出局号码的连续播报、取消、快速切换阶段与重播。Apple 平台固定 `audioplayers_darwin 6.3.0`，避开 6.4+ 短音频连续切换的 AVPlayer 回调问题；主持源准备串行执行，使用停止保留模式，防止旧音频释放回调干扰新片段。

`test/render_preview_test.dart` 使用真实字体和图片生成 Flutter 实际渲染截图，保存在 `output/screenshots/`。手办预览见 `heroes-*.png`，动画关键帧见 `scene-*.png`。

iOS 无签名构建产物不能直接安装到手机。要真机运行，请在 Xcode 选择你自己的开发团队，再使用 `fvm flutter run`；Windows / Linux 工程需在相应系统构建和验证。

### iOS 27 启动兼容

Xcode 27 / iOS 27 要求应用采用 UIScene 生命周期。旧 Flutter 3.27 模板没有 Scene Manifest，会以 `NoSceneLifecycleAdoption` / `SIGTRAP` 启动崩溃。项目已迁移 `Info.plist` 与 `AppDelegate`，插件在隐式引擎初始化时注册，使用 Flutter 自带 `FlutterSceneDelegate` 管理窗口。官方说明：[UIScene adoption](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)。

终端请用 `fvm flutter …` 或 `./tools/flutterw …`，避免 PATH 中的旧全局 `flutter`。VS Code 如已打开旧 SDK，请重新加载窗口；其他编辑器将 Flutter SDK 指向 `.fvm/flutter_sdk`。Debug 适合调试器连接运行，日常从 iPhone 图标启动请安装 Release 版本。

本机无线 Debug 启动后未发现 VM Service，终止调试会话时记录到 JIT 的 `EXC_BAD_ACCESS / SIGBUS`。因此不把无线 Debug 的稳定性标记为通过；需要热重载时建议使用 USB，并允许手机上的本地网络权限。VS Code 第一个启动配置为 Release 真机体验，第二个保留 Debug。

## 本次验证

初版（Flutter 3.27.1）：静态检查、21 项自动测试及 macOS 原生音频测试通过。macOS 双架构 Release、Android Release APK、iOS 无签名 Release 和 Web Release 构建成功。该版本的验证记录保留在 `output/verification.json` 的 `initial_release` 中，当前 macOS/Android 发布包已替换为 3.47.5 新版。Android 包用本机调试密钥签名，适合本地体验；发布到应用商店前需要配置正式签名。Windows/Linux 运行尚未验证。

升级后（Flutter 3.47.5）：静态检查无问题、21 项自动测试通过、macOS 原生音频测试通过、macOS Release 构建成功。iOS 27 真机签名构建、安装、Release 启动和独立冷启动成功，并检查启动后进程。无线 Debug 热重载尚未验证通过；具体限制见上面的 iOS 27 说明。

玩法修正后：37 项测试通过，新增死亡后投票拦截、旧存档无效选票清理、围炉角色确认交接、预言家私密结果恢复、平安夜/出局公告和 320/390 竖屏、844 横屏、1360 桌面布局验证。公告渲染截图见 `output/screenshots/dawn-*.png`。

视觉与社交增强后（Flutter 3.47.5）：49 项自动测试通过，静态检查无问题。新增好感按实际选票结算、弃票/旁观不改变好感、明确查验优先、关系存档兼容、句式避免连续重复、关系面板窄屏布局、演出身份保护、药剂音效隐私、枪声音效仅触发一次与减少动态效果验证。macOS 原生音频实际通过连续播报、取消、快速阶段切换、重播和音效测试。手办、技能与出局/终局截图覆盖 390 竖屏、844 横屏、1360 桌面。最终 macOS 双架构、iOS 签名 Release、Android APK 和 Web Release 构建均通过；macOS 发布包签名重新封装并验证，Android 包含新手办和枪声音效。新版已安装到 iPhone；本轮设备处于锁屏状态，尚未验证这份最终版本的启动，不沿用此前版本的真机启动结果作为本轮验证。

构建包：`output/releases/moonveil-macos.zip`、`output/releases/moonveil-android.apk`。详细验证与文件摘要见 `output/verification.json`。

## 代码

- `lib/game/engine.dart`：独立规则状态机、规则 AI 与 JSON 存档。
- `lib/game/ai_personality.dart`：AI 性格、好感、公开票型记忆与离线语言库。
- `lib/game/cinematic_event.dart`：演出事件与目标身份可见性。
- `lib/ui/cinematic_overlay.dart`：序列帧动作、粒子、光效与音效时点。
- `lib/ui/hero_selector.dart`：英雄手办身份选择。
- `lib/game/roles.dart`：角色、技能文案和规则。
- `lib/ui/kit.dart`：月徽、切角金属按钮、装饰边框、角色卡。
- `lib/ui/game_screen.dart`：对局、秘密交接、技能操作、发言与结算。
- `lib/services/audio_director.dart`：离线中文主持、音乐循环、音量与语音压低背景音。
- `lib/main.dart`：主菜单、图鉴、开局、规则、战绩与自动保存。

# Android 墨水屏精简与美化（DSH Skill）

一个可直接被 AI 代理调用、也可纯手工执行的方案，用来把一台国产安卓墨水屏设备
整理成「安静、黑白、够用」的状态：

- 按类别甄别并**经用户确认后**禁用内置臃肿应用（应用商店、书城、打印服务、产线测试、OTA 等）
- 安装墨水屏专用桌面（默认 [InkBoard](https://github.com/kuaner/inkBoard)）
- 安装 [Trime/同文输入法](https://github.com/osfans/trime) + 微软双拼 + **纯黑白主题**

全程只用 `adb`：不需要 root、不刷机、不清数据，每一步都可回滚。

![InkBoard 桌面](docs/inkboard-home.png)

![纯黑白键盘](docs/trime-bw.png)

## 为什么需要它

市面上大多数教程只给一串 `pm disable` 命令，照着敲很容易把
`providers.*`、`webview`、`packageinstaller` 一起禁掉，然后设备装不了应用、
存储读不出来。另外 Trime 自带主题是彩色的，官方包也**不含双拼**——
这两件事都需要一份可复用的、踩过坑的说明。

这个仓库把这些经验固化下来：

- **分级禁用清单**（安全 / 需确认 / 绝不）：见 [`references/package-triage.md`](references/package-triage.md)
- **纯黑白主题生成器**：从任意 Trime APK 重新生成，而不是手改 YAML
- **可缓解的 ADB 掉线处理**：`adbd` 被杀后如何切到 Wi-Fi 调试继续
- **桌面 / 输入法替换的正确顺序**（先装新、验证、再禁旧）

## 快速开始

### 1. 准备

打开设备「开发者选项 → USB 调试」，连接数据线，确认：

```bash
adb devices -l          # 状态必须是 device（不是 unauthorized / offline）
```

### 2. 探测与保活

```bash
./scripts/eink-adb.sh probe      # 或 Windows: .\scripts\eink-adb.ps1 probe
./scripts/eink-adb.sh persist
```

### 3. 选应用、再禁用

```bash
./scripts/eink-adb.sh list                       # 导出到 packages-<型号>.txt
./scripts/eink-adb.sh disable com.moan.appstore com.duokan.einkreader
./scripts/eink-adb.sh enable  com.moan.appstore  # 随时回滚
```

> 建议先把要禁用的包名写进 `disabled-<型号>.txt`，然后
> `enable-file disabled-EPD103.txt` 一条命令还原。

### 4. 换桌面

```bash
./scripts/eink-adb.sh install InkBoard-v1.0.5.apk
./scripts/eink-adb.sh home ai.openduo.inkboard/.MainActivity
./scripts/eink-adb.sh shot home.png
```

### 5. 换输入法 + 黑白主题

```bash
# 1) 装 Trime（选对 ABI），设为默认
adb shell ime enable com.osfans.trime/.ime.core.TrimeInputMethodService
adb shell ime set    com.osfans.trime/.ime.core.TrimeInputMethodService

# 2) 首次启动时在向导里选「外部数据目录」→ rime/
RIME=/sdcard/Android/data/com.osfans.trime/files/rime

# 3) 推入双拼方案与黑白主题
adb push assets/trime/double_pinyin_mspy.schema.yaml $RIME/
adb push assets/trime/default.custom.yaml            $RIME/
adb push assets/trime/double_pinyin_mspy.custom.yaml $RIME/
adb push "assets/trime/纯黑白.trime.yaml"            $RIME/

# 4) 键盘样式 → 主题 → 纯黑白；再点「部署」
adb shell am force-stop com.osfans.trime
```

换一个 Trime 版本时，不要手改主题，重新生成：

```bash
python3 scripts/build-trime-bw-theme.py --apk trime.apk --out 纯黑白.trime.yaml
```

### 6. 体检

```bash
./scripts/eink-adb.sh health
```

## 作为 DSH Skill 使用

把整个目录放进技能目录即可被自动发现：

| 作用域 | 路径 |
|---|---|
| 用户级 | `~/.dsh/skills/android-eink-setup/` |
| 项目级 | `<项目根>/.dsh/skills/android-eink-setup/` |
| 兼容 Claude 风格 | `~/.agents/skills/android-eink-setup/` |

```bash
# Windows
xcopy /E /I android-eink-setup "%USERPROFILE%\.dsh\skills\android-eink-setup"
# macOS / Linux
cp -r android-eink-setup ~/.dsh/skills/
```

新开会话后，代理会在技能目录里看到 `android-eink-setup`，并在你说
「帮我精简这台墨水屏、换个桌面」时自动加载它。

## 仓库结构

```
android-eink-setup/
├── SKILL.md                        # 给 AI 的操作流程（含踩坑点）
├── references/
│   ├── package-triage.md           # 系统包分级清单
│   ├── launchers.md                # 墨水屏桌面横评与切换
│   └── trime.md                    # Trime 数据目录、双拼、主题机制
├── scripts/
│   ├── eink-adb.ps1                # Windows 助手
│   ├── eink-adb.sh                 # macOS / Linux 助手
│   └── build-trime-bw-theme.py     # 黑白主题生成器
├── assets/trime/
│   ├── 纯黑白.trime.yaml
│   ├── double_pinyin_mspy.schema.yaml
│   ├── double_pinyin_mspy.custom.yaml
│   └── default.custom.yaml
└── docs/                           # 截图
```

## 已验证设备

| 设备 | 系统 | 结果 |
|---|---|---|
| 墨案 W7（EPD103，10.3"） | Android 8.1 / API 27 / armeabi-v7a | 24 个内置应用禁用、InkBoard 桌面、Trime 微软双拼 + 纯黑白主题，全部正常 |

其它 Allwinner / Rockchip 平台的国产墨水屏（文石、掌阅、汉王、海信、多看）思路一致，
包名不同而已——用 `references/package-triage.md` 的规则去归类，不要照抄包名。

## 风险与边界

- **禁用 OTA 组件后收不到系统更新**，需要时用 `enable` 恢复。
- **禁用输入法前必须先装好替代输入法并验证能打字**，否则会失去输入能力。
- 不提供刷机、root、修改系统分区的脚本；本仓库只做 `pm disable-user` 级别的改动。
- 部分机型（尤其是带手写笔的）在禁用厂商服务后可能丢失笔迹优化，遇到问题按清单回滚。

## 许可

MIT。主题与方案文件可自由修改再分发；InkBoard、Trime 分别遵循其自身许可证。

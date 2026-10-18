---
name: Computer Use (Windows)
description: 像人一样操控 Windows 桌面应用：列出窗口、截图、读取 Windows UI Automation 元素树、点击、输入、快捷键、滚动、拖拽。纯 Windows UIA/Win32 实现。
---

# Computer Use (Windows)

用这个技能操控本机 Windows 桌面。完全使用 Windows 自带能力，**不依赖任何外部运行时**：

- **UIA（默认）**：`uia.mjs` + `uia.ps1`
  - Windows UI Automation 元素树
  - 元素索引、按元素点击、`set_value`、Invoke/Select/Expand 等
  - PowerShell/Win32 截图、鼠标、键盘
  - 没有常驻进程，没有额外覆盖层
- **Native（兜底）**：`native.ps1`
  - 浏览器窗口、画布、自绘控件
  - 截图 + 窗口相对坐标点击、键盘、滚动、拖拽

依赖：Windows 10/11、PowerShell 5.1、Node 18+。

## 功能取舍

- 元素树 + 元素索引 + `click` / `set_value` / `Invoke` / `Select` / `Expand` / `Toggle` / `ScrollIntoView` / `Focus`
- 标准 Win32 控件没有 pattern 时，用元素矩形中心鼠标点击兜底
- 窗口截图 + 窗口相对坐标兜底
- state 文件、元素路径重新定位、过期后强制刷新
- 应用清单 `start-apps` + `launch`
- 可选全屏上下文截图（`state --full-screen`）
- 安全边界与“先观察再动作”的流程

不包含：常驻 daemon、覆盖层、音频录制。  
遮挡窗口截图用 `PrintWindow` 尽力截取，必要时把窗口带到前台。

---

## 0. 先读：安全边界

你是用户桌面的代理。默认假设用户正看着屏幕，鼠标和键盘会被真实移动/输入。

**必须先征得用户明确同意，才能做以下事情：**

- 删除、移动、覆盖文件，或清空回收站
- 发送消息、邮件、评论，提交表单，发布内容
- 购买、支付、转账、订阅，或修改账户/密码/权限
- 修改系统设置、安装/卸载软件、改注册表、关防火墙
- 关闭有未保存内容的工作，或强制结束进程
- 输入密码、2FA 验证码、API key、身份证/银行卡/住址等敏感信息
- 接受 UAC、杀毒软件、浏览器安全警告、证书警告
- 访问网银、密码管理器、医疗/财务等敏感应用（除非用户明确要求，并优先让用户自己操作）

**绝对不要：**

- 绕过 UAC、Windows 安全机制、浏览器安全提示、登录/验证码
- 把屏幕上的密码、密钥、个人信息写进回答或日志
- 在用户没要求时删除/上传文件
- 用 Computer Use 执行本来可以用 shell/CLI/API 完成的任务（优先用专用工具）

**独立后端没有全局 Esc 监听。** 如果用户说停或表现出要接管，立即停止发送新的动作，不要继续尝试。

---

## 1. 快速开始

```powershell
$CU = "$HOME\.config\opencode\skills\computer-use\scripts\uia.mjs"

# 检查 UIA 和 PowerShell
node $CU doctor

# 找窗口（uia.mjs 列出当前打开的窗口）
node $CU windows
node $CU windows --title "记事本"
node $CU apps --running

# 找已安装应用（Start Menu 清单）
node $CU start-apps --app "记事本"
node $CU launch --app "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
```

`windows` 返回窗口 `id`（HWND）、`app`（进程名）、`title`、位置和大小。

选择窗口时：

- 只有一个匹配：直接用 `--title` / `--app`
- 多个匹配：用 `--window <id>`，不要猜
- 目标应用没开：先 `launch`，再 `windows`

```powershell
node $CU launch --command "notepad.exe"
node $CU launch --app "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
```

`apps` 在独立后端里只列出正在运行的窗口（按进程分组），不是完整的“已安装应用”清单。

---

## 2. 观察：state

```powershell
$OUT = "$env:TEMP\opencode-cua\job1"
node $CU state --window 123 --out-dir $OUT
```

`state` 会输出：

1. 一段 JSON 元数据（窗口、`stateId`、截图、`stateFile`、`focusedElement`、`elementCount` 等）
2. `--- ACCESSIBILITY TREE ---` 后面的原始 UIA 元素树

元素树每行开头的数字就是元素索引：

```text
0 Window "运行" Class: #32770
  4 Pane ID: 12298 Class: ComboBox
    5 Pane "notepad" ID: 1001 Class: Edit
  7 Pane "取消" ID: 2 Class: Button
```

**截图**：

- `screenshots[]` 里每项有 `path`、`width`、`height`、`isWindow`、`originX`、`originY`。
- 用 `read` 工具读取 `path` 指向的图片。
- 当前 UIA 后端只返回目标窗口截图（`isWindow: true`）。
- 如果图片显示被缩放，用元数据里的 `width`/`height` 做比例换算。

**元素树**：

- 用 `read` 工具读 `treePath`，或直接在输出里看。
- 如果 `treeTruncated: true`，完整树在 `treePath`。
- 元素索引只对产生它的那次 `state` 有效。动作时把 `stateFile` 传给 CLI；UIA 后端会按 state 文件里的元素路径重新定位。
- 如果 UI 已经变化，动作会报 “element is no longer present; refresh state”；重新 `state` 即可。
- UIA 树对部分 Win32 控件只显示 `Pane`，但 `name` / `ID` / `Class` 仍然可用；点击和输入通常仍然能工作。
- 如果元素树为空、太大或不稳定（浏览器、画布、游戏），用 `--backend native` 看截图、用坐标。

**常用选项**：

```powershell
node $CU state --window 123 --no-text          # 只看截图
node $CU state --window 123 --no-screenshot    # 只看元素树
node $CU state --window 123 --max-elements 300 # 限制树大小
node $CU state --window 123 --full-screen      # 额外保存一张全屏上下文截图
node $CU state --window 123 --backend native   # 强制只看截图
```

---

## 3. 动作

动作前先 `state`，动作后再 `state` 验证。不要复用旧索引。

### 3.1 点击元素（首选）

```powershell
node $CU click --state-file "$OUT\state.json" --element 7
node $CU click --state-file "$OUT\state.json" --element 32 --button right
node $CU click --state-file "$OUT\state.json" --element 12 --count 2
```

- UIA 会读取元素的屏幕矩形，把鼠标移动到中心点击。
- 如果元素没有有效矩形，会尝试 `Invoke` / `Select` / `Toggle` / `Expand`。
- 对 Win32 按钮、列表项、树节点、菜单通常都有效。
- 如果点击后 UI 没反应，重新 `state`；仍不行就用截图坐标 + `--backend native`。

### 3.2 填写文本（首选）

```powershell
node $CU set-value --state-file "$OUT\state.json" --element 5 --value "notepad"
```

- 优先使用 UIA `ValuePattern`。
- 如果元素不支持 `ValuePattern`，会自动退化为：点击元素中心 → `Ctrl+A` → 输入文本。
- 会替换整个值，不是追加。
- 多行/中文请用 PowerShell 变量或 here-string 传给 `--value`，不要直接管道给 `--stdin`（Windows PowerShell 5.1 的管道默认可能把中文变成 `?`）：

```powershell
$value = @"
第一行
第二行
"@
node $CU set-value --state-file "$OUT\state.json" --element 5 --value $value
```

### 3.3 输入文本（当前焦点）

```powershell
node $CU type --window 123 --text "hello"
node $CU type --window 123 --x 400 --y 300 --text "hello"   # 先点一下再输入

$text = @"
第一行
第二行
"@
node $CU type --window 123 --text $text
```

- 先确保目标输入框有焦点（`set-value` 或 `click`）。
- `type` 走 Win32 Unicode 输入，不受输入法候选框影响；纯文本优先用 `set-value`。
- **中文/多行优先用 `--text` 传 PowerShell 变量或 here-string**，本机验证可用。
- 如果一定要用 `--stdin`，先设置 `$OutputEncoding = [System.Text.Encoding]::UTF8`，否则 Windows PowerShell 5.1 管道可能把中文变成 `?`。
- 如果键盘输入没反应，先用 `click` 点一下目标窗口内部再发。

### 3.4 键盘快捷键

```powershell
node $CU key --window 123 --key "Control_L+s"
node $CU key --window 123 --key "Control_L+Shift_L+Escape"
node $CU key --window 123 --key "Alt+F4"
node $CU key --window 123 --key "Win+r"
node $CU key --window 123 --key "Tab"
node $CU key --window 123 --key "Return"
```

- 独立后端使用 Win32 虚拟键；支持 `Ctrl`/`Control_L`、`Shift`、`Alt`、`Win`、F1–F24、方向键、`KP_0` 等。
- 不要用 `type` 模拟快捷键；用 `key`。

### 3.5 坐标点击 / 滚动 / 拖拽（Native）

用于没有元素索引的画布、网页、游戏、自绘控件。

```powershell
# 坐标是窗口相对坐标，基于 state 截图
node $CU click --window 123 --x 400 --y 300
node $CU click --window 123 --x 400 --y 300 --button right

node $CU scroll --window 123 --x 400 --y 300 --dy 600
node $CU scroll --window 123 --x 400 --y 300 --dx -300

node $CU drag --window 123 --from-x 200 --from-y 300 --to-x 500 --to-y 300
```

- 点击前先看截图，确认坐标落在正确控件上。
- 坐标系原点在窗口左上角（含标题栏）。
- 滚动 `dy` 正数向下，负数向上；`dx` 正数向右。
- 拖拽请慢慢来；不要在未确认目标时拖文件。

### 3.6 其他

```powershell
node $CU activate --window 123
node $CU action --state-file "$OUT\state.json" --element 12 --action "Expand"
```

`action` 支持 `Invoke`、`Select`、`Expand`、`Collapse`、`Toggle`、`ScrollIntoView`、`Focus`、`Close`。  
UIA 树里没有列出对应 pattern 的元素不要猜；标准 Win32 按钮直接用 `click` 点元素中心。

---

## 4. 标准工作流

1. **确认目标**：`windows` / `apps`，说出要操作哪个应用/窗口。
2. **观察**：`state`，读截图 + UIA 元素树。
3. **选动作**：
   - 可编辑字段 → `set-value`
   - 按钮/菜单/列表项 → `click --element`
   - 键盘导航 → `key`
   - 焦点输入 → `type`
   - 无元素/画布/网页 → `click --x --y` + `--backend native`
4. **小步执行**：一次做一组相关动作，不要盲点一长串。
5. **验证**：再 `state`，确认 UI 真的变成目标状态。不要用“动作返回 ok”当作完成。
6. **失败就刷新**：重新 `state`，不要复用旧坐标/索引。
7. **收尾**：撤销测试输入、关闭测试窗口、清理临时目录，确认没有未保存内容。

**判断完成的标准**：目标页面/文件/消息/设置已经明确出现在最新截图或元素树里。仅仅“点了按钮”不算完成。

独立 UIA 后端**没有常驻 helper，也没有覆盖层**，不需要按 Esc 退出。

---

## 5. 浏览器与 Native 兜底

浏览器、PDF 阅读器、Canvas、视频控件通常没有稳定/可用的 UIA 树。优先：

1. 能用 `webfetch`、Playwright MCP、浏览器插件/API 完成的，优先用它们。
2. 必须点网页 UI 时，用 `--backend native` + 截图 + 坐标/键盘。
3. 不要用 Native 绕过登录、验证码、证书警告或浏览器安全提示。

Native 示例：

```powershell
node $CU state --title "Edge" --backend native --out-dir "$env:TEMP\opencode-cua\web1"
node $CU click --title "Edge" --x 400 --y 300
node $CU type --title "Edge" --text "hello"
node $CU key --title "Edge" --key "Control_L+l"
```

Native 限制：

- 没有元素树，不能用 `--element`
- 截图是可见窗口；被遮挡时先 `activate`
- 输入会移动真实鼠标/键盘，执行期间不要碰电脑

---

## 6. 输出格式与错误码

大多数命令输出纯 JSON。`state` 是“JSON 元数据 + 原始元素树”：

```json
{
  "ok": true,
  "backend": "uia",
  "window": { "id": 123, "app": "explorer", "title": "..." },
  "stateId": 1792347835,
  "screenshots": [
    { "path": "C:\\...\\native.png", "width": 856, "height": 701, "isWindow": true }
  ],
  "stateFile": "C:\\...\\state.json",
  "focusedElement": "ListItem 005.png",
  "elementCount": 179
}
--- ACCESSIBILITY TREE ---
...
--- END ACCESSIBILITY TREE ---
```

常见错误：

| 错误码 | 含义 | 处理 |
| --- | --- | --- |
| `AMBIGUOUS_WINDOW` | 多个窗口匹配 | 用 `--window <id>` |
| `NO_WINDOW` | 没匹配到窗口 | 先启动应用，或换 `--title` |
| `UIA_ERROR` | UIA 读取/动作失败 | 重新 `state`，或 `--backend native` |
| `BAD_STATE_FILE` | state 文件读不了 | 重新 `state` |
| `ELEMENT_NOT_FOUND` / “element is no longer present” | 元素已变化 | 重新 `state` |
| `VALUE_UNSUPPORTED` | 元素不支持 ValuePattern | 自动退化；若仍失败用 click+type |
| `NATIVE_ELEMENT_UNSUPPORTED` | Native 不支持元素点击 | 用 `--x/--y` 坐标 |

---

## 7. 排障

```powershell
node $CU doctor
```

- **UIA 不可用**：运行 `doctor`，确认 PowerShell 5.1 和 `UIAutomationClient` 可用（Windows 10/11 自带）。
- **元素树为空/太少**：部分 Win32 控件只显示 `Pane`；用截图和坐标。
- **元素点击没反应**：重新 `state`；仍不行就改用截图坐标。
- **键盘/快捷键没反应**：先 `click` 点一下目标窗口内部（或 `activate`）。Windows 的前台锁定可能让 `SetForegroundWindow` 失败。
- **中文输入变成 `?`**：用 `--text` 传 PowerShell 变量/here-string；不要直接管道给 `--stdin`。
- **窗口最小化**：`state` 和动作会自动激活；仍失败时用 `activate`。
- **截图全黑**：先 `activate`；某些受保护窗口无法截图，改用应用自身的导出/另存功能。

临时文件在 `%TEMP%\opencode-cua`。任务结束后可以手动删除本次的 `--out-dir`。

---

## 8. 命令速查

```powershell
$CU = "$HOME\.config\opencode\skills\computer-use\scripts\uia.mjs"

node $CU doctor
node $CU windows [--title Q] [--app Q]
node $CU apps [--running]
node $CU start-apps [--app Q]
node $CU state [--window ID | --title Q | --app Q] [--out-dir DIR] [--full-screen]
node $CU click [selector] (--element N | --x N --y N) [--button left|right|middle] [--count N]
node $CU set-value [selector] --element N (--value TEXT | --stdin)
node $CU type [selector] (--text TEXT | --stdin) [--x N --y N]
node $CU key [selector] --key "Control_L+s"
node $CU scroll [selector] --x N --y N --dy N [--dx N]
node $CU drag [selector] --from-x N --from-y N --to-x N --to-y N
node $CU action [selector] --element N --action "Expand"
node $CU activate [selector]
node $CU launch (--app APP_ID | --command CMD)
node $CU screenshot [selector] --out PATH
```

选择器：`--window <id>`、`--title <substring>`、`--app <substring>`、`--state-file <path>`。

全局选项：`--backend uia|native`、`--out-dir`、`--no-text`、`--no-screenshot`、`--no-activate`、`--max-elements`、`--max-text`、`--timeout`。

---

## 9. 最后提醒

- 这是真实电脑，不是沙盒。宁可多问一句，不要猜。
- 任何不可逆操作前，先停下来向用户确认。
- 能用专用工具（shell、文件 API、浏览器工具）就不要点 GUI。
- 每次动作后看最新状态；不要相信“应该已经成功了”。
- 完成后用一句话告诉用户：操作了哪个应用、做了什么、结果如何、有没有留下未保存内容。

# computer-use-skill

An OpenCode skill for controlling Windows desktop apps like a human: inspect windows, capture screenshots and UI Automation trees, click, type, press hotkeys, scroll, and drag.

Windows 桌面自动化 skill：列窗口、截图、读取 UI Automation 元素树、点击、输入、快捷键、滚动、拖拽。

**Pure Windows implementation:** Windows UI Automation plus PowerShell/Win32. No external runtime is required.

## Backends

- **UIA (default)** — `uia.mjs` + `uia.ps1`
  - Windows UI Automation accessibility tree with element indexes
  - element clicks, `set_value`, Invoke/Select/Expand/Collapse/Toggle/ScrollIntoView
  - screenshots and native mouse/keyboard input
  - no daemon, no overlay
- **Native (fallback)** — `native.ps1`
  - browser windows, canvas, games, custom-drawn controls
  - screenshots and window-relative coordinate clicks
  - keyboard, Unicode text, scrolling, dragging

## Requirements

- Windows 10/11
- PowerShell 5.1 (built in)
- Node.js 18+

## Install

Copy this directory to your OpenCode global skills directory:

```powershell
$dest = "$HOME\.config\opencode\skills\computer-use"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item .\SKILL.md $dest
Copy-Item .\scripts $dest -Recurse -Force
```

Then start a new OpenCode session (or reload the current one) and ask it to use `@computer-use`.

## Quick start

```powershell
$CU = "$HOME\.config\opencode\skills\computer-use\scripts\uia.mjs"

node $CU doctor
node $CU windows
node $CU start-apps --app "Notepad"
node $CU state --title "Notepad" --out-dir "$env:TEMP\opencode-cua\job1"
node $CU click --state-file "$env:TEMP\opencode-cua\job1\state.json" --element 5
node $CU set-value --state-file "$env:TEMP\opencode-cua\job1\state.json" --element 5 --value "hello"
node $CU type --window 123 --text "hello"
node $CU key --window 123 --key "Control_L+s"
```

See `SKILL.md` for the full command reference, workflow, safety policy, and troubleshooting.

## Notes

- The UIA tree is built with `ControlViewWalker`. Some Win32 controls appear as `Pane`; names and automation IDs still help. Use screenshot coordinates if an element click does nothing.
- Browser content may have no stable UIA tree. Prefer browser tools, or use `--backend native` with screenshots and coordinates.
- Use `--text` with a PowerShell variable/here-string for Unicode or multiline input. Piping to `--stdin` may mangle non-ASCII text unless UTF-8 output encoding is set.
- Element indexes are valid only for the state file that produced them. Run `state` again after UI changes.
- `state --full-screen` also saves a full-screen context screenshot; the window screenshot is marked `isWindow: true`.
- Coordinate actions affect the real mouse and keyboard; do not touch the computer while they run.

## Layout

```text
.
├── SKILL.md
└── scripts/
    ├── uia.mjs          # UIA CLI
    ├── uia.ps1          # Windows UI Automation worker
    ├── windows-lib.mjs  # PowerShell bridge helpers
    ├── native.ps1       # native screenshots/input
    └── cu.cmd           # default launcher
```

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import {
  SHOTS_DIR,
  SCRIPT_DIR,
  STATE_DIR,
  ensureDir,
  runNative,
  runPowerShellScript,
} from "./windows-lib.mjs";

const VERSION = "1.0.0";
const UIA_SCRIPT = join(SCRIPT_DIR, "uia.ps1");

const HELP = `
Computer Use for Windows (UI Automation + native input)
Usage: node uia.mjs <command> [options]

Pure Windows UI Automation + PowerShell/Win32. No external runtime required.

Commands:
  doctor                     Check UIA assemblies and native input
  windows [--app Q] [--title Q]
  apps [--app Q]                     Running windows grouped by process
  start-apps [--app Q]               Installed Start Menu apps (Name / AppID)
  state [selector] [--out-dir DIR] [--no-text] [--no-screenshot] [--no-activate] [--max-elements N]
  click [selector] (--element N | --x N --y N) [--button left|right|middle] [--count N]
  set-value [selector] --element N (--value TEXT | --stdin)
  action [selector] --element N --action "Invoke|Select|Expand|Collapse|Toggle|ScrollIntoView|Focus"
  type [selector] (--text TEXT | --stdin) [--x N --y N]
  key [selector] --key "Control_L+s"
  scroll [selector] --x N --y N --dy N [--dx N]
  drag [selector] --from-x N --from-y N --to-x N --to-y N
  activate [selector]
  launch (--app APP_ID | --command COMMAND)
  screenshot [selector] --out PATH [--no-activate]

Selector:
  --window <id>      Window id/HWND from windows or state output
  --title <text>     Case-insensitive title substring
  --app <text>       Case-insensitive process/title substring
  --state-file PATH  Reuse a state file from the state command

Options:
  --backend uia|native   uia (default) uses UI Automation; native is screenshot/coordinates only
  --out-dir DIR          Directory for state screenshots and state.json
  --out PATH             Screenshot path for the screenshot command
  --no-text              Skip UI Automation text (native screenshot only)
  --no-screenshot        Skip screenshot capture
  --full-screen          Also capture a full-screen context screenshot
  --no-activate          Do not bring the target window to the foreground
  --max-elements N       Max UIA elements to walk (default 800)
  --max-text N           Max accessibility text characters returned (default 30000)
  --timeout MS           Timeout for PowerShell/UIA calls (default 60000)
  --help                 Show this help

Examples:
  node uia.mjs doctor
  node uia.mjs windows
  node uia.mjs state --title "Notepad" --out-dir "$env:TEMP\opencode-cua\job1"
  node uia.mjs click --state-file "$env:TEMP\opencode-cua\job1\state.json" --element 32
  node uia.mjs set-value --state-file "$env:TEMP\opencode-cua\job1\state.json" --element 4 --value "hello"
  node uia.mjs type --window 123 --text "hello"
  node uia.mjs key --window 123 --key "Control_L+s"
`;

const { values: opts, positionals } = parseArgs({
  allowPositionals: true,
  strict: false,
  options: {
    window: { type: "string" },
    app: { type: "string" },
    title: { type: "string" },
    "state-file": { type: "string" },
    "state-id": { type: "string" },
    "out-dir": { type: "string" },
    out: { type: "string" },
    "no-text": { type: "boolean", default: false },
    "no-screenshot": { type: "boolean", default: false },
    "full-screen": { type: "boolean", default: false },
    "no-activate": { type: "boolean", default: false },
    "max-elements": { type: "string" },
    "max-text": { type: "string" },
    backend: { type: "string", default: "uia" },
    timeout: { type: "string" },
    element: { type: "string" },
    x: { type: "string" },
    y: { type: "string" },
    button: { type: "string" },
    count: { type: "string" },
    text: { type: "string" },
    stdin: { type: "boolean", default: false },
    key: { type: "string" },
    dx: { type: "string" },
    dy: { type: "string" },
    "from-x": { type: "string" },
    "from-y": { type: "string" },
    "to-x": { type: "string" },
    "to-y": { type: "string" },
    value: { type: "string" },
    action: { type: "string" },
    command: { type: "string" },
    running: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
});

const command = positionals[0] || "";
const backend = String(opts.backend || "uia").toLowerCase();
const timeoutMs = Number(opts.timeout || 60000);
const includeText = !opts["no-text"] && backend !== "native";
const includeScreenshot = !opts["no-screenshot"];

if (opts.help || !command) {
  console.log(HELP.trim());
  process.exit(0);
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function defaultOutDir() {
  return join(SHOTS_DIR, timestamp());
}

function defaultShotPath() {
  ensureDir(STATE_DIR);
  return join(SHOTS_DIR, timestamp(), "screenshot.png");
}

function fail(error) {
  console.log(
    JSON.stringify(
      {
        ok: false,
        error: {
          message: error?.message || String(error),
          code: error?.code || "ERROR",
          candidates: error?.candidates || undefined,
        },
      },
      null,
      2
    )
  );
  process.exitCode = 1;
}

function printResult(result) {
  if (result && typeof result === "object" && "tree" in result) {
    const { tree, ...meta } = result;
    console.log(JSON.stringify(meta, null, 2));
    if (tree) {
      console.log("\n--- ACCESSIBILITY TREE ---");
      console.log(tree);
      console.log("--- END ACCESSIBILITY TREE ---");
      if (result.treeTruncated) {
        console.log(`\nTree truncated. Full tree: ${result.treePath}`);
      }
    }
    return;
  }
  console.log(JSON.stringify(result, null, 2));
}

async function runUia(payload, requestTimeout = timeoutMs) {
  return runPowerShellScript(UIA_SCRIPT, payload, requestTimeout);
}

function normalizeNativeWindow(window) {
  return {
    id: Number(window.Hwnd),
    app: window.Process || "",
    title: window.Title || "",
    left: window.Left,
    top: window.Top,
    width: window.Width,
    height: window.Height,
    minimized: Boolean(window.Minimized),
  };
}

async function listWindows() {
  const result = await runNative({ op: "list" }, timeoutMs);
  const ignored = /^(Program Manager|Windows 输入体验|TextInputHost|Default IME|MSCTFIME UI)$/i;
  return (result.windows || [])
    .map(normalizeNativeWindow)
    .filter((window) => window.title && !ignored.test(window.title));
}

async function resolveWindow(selector = {}) {
  if (selector.stateFile) {
    try {
      const state = JSON.parse(readFileSync(selector.stateFile, "utf8"));
      if (!state?.window?.id) throw new Error("state file has no window id");
      return state.window;
    } catch (error) {
      const wrapped = new Error(`Could not read state file ${selector.stateFile}: ${error.message}`);
      wrapped.code = "BAD_STATE_FILE";
      throw wrapped;
    }
  }

  const windows = await listWindows();
  let candidates = windows;
  if (selector.window !== undefined) {
    const exact = windows.find((window) => Number(window.id) === Number(selector.window));
    if (exact) return exact;
    const error = new Error(
      `No window with id ${selector.window}. Run windows to list current window ids.`
    );
    error.code = "NO_WINDOW";
    throw error;
  }
  if (selector.app) {
    const needle = String(selector.app).toLowerCase();
    candidates = candidates.filter((window) =>
      `${window.app || ""} ${window.title || ""}`.toLowerCase().includes(needle)
    );
  }
  if (selector.title) {
    const needle = String(selector.title).toLowerCase();
    candidates = candidates.filter((window) =>
      String(window.title || "").toLowerCase().includes(needle)
    );
  }
  if (candidates.length === 0) {
    const error = new Error(
      `No window matched ${JSON.stringify({
        window: selector.window,
        app: selector.app,
        title: selector.title,
      })}. Open the app first or use a broader selector.`
    );
    error.code = "NO_WINDOW";
    throw error;
  }
  if (candidates.length > 1) {
    const error = new Error(
      `Multiple windows matched. Choose one with --window <id>: ${candidates
        .slice(0, 12)
        .map((window) => `${window.id} "${window.title}" (${window.app})`)
        .join(", ")}`
    );
    error.code = "AMBIGUOUS_WINDOW";
    error.candidates = candidates;
    throw error;
  }
  return candidates[0];
}

function selectorFromOptions() {
  const selector = {};
  if (opts.window !== undefined && opts.window !== null && opts.window !== "") {
    selector.window = Number(opts.window);
  }
  if (opts.title) selector.title = opts.title;
  if (opts.app) selector.app = opts.app;
  if (opts["state-file"]) selector.stateFile = opts["state-file"];
  return selector;
}

async function activateWindow(window) {
  if (opts["no-activate"]) return window;
  const result = await runNative({ op: "activate", hwnd: window.id }, 20000);
  return normalizeNativeWindow(result.window || { Hwnd: window.id });
}

async function captureNativeState(window, outDir) {
  const screenshotPath = join(outDir, "native.png");
  const shot = await runNative(
    {
      op: "screenshot",
      hwnd: window.id,
      out: screenshotPath,
      activate: !opts["no-activate"],
    },
    timeoutMs
  );
  return {
    ok: true,
    backend: "native",
    window: normalizeNativeWindow(shot.window || { Hwnd: window.id }),
    stateId: null,
    screenshots: [
      {
        path: shot.path,
        mime: "image/png",
        width: shot.width,
        height: shot.height,
        isWindow: true,
        originX: shot.window?.Left ?? window.left ?? null,
        originY: shot.window?.Top ?? window.top ?? null,
      },
    ],
    tree: "",
    treePath: null,
    treeTruncated: false,
    stateFile: null,
    focusedElement: null,
    elementCount: 0,
    note: "Native backend has no accessibility tree. Use the screenshot and window-relative coordinates.",
  };
}

async function doState() {
  let window = await resolveWindow(selectorFromOptions());
  if (!includeText) {
    return captureNativeState(window, ensureDir(opts["out-dir"] || defaultOutDir()));
  }

  const outDir = ensureDir(opts["out-dir"] || defaultOutDir());

  let tree;
  try {
    tree = await runUia(
      {
        op: "tree",
        hwnd: window.id,
        outDir,
        activate: !opts["no-activate"],
        maxElements: Number(opts["max-elements"] || 800),
        maxText: Number(opts["max-text"] || 30000),
      },
      Math.max(timeoutMs, 120000)
    );
  } catch (error) {
    if (error.code === "UIA_ERROR" || error.code === "POWERSHELL_ERROR") {
      const native = await captureNativeState(window, outDir);
      native.note =
        `UI Automation failed: ${error.message}. ` +
        "Falling back to a native screenshot; use coordinates for this window.";
      return native;
    }
    throw error;
  }

  const screenshots = [];
  if (includeScreenshot) {
    const shot = await runNative(
      {
        op: "screenshot",
        hwnd: window.id,
        out: join(outDir, "native.png"),
        activate: false,
      },
      timeoutMs
    );
    screenshots.push({
      path: shot.path,
      mime: "image/png",
      width: shot.width,
      height: shot.height,
      isWindow: true,
      originX: shot.window?.Left ?? tree.window?.left ?? null,
      originY: shot.window?.Top ?? tree.window?.top ?? null,
    });
  }

  if (opts["full-screen"]) {
    const screen = await runNative(
      { op: "screenshot-screen", out: join(outDir, "screen.png") },
      timeoutMs
    );
    screenshots.push({
      path: screen.path,
      mime: "image/png",
      width: screen.width,
      height: screen.height,
      isWindow: false,
      originX: 0,
      originY: 0,
    });
  }

  try {
    const state = JSON.parse(readFileSync(tree.stateFile, "utf8"));
    state.screenshots = screenshots;
    writeFileSync(tree.stateFile, JSON.stringify(state, null, 2), "utf8");
  } catch {
    // The state file is optional metadata; the tree still works.
  }

  return {
    ...tree,
    backend: "uia",
    screenshots,
  };
}

async function stateWindowForAction() {
  return resolveWindow(selectorFromOptions());
}

async function getElementInfo(window, stateFile, element) {
  const result = await runUia(
    {
      op: "element",
      hwnd: window.id,
      stateFile,
      element: Number(element),
      activate: true,
    },
    timeoutMs
  );
  return result.element;
}

function elementCenter(rect) {
  const x = Number(rect?.x || 0);
  const y = Number(rect?.y || 0);
  const width = Number(rect?.width || 0);
  const height = Number(rect?.height || 0);
  if (width <= 0 || height <= 0) return null;
  return { x: Math.round(x + width / 2), y: Math.round(y + height / 2) };
}

async function doClick() {
  if (opts.element === undefined) {
    if (opts.x === undefined || opts.y === undefined) {
      const error = new Error("click requires --element N or both --x and --y.");
      error.code = "BAD_INPUT";
      throw error;
    }
    const window = await stateWindowForAction();
    const result = await runNative(
      {
        op: "click",
        hwnd: window.id,
        x: Number(opts.x),
        y: Number(opts.y),
        button: opts.button || "left",
        count: Number(opts.count || 1),
      },
      timeoutMs
    );
    return {
      ok: true,
      backend: "native",
      window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
      action: "click",
      x: Number(opts.x),
      y: Number(opts.y),
      button: opts.button || "left",
      count: Number(opts.count || 1),
    };
  }

  if (!opts["state-file"]) {
    const error = new Error(
      "Element clicks require --state-file from the state command. Run state first."
    );
    error.code = "BAD_INPUT";
    throw error;
  }

  const window = await stateWindowForAction();
  const info = await getElementInfo(window, opts["state-file"], opts.element);
  const center = elementCenter(info.rect);
  const button = String(opts.button || "left").toLowerCase();

  if (!center) {
    const invoked = await runUia(
      {
        op: "invoke",
        hwnd: window.id,
        stateFile: opts["state-file"],
        element: Number(opts.element),
        action: "Invoke",
        activate: true,
      },
      timeoutMs
    );
    return {
      ok: true,
      backend: "uia",
      window,
      action: "click-element",
      element: Number(opts.element),
      method: invoked.method || "Invoke",
    };
  }

  const result = await runNative(
    {
      op: "click",
      hwnd: window.id,
      x: center.x,
      y: center.y,
      screen: true,
      button,
      count: Number(opts.count || 1),
    },
    timeoutMs
  );
  return {
    ok: true,
    backend: "uia",
    window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
    action: "click-element",
    element: Number(opts.element),
    elementName: info.name,
    controlType: info.controlType,
    x: center.x,
    y: center.y,
    button,
    count: Number(opts.count || 1),
  };
}

async function textFromOptions() {
  if (opts.stdin) {
    const text = readFileSync(0, "utf8");
    if (!text) {
      const error = new Error("--stdin was provided but stdin was empty.");
      error.code = "BAD_INPUT";
      throw error;
    }
    return text;
  }
  if (opts.text !== undefined) return String(opts.text);
  const error = new Error("type requires --text TEXT or --stdin.");
  error.code = "BAD_INPUT";
  throw error;
}

async function doSetValue() {
  if (opts.element === undefined) {
    const error = new Error("set-value requires --element N.");
    error.code = "BAD_INPUT";
    throw error;
  }
  if (!opts["state-file"]) {
    const error = new Error(
      "set-value requires --state-file from the state command. Run state first."
    );
    error.code = "BAD_INPUT";
    throw error;
  }
  let value = opts.value;
  if (opts.stdin) value = readFileSync(0, "utf8");
  if (value === undefined) {
    const error = new Error("set-value requires --value TEXT or --stdin.");
    error.code = "BAD_INPUT";
    throw error;
  }

  const window = await stateWindowForAction();
  try {
    const result = await runUia(
      {
        op: "set-value",
        hwnd: window.id,
        stateFile: opts["state-file"],
        element: Number(opts.element),
        value,
        activate: true,
      },
      timeoutMs
    );
    return {
      ok: true,
      backend: "uia",
      window,
      action: "set-value",
      element: Number(opts.element),
      method: "ValuePattern",
      result,
    };
  } catch (error) {
    if (error.code !== "VALUE_UNSUPPORTED") throw error;

    // Fallback: focus the element, select all, and type the value.
    const info = await getElementInfo(window, opts["state-file"], opts.element);
    const center = elementCenter(info.rect);
    if (!center) throw error;
    await runNative(
      {
        op: "click",
        hwnd: window.id,
        x: center.x,
        y: center.y,
        screen: true,
        button: "left",
        count: 1,
      },
      timeoutMs
    );
    await runNative({ op: "key", hwnd: window.id, key: "Control_L+a" }, timeoutMs);
    await runNative({ op: "type", hwnd: window.id, text: String(value) }, timeoutMs);
    return {
      ok: true,
      backend: "uia",
      window,
      action: "set-value",
      element: Number(opts.element),
      method: "click+select-all+type",
    };
  }
}

async function doAction() {
  if (opts.element === undefined || !opts.action) {
    const error = new Error("action requires --element N and --action NAME.");
    error.code = "BAD_INPUT";
    throw error;
  }
  if (!opts["state-file"]) {
    const error = new Error(
      "action requires --state-file from the state command. Run state first."
    );
    error.code = "BAD_INPUT";
    throw error;
  }
  const window = await stateWindowForAction();
  const result = await runUia(
    {
      op: "invoke",
      hwnd: window.id,
      stateFile: opts["state-file"],
      element: Number(opts.element),
      action: opts.action,
      activate: true,
    },
    timeoutMs
  );
  return {
    ok: true,
    backend: "uia",
    window,
    action: "secondary-action",
    element: Number(opts.element),
    secondaryAction: opts.action,
    method: result.method,
  };
}

async function doNativeInput(kind) {
  const window = await stateWindowForAction();
  const payload = {
    op: kind,
    hwnd: window.id,
    button: opts.button,
    count: opts.count,
    x: opts.x !== undefined ? Number(opts.x) : undefined,
    y: opts.y !== undefined ? Number(opts.y) : undefined,
    dx: Number(opts.dx || 0),
    dy: Number(opts.dy || 0),
    fromX: Number(opts["from-x"] || 0),
    fromY: Number(opts["from-y"] || 0),
    toX: Number(opts["to-x"] || 0),
    toY: Number(opts["to-y"] || 0),
  };
  if (kind === "type") payload.text = await textFromOptions();
  if (kind === "key") payload.key = String(opts.key || "");
  const result = await runNative(payload, timeoutMs);
  return {
    ok: true,
    backend: "native",
    window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
    action: kind,
    result,
  };
}

async function main() {
  if (command === "doctor") {
    const result = {
      ok: true,
      version: VERSION,
      backend: "uia",
      platform: process.platform,
      arch: process.arch,
      node: process.version,
      uia: null,
      native: null,
      notes: [],
    };
    try {
      const probe = await runUia({ op: "probe" }, 30000);
      result.uia = { available: Boolean(probe.ok), script: UIA_SCRIPT, assembly: probe.assembly };
    } catch (error) {
      result.uia = { available: false, script: UIA_SCRIPT, error: error.message };
      result.ok = false;
      result.notes.push("Windows UI Automation is unavailable. Install/enable .NET UIAutomationClient.");
    }
    try {
      const native = await runNative({ op: "list" }, 30000);
      result.native = { available: true, windowCount: (native.windows || []).length };
    } catch (error) {
      result.native = { available: false, error: error.message };
      result.ok = false;
      result.notes.push("Native PowerShell input/screenshot backend is unavailable.");
    }
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  if (command === "windows" || command === "apps") {
    let windows = await listWindows();
    if (opts.app) {
      const needle = String(opts.app).toLowerCase();
      windows = windows.filter((window) =>
        `${window.app || ""} ${window.title || ""}`.toLowerCase().includes(needle)
      );
    }
    if (opts.title) {
      const needle = String(opts.title).toLowerCase();
      windows = windows.filter((window) =>
        String(window.title || "").toLowerCase().includes(needle)
      );
    }
    if (command === "windows") {
      printResult({ ok: true, backend: "uia", windows });
    } else {
      const groups = new Map();
      for (const window of windows) {
        const key = window.app || "unknown";
        if (!groups.has(key)) {
          groups.set(key, { id: key, displayName: key, isRunning: true, windows: [] });
        }
        groups.get(key).windows.push(window);
      }
      printResult({ ok: true, backend: "uia", apps: [...groups.values()] });
    }
    return;
  }

  if (command === "start-apps") {
    const result = await runUia({ op: "start-apps" }, timeoutMs);
    let apps = result.apps || [];
    if (opts.app) {
      const needle = String(opts.app).toLowerCase();
      apps = apps.filter((app) =>
        `${app.Name || ""} ${app.AppID || ""}`.toLowerCase().includes(needle)
      );
    }
    printResult({ ok: true, backend: "uia", apps });
    return;
  }

  if (command === "state") {
    printResult(await doState());
    return;
  }

  if (command === "click") {
    printResult(await doClick());
    return;
  }

  if (command === "set-value") {
    printResult(await doSetValue());
    return;
  }

  if (command === "action") {
    printResult(await doAction());
    return;
  }

  if (command === "type") {
    if (backend === "uia") {
      const window = await stateWindowForAction();
      if (opts.x !== undefined && opts.y !== undefined) {
        await runNative(
          {
            op: "click",
            hwnd: window.id,
            x: Number(opts.x),
            y: Number(opts.y),
            button: "left",
            count: 1,
          },
          timeoutMs
        );
      }
      const text = await textFromOptions();
      const result = await runNative({ op: "type", hwnd: window.id, text }, timeoutMs);
      printResult({
        ok: true,
        backend: "native",
        window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
        action: "type",
        chars: text.length,
      });
      return;
    }
    printResult(await doNativeInput("type"));
    return;
  }

  if (command === "key") {
    if (!opts.key) {
      const error = new Error("key requires --key.");
      error.code = "BAD_INPUT";
      throw error;
    }
    printResult(await doNativeInput("key"));
    return;
  }

  if (command === "scroll") {
    printResult(await doNativeInput("scroll"));
    return;
  }

  if (command === "drag") {
    if (
      opts["from-x"] === undefined ||
      opts["from-y"] === undefined ||
      opts["to-x"] === undefined ||
      opts["to-y"] === undefined
    ) {
      const error = new Error("drag requires --from-x, --from-y, --to-x, and --to-y.");
      error.code = "BAD_INPUT";
      throw error;
    }
    printResult(await doNativeInput("drag"));
    return;
  }

  if (command === "activate") {
    const window = await stateWindowForAction();
    const result = await runNative({ op: "activate", hwnd: window.id }, timeoutMs);
    printResult({
      ok: true,
      backend: "native",
      window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
      action: "activate",
    });
    return;
  }

  if (command === "launch") {
    const result = await runNative(
      { op: "launch", app: opts.app, command: opts.command },
      timeoutMs
    );
    printResult({ ok: true, backend: "native", action: "launch", ...result });
    return;
  }

  if (command === "screenshot") {
    if (!opts.out) {
      const error = new Error("screenshot requires --out PATH.");
      error.code = "BAD_INPUT";
      throw error;
    }
    const window = await stateWindowForAction();
    const result = await runNative(
      {
        op: "screenshot",
        hwnd: window.id,
        out: opts.out,
        activate: !opts["no-activate"],
      },
      timeoutMs
    );
    printResult({
      ok: true,
      backend: "native",
      window: normalizeNativeWindow(result.window || { Hwnd: window.id }),
      screenshots: [
        {
          path: result.path,
          mime: "image/png",
          width: result.width,
          height: result.height,
          isWindow: true,
          originX: result.window?.Left ?? window.left ?? null,
          originY: result.window?.Top ?? window.top ?? null,
        },
      ],
    });
    return;
  }

  const error = new Error(`Unknown command: ${command}`);
  error.code = "BAD_INPUT";
  throw error;
}

main().catch(fail);

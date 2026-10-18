$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Drawing

$csharp = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

public class WinInfo
{
    public long Hwnd { get; set; }
    public string Title { get; set; }
    public string ClassName { get; set; }
    public int Pid { get; set; }
    public string Process { get; set; }
    public int Left { get; set; }
    public int Top { get; set; }
    public int Right { get; set; }
    public int Bottom { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public bool Minimized { get; set; }
    public bool Visible { get; set; }
}

public static class Native
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("user32.dll")]
    public static extern void SwitchToThisWindow(IntPtr hwnd, bool altTab);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, int data, UIntPtr extraInfo);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")]
    public static extern IntPtr GetWindowDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")]
    public static extern short VkKeyScan(char ch);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
    [DllImport("kernel32.dll")]
    public static extern void Sleep(int milliseconds);

    public const uint INPUT_MOUSE = 0;
    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_UNICODE = 0x0004;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    public const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    public const uint MOUSEEVENTF_WHEEL = 0x0800;
    public const uint MOUSEEVENTF_HWHEEL = 0x1000;

    public static void EnableDpiAwareness()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
    }

    public static List<WinInfo> GetWindows()
    {
        var list = new List<WinInfo>();
        EnumWindows(delegate(IntPtr hwnd, IntPtr lparam)
        {
            if (!IsWindowVisible(hwnd)) return true;
            int length = GetWindowTextLength(hwnd);
            if (length == 0) return true;
            var title = new StringBuilder(length + 1);
            GetWindowText(hwnd, title, title.Capacity);
            if (title.Length == 0) return true;
            var cls = new StringBuilder(256);
            GetClassName(hwnd, cls, cls.Capacity);
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            string process = "";
            try { process = Process.GetProcessById((int)pid).ProcessName; } catch { }
            RECT rect;
            GetWindowRect(hwnd, out rect);
            list.Add(new WinInfo
            {
                Hwnd = hwnd.ToInt64(),
                Title = title.ToString(),
                ClassName = cls.ToString(),
                Pid = (int)pid,
                Process = process,
                Left = rect.Left,
                Top = rect.Top,
                Right = rect.Right,
                Bottom = rect.Bottom,
                Width = rect.Right - rect.Left,
                Height = rect.Bottom - rect.Top,
                Minimized = IsIconic(hwnd),
                Visible = true
            });
            return true;
        }, IntPtr.Zero);
        list.Sort((a, b) => string.Compare(a.Process + " " + a.Title, b.Process + " " + b.Title, StringComparison.OrdinalIgnoreCase));
        return list;
    }

    public static WinInfo GetWindowInfo(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        int length = GetWindowTextLength(hwnd);
        var title = new StringBuilder(length + 1);
        GetWindowText(hwnd, title, title.Capacity);
        var cls = new StringBuilder(256);
        GetClassName(hwnd, cls, cls.Capacity);
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        string process = "";
        try { process = Process.GetProcessById((int)pid).ProcessName; } catch { }
        RECT rect;
        if (!GetWindowRect(hwnd, out rect)) return null;
        return new WinInfo
        {
            Hwnd = hwnd.ToInt64(),
            Title = title.ToString(),
            ClassName = cls.ToString(),
            Pid = (int)pid,
            Process = process,
            Left = rect.Left,
            Top = rect.Top,
            Right = rect.Right,
            Bottom = rect.Bottom,
            Width = rect.Right - rect.Left,
            Height = rect.Bottom - rect.Top,
            Minimized = IsIconic(hwnd),
            Visible = IsWindowVisible(hwnd)
        };
    }

    public static void Activate(IntPtr hwnd)
    {
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        IntPtr foreground = GetForegroundWindow();
        uint foregroundPid;
        uint foregroundThread = GetWindowThreadProcessId(foreground, out foregroundPid);
        uint targetPid;
        uint targetThread = GetWindowThreadProcessId(hwnd, out targetPid);
        bool attached = false;
        if (foregroundThread != 0 && targetThread != 0 && foregroundThread != targetThread)
        {
            attached = AttachThreadInput(foregroundThread, targetThread, true);
        }
        SetForegroundWindow(hwnd);
        BringWindowToTop(hwnd);
        if (foreground != hwnd) SwitchToThisWindow(hwnd, true);
        if (attached) AttachThreadInput(foregroundThread, targetThread, false);
        Sleep(220);
    }

    private static INPUT KeyInput(ushort vk, ushort scan, uint flags)
    {
        var input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wVk = vk;
        input.U.ki.wScan = scan;
        input.U.ki.dwFlags = flags;
        input.U.ki.time = 0;
        input.U.ki.dwExtraInfo = IntPtr.Zero;
        return input;
    }

    private static void SendAll(List<INPUT> inputs)
    {
        if (inputs.Count == 0) return;
        var array = inputs.ToArray();
        uint sent = SendInput((uint)array.Length, array, Marshal.SizeOf(typeof(INPUT)));
        if (sent != array.Length)
        {
            throw new Exception("SendInput failed (sent " + sent + " of " + array.Length + " events, error " + Marshal.GetLastWin32Error() + ")");
        }
    }

    public static void SendUnicode(string text)
    {
        if (text == null) return;
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        var parts = text.Split('\n');
        for (int p = 0; p < parts.Length; p++)
        {
            if (parts[p].Length > 0)
            {
                var inputs = new List<INPUT>();
                foreach (char c in parts[p])
                {
                    inputs.Add(KeyInput(0, (ushort)c, KEYEVENTF_UNICODE));
                    inputs.Add(KeyInput(0, (ushort)c, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
                }
                SendAll(inputs);
            }
            if (p < parts.Length - 1)
            {
                SendAll(new List<INPUT> { KeyInput(0x0D, 0, 0), KeyInput(0x0D, 0, KEYEVENTF_KEYUP) });
            }
            Sleep(5);
        }
    }

    private static bool IsModifier(string name)
    {
        string n = name.ToLowerInvariant();
        return n == "ctrl" || n == "control" || n == "control_l" || n == "control_r" ||
               n == "shift" || n == "shift_l" || n == "shift_r" ||
               n == "alt" || n == "alt_l" || n == "alt_r" ||
               n == "win" || n == "super" || n == "meta" || n == "super_l" || n == "super_r";
    }

    private static ushort ModifierVk(string name)
    {
        string n = name.ToLowerInvariant();
        if (n.StartsWith("ctrl") || n.StartsWith("control")) return 0x11;
        if (n.StartsWith("shift")) return 0x10;
        if (n.StartsWith("alt")) return 0x12;
        return 0x5B;
    }

    private static ushort MapKey(string name, List<ushort> extraModifiers)
    {
        string n = name.Trim();
        if (n.Length == 0) throw new Exception("empty key");
        string lower = n.ToLowerInvariant();

        switch (lower)
        {
            case "return": case "enter": return 0x0D;
            case "tab": return 0x09;
            case "escape": case "esc": return 0x1B;
            case "space": case "spacebar": return 0x20;
            case "backspace": case "back": return 0x08;
            case "delete": case "del": return 0x2E;
            case "insert": case "ins": return 0x2D;
            case "home": return 0x24;
            case "end": return 0x23;
            case "pageup": case "pgup": return 0x21;
            case "pagedown": case "pgdn": return 0x22;
            case "up": case "arrowup": return 0x26;
            case "down": case "arrowdown": return 0x28;
            case "left": case "arrowleft": return 0x25;
            case "right": case "arrowright": return 0x27;
            case "printscreen": case "print": return 0x2C;
            case "pause": return 0x13;
            case "capslock": return 0x14;
            case "numlock": return 0x90;
            case "scrolllock": return 0x91;
            case "apps": case "menu": return 0x5D;
            case "period": case ".": return 0xBE;
            case "comma": case ",": return 0xBC;
            case "slash": case "/": return 0xBF;
            case "backslash": case "\\": return 0xDC;
            case "semicolon": case ";": return 0xBA;
            case "apostrophe": case "'": return 0xDE;
            case "minus": case "-": return 0xBD;
            case "equal": case "=": return 0xBB;
            case "plus": case "+": extraModifiers.Add(0x10); return 0xBB;
            case "bracketleft": case "[": return 0xDB;
            case "bracketright": case "]": return 0xDD;
            case "grave": case "`": return 0xC0;
        }

        int fnum;
        if (lower.Length >= 2 && lower[0] == 'f' && int.TryParse(lower.Substring(1), out fnum) && fnum >= 1 && fnum <= 24)
        {
            return (ushort)(0x70 + fnum - 1);
        }
        if (lower.StartsWith("kp_") || lower.StartsWith("numpad_"))
        {
            string suffix = lower.Substring(lower.IndexOf('_') + 1);
            if (suffix.Length == 1 && char.IsDigit(suffix[0])) return (ushort)(0x60 + (suffix[0] - '0'));
            if (suffix == "add") return 0x6B;
            if (suffix == "subtract") return 0x6D;
            if (suffix == "multiply") return 0x6A;
            if (suffix == "divide") return 0x6F;
            if (suffix == "decimal") return 0x6E;
        }
        if (n.Length == 1)
        {
            char c = n[0];
            if (c >= 'a' && c <= 'z') return (ushort)(0x41 + (c - 'a'));
            if (c >= 'A' && c <= 'Z') { extraModifiers.Add(0x10); return (ushort)(0x41 + (c - 'A')); }
            if (c >= '0' && c <= '9') return (ushort)(0x30 + (c - '0'));
            short vk = VkKeyScan(c);
            if (vk != -1)
            {
                byte low = (byte)(vk & 0xFF);
                byte high = (byte)((vk >> 8) & 0xFF);
                if ((high & 1) != 0) extraModifiers.Add(0x10);
                if ((high & 2) != 0) extraModifiers.Add(0x11);
                if ((high & 4) != 0) extraModifiers.Add(0x12);
                return low;
            }
        }
        throw new Exception("unknown key: " + name);
    }

    public static void SendKeyChord(string chord)
    {
        var modifiers = new List<ushort>();
        var extra = new List<ushort>();
        ushort key = 0;
        foreach (string raw in chord.Split('+'))
        {
            string token = raw.Trim();
            if (token.Length == 0) continue;
            if (IsModifier(token)) modifiers.Add(ModifierVk(token));
            else key = MapKey(token, extra);
        }
        if (key == 0) throw new Exception("no key in chord: " + chord);
        foreach (ushort m in extra) if (!modifiers.Contains(m)) modifiers.Add(m);

        var inputs = new List<INPUT>();
        foreach (ushort m in modifiers) inputs.Add(KeyInput(m, 0, 0));
        inputs.Add(KeyInput(key, 0, 0));
        inputs.Add(KeyInput(key, 0, KEYEVENTF_KEYUP));
        for (int i = modifiers.Count - 1; i >= 0; i--) inputs.Add(KeyInput(modifiers[i], 0, KEYEVENTF_KEYUP));
        SendAll(inputs);
        Sleep(20);
    }

    public static void Click(int x, int y, string button, int count)
    {
        SetCursorPos(x, y);
        uint down = MOUSEEVENTF_LEFTDOWN, up = MOUSEEVENTF_LEFTUP;
        if (button == "right") { down = MOUSEEVENTF_RIGHTDOWN; up = MOUSEEVENTF_RIGHTUP; }
        else if (button == "middle") { down = MOUSEEVENTF_MIDDLEDOWN; up = MOUSEEVENTF_MIDDLEUP; }
        for (int i = 0; i < count; i++)
        {
            mouse_event(down, 0, 0, 0, UIntPtr.Zero);
            Sleep(30);
            mouse_event(up, 0, 0, 0, UIntPtr.Zero);
            Sleep(60);
        }
    }

    public static void Scroll(int x, int y, int dy, int dx)
    {
        SetCursorPos(x, y);
        if (dy != 0) mouse_event(MOUSEEVENTF_WHEEL, 0, 0, -dy, UIntPtr.Zero);
        if (dx != 0) mouse_event(MOUSEEVENTF_HWHEEL, 0, 0, dx, UIntPtr.Zero);
        Sleep(50);
    }

    public static void Drag(int x1, int y1, int x2, int y2)
    {
        SetCursorPos(x1, y1);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Sleep(80);
        int steps = 20;
        for (int i = 1; i <= steps; i++)
        {
            int x = x1 + (x2 - x1) * i / steps;
            int y = y1 + (y2 - y1) * i / steps;
            SetCursorPos(x, y);
            Sleep(15);
        }
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        Sleep(80);
    }

    public static void CaptureWindow(long hwndValue, string path, bool activate)
    {
        IntPtr hwnd = new IntPtr(hwndValue);
        if (activate) Activate(hwnd);
        RECT rect;
        if (!GetWindowRect(hwnd, out rect)) throw new Exception("GetWindowRect failed");
        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0) throw new Exception("window has no visible area");
        using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(bitmap))
            {
                IntPtr hdc = graphics.GetHdc();
                bool ok = false;
                try { ok = PrintWindow(hwnd, hdc, 2); }
                finally { graphics.ReleaseHdc(hdc); }
                if (!ok)
                {
                    graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(width, height), CopyPixelOperation.SourceCopy);
                }
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    public static void CaptureScreen(string path)
    {
        int width = GetSystemMetrics(0);
        int height = GetSystemMetrics(1);
        using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(0, 0, 0, 0, new Size(width, height), CopyPixelOperation.SourceCopy);
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}
'@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing
[Native]::EnableDpiAwareness()

function Resolve-Target($req) {
    if ($null -ne $req.hwnd) {
        $candidate = [Native]::GetWindowInfo([IntPtr]([long]$req.hwnd))
        if ($null -ne $candidate -and $candidate.Hwnd -ne 0) {
            if ([string]::IsNullOrEmpty([string]$req.title) -or $candidate.Title -like ("*" + [string]$req.title + "*")) {
                return $candidate
            }
        }
    }
    $windows = @([Native]::GetWindows())
    if (-not [string]::IsNullOrEmpty([string]$req.title)) {
        $matches = @($windows | Where-Object { $_.Title -like ("*" + [string]$req.title + "*") })
        if ($matches.Count -gt 0) { return $matches[0] }
    }
    if (-not [string]::IsNullOrEmpty([string]$req.app)) {
        $matches = @($windows | Where-Object { $_.Process -like ("*" + [string]$req.app + "*") -or $_.Title -like ("*" + [string]$req.app + "*") })
        if ($matches.Count -gt 0) { return $matches[0] }
    }
    throw "window not found"
}

function Write-Result($value) {
    $json = $value | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "no command JSON on stdin" }
    $req = $raw | ConvertFrom-Json
    $op = [string]$req.op

    if ($op -eq "list") {
        $windows = @([Native]::GetWindows())
        Write-Result ([ordered]@{ ok = $true; windows = $windows })
        exit 0
    }

    if ($op -eq "get") {
        $win = Resolve-Target $req
        Write-Result ([ordered]@{ ok = $true; window = $win })
        exit 0
    }

    if ($op -eq "activate") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        Write-Result ([ordered]@{ ok = $true; window = $win })
        exit 0
    }

    if ($op -eq "screenshot") {
        $win = Resolve-Target $req
        $activate = $true
        if ($null -ne $req.activate) { $activate = [bool]$req.activate }
        $path = [string]$req.out
        if ([string]::IsNullOrWhiteSpace($path)) { throw "missing out path" }
        $dir = Split-Path -Parent $path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [Native]::CaptureWindow([long]$win.Hwnd, $path, $activate)
        $image = [System.Drawing.Image]::FromFile($path)
        $width = $image.Width
        $height = $image.Height
        $image.Dispose()
        Write-Result ([ordered]@{ ok = $true; path = $path; width = $width; height = $height; window = $win })
        exit 0
    }

    if ($op -eq "screenshot-screen") {
        $path = [string]$req.out
        if ([string]::IsNullOrWhiteSpace($path)) { throw "missing out path" }
        $dir = Split-Path -Parent $path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [Native]::CaptureScreen($path)
        $image = [System.Drawing.Image]::FromFile($path)
        $width = $image.Width
        $height = $image.Height
        $image.Dispose()
        Write-Result ([ordered]@{ ok = $true; path = $path; width = $width; height = $height })
        exit 0
    }

    if ($op -eq "click") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        $x = [int]$win.Left + [int]$req.x
        $y = [int]$win.Top + [int]$req.y
        if ($null -ne $req.screen -and [bool]$req.screen) { $x = [int]$req.x; $y = [int]$req.y }
        $button = "left"
        if (-not [string]::IsNullOrEmpty([string]$req.button)) { $button = ([string]$req.button).ToLowerInvariant() }
        $count = 1
        if ($null -ne $req.count) { $count = [int]$req.count }
        [Native]::Click($x, $y, $button, $count)
        Write-Result ([ordered]@{ ok = $true; window = $win; x = $x; y = $y; button = $button; count = $count })
        exit 0
    }

    if ($op -eq "type") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        if ($null -ne $req.x -and $null -ne $req.y) {
            [Native]::Click([int]$win.Left + [int]$req.x, [int]$win.Top + [int]$req.y, "left", 1)
            Start-Sleep -Milliseconds 120
        }
        $text = [string]$req.text
        [Native]::SendUnicode($text)
        Write-Result ([ordered]@{ ok = $true; window = $win; chars = $text.Length })
        exit 0
    }

    if ($op -eq "key") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        $key = [string]$req.key
        [Native]::SendKeyChord($key)
        Write-Result ([ordered]@{ ok = $true; window = $win; key = $key })
        exit 0
    }

    if ($op -eq "scroll") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        $x = [int]$win.Left + [int]$req.x
        $y = [int]$win.Top + [int]$req.y
        $dy = 0
        $dx = 0
        if ($null -ne $req.dy) { $dy = [int]$req.dy }
        if ($null -ne $req.dx) { $dx = [int]$req.dx }
        [Native]::Scroll($x, $y, $dy, $dx)
        Write-Result ([ordered]@{ ok = $true; window = $win; x = $x; y = $y; dy = $dy; dx = $dx })
        exit 0
    }

    if ($op -eq "drag") {
        $win = Resolve-Target $req
        [Native]::Activate([IntPtr]([long]$win.Hwnd))
        $x1 = [int]$win.Left + [int]$req.fromX
        $y1 = [int]$win.Top + [int]$req.fromY
        $x2 = [int]$win.Left + [int]$req.toX
        $y2 = [int]$win.Top + [int]$req.toY
        [Native]::Drag($x1, $y1, $x2, $y2)
        Write-Result ([ordered]@{ ok = $true; window = $win; fromX = $x1; fromY = $y1; toX = $x2; toY = $y2 })
        exit 0
    }

    if ($op -eq "launch") {
        if (-not [string]::IsNullOrEmpty([string]$req.command)) {
            Start-Process -FilePath ([string]$req.command) | Out-Null
        } elseif (-not [string]::IsNullOrEmpty([string]$req.app)) {
            $app = [string]$req.app
            if ($app -like "*!*") {
                Start-Process -FilePath "explorer.exe" -ArgumentList ("shell:AppsFolder\" + $app) | Out-Null
            } else {
                Start-Process -FilePath $app | Out-Null
            }
        } else {
            throw "missing command or app"
        }
        Write-Result ([ordered]@{ ok = $true })
        exit 0
    }

    throw "unknown op: $op"
}
catch {
    Write-Result ([ordered]@{ ok = $false; error = [ordered]@{ message = $_.Exception.Message; type = $_.Exception.GetType().Name } })
    exit 1
}

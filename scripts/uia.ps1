$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing

$csharp = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class UiaWin32
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    public static void EnableDpiAwareness()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
    }

    public static string Title(IntPtr hwnd)
    {
        int len = GetWindowTextLength(hwnd);
        var sb = new StringBuilder(len + 1);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }
}
'@
Add-Type -TypeDefinition $csharp
[UiaWin32]::EnableDpiAwareness()

$script:walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$script:elements = New-Object System.Collections.ArrayList
$script:lines = New-Object System.Collections.ArrayList
$script:counter = 0
$script:maxElements = 800

function Write-Result($value) {
    $json = $value | ConvertTo-Json -Depth 12 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
}

function Safe-Get($scriptBlock, $fallback = $null) {
    try { return & $scriptBlock } catch { return $fallback }
}

function To-Int($value) {
    try {
        $d = [double]$value
        if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return 0 }
        return [int]$d
    } catch {
        return 0
    }
}

function Get-ControlType($el) {
    $ct = Safe-Get { $el.Current.ControlType } $null
    if ($null -eq $ct) { return "Unknown" }
    return ($ct.ProgrammaticName -replace '^ControlType\.', '')
}

function Get-Patterns($el) {
    $names = New-Object System.Collections.ArrayList
    $checks = @(
        @("Invoke", [System.Windows.Automation.InvokePattern]::Pattern),
        @("Value", [System.Windows.Automation.ValuePattern]::Pattern),
        @("SelectionItem", [System.Windows.Automation.SelectionItemPattern]::Pattern),
        @("ExpandCollapse", [System.Windows.Automation.ExpandCollapsePattern]::Pattern),
        @("Toggle", [System.Windows.Automation.TogglePattern]::Pattern),
        @("ScrollItem", [System.Windows.Automation.ScrollItemPattern]::Pattern)
    )
    foreach ($check in $checks) {
        $obj = $null
        try {
            if ($el.TryGetCurrentPattern($check[1], [ref]$obj)) { [void]$names.Add($check[0]) }
        } catch { }
    }
    return ($names -join ',')
}

function Get-ElementValue($el) {
    $obj = $null
    try {
        if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$obj)) {
            return [string]$obj.Current.Value
        }
    } catch { }
    return $null
}

function Walk-Element($el, [int[]]$path, [int]$depth) {
    if ($script:counter -ge $script:maxElements) { return }
    if ($depth -gt 30) { return }

    $index = $script:counter
    $script:counter++

    $controlType = Get-ControlType $el
    $name = [string](Safe-Get { $el.Current.Name } "")
    $automationId = [string](Safe-Get { $el.Current.AutomationId } "")
    $className = [string](Safe-Get { $el.Current.ClassName } "")
    $helpText = [string](Safe-Get { $el.Current.HelpText } "")
    $value = Get-ElementValue $el
    $patterns = Get-Patterns $el
    $rect = Safe-Get { $el.Current.BoundingRectangle } $null
    $offscreen = [bool](Safe-Get { $el.Current.IsOffscreen } $false)
    $enabled = [bool](Safe-Get { $el.Current.IsEnabled } $true)

    $x = 0; $y = 0; $w = 0; $h = 0
    if ($null -ne $rect) {
        $x = To-Int $rect.X; $y = To-Int $rect.Y; $w = To-Int $rect.Width; $h = To-Int $rect.Height
    }

    $line = ("`t" * $depth) + "$index $controlType"
    if ($name) { $line += " `"$name`"" }
    if ($automationId) { $line += " ID: $automationId" }
    if ($className) { $line += " Class: $className" }
    if ($null -ne $value -and $value -ne "") { $line += " Value: $value" }
    if ($helpText) { $line += " Help: $helpText" }
    if ($patterns) { $line += " Actions: $patterns" }
    if ($offscreen) { $line += " (offscreen)" }
    if (-not $enabled) { $line += " (disabled)" }
    [void]$script:lines.Add($line)

    [void]$script:elements.Add([ordered]@{
        index = $index
        path = @($path)
        controlType = $controlType
        name = $name
        automationId = $automationId
        className = $className
        value = $value
        patterns = $patterns
        rect = [ordered]@{ x = $x; y = $y; width = $w; height = $h }
        offscreen = $offscreen
        enabled = $enabled
    })

    $child = $null
    try { $child = $script:walker.GetFirstChild($el) } catch { $child = $null }
    $childIndex = 0
    while ($null -ne $child) {
        Walk-Element $child (@($path) + $childIndex) ($depth + 1)
        try { $child = $script:walker.GetNextSibling($child) } catch { $child = $null }
        $childIndex++
    }
}

function Get-ChildAt($el, [int]$index) {
    $child = $null
    try { $child = $script:walker.GetFirstChild($el) } catch { return $null }
    $i = 0
    while ($null -ne $child -and $i -lt $index) {
        try { $child = $script:walker.GetNextSibling($child) } catch { return $null }
        $i++
    }
    return $child
}

function Find-ByPath($root, [int[]]$path) {
    $current = $root
    foreach ($idx in $path) {
        if ($null -eq $current) { return $null }
        $current = Get-ChildAt $current ([int]$idx)
    }
    return $current
}

function Element-Matches($el, $entry) {
    if ($null -eq $el) { return $false }
    $name = [string](Safe-Get { $el.Current.Name } "")
    $aid = [string](Safe-Get { $el.Current.AutomationId } "")
    $ct = Get-ControlType $el
    if ($entry.automationId -and $aid -ne [string]$entry.automationId) { return $false }
    if ($entry.name -and $name -ne [string]$entry.name) { return $false }
    if ($entry.controlType -and $ct -ne [string]$entry.controlType) { return $false }
    return $true
}

function Find-Element($root, $entry) {
    $path = @($entry.path)
    $el = Find-ByPath $root $path
    if (Element-Matches $el $entry) { return $el }

    if ([string]::IsNullOrEmpty([string]$entry.name) -and [string]::IsNullOrEmpty([string]$entry.automationId)) {
        return $null
    }

    # Path drifted. Do a bounded breadth-first search for matching metadata.
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($root)
    $visited = 0
    while ($queue.Count -gt 0 -and $visited -lt $script:maxElements) {
        $current = $queue.Dequeue()
        $visited++
        if (Element-Matches $current $entry) { return $current }
        $child = $null
        try { $child = $script:walker.GetFirstChild($current) } catch { $child = $null }
        while ($null -ne $child) {
            $queue.Enqueue($child)
            try { $child = $script:walker.GetNextSibling($child) } catch { $child = $null }
        }
    }
    return $null
}

function Load-State($path) {
    $json = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return $json | ConvertFrom-Json
}

function Get-WindowInfo([long]$hwnd) {
    $ptr = [IntPtr]$hwnd
    $rect = New-Object UiaWin32+RECT
    [void][UiaWin32]::GetWindowRect($ptr, [ref]$rect)
    $process = ""
    try {
        $procId = 0
        [void][UiaWin32]::GetWindowThreadProcessId($ptr, [ref]$procId)
        $process = (Get-Process -Id ([int]$procId)).ProcessName
    } catch { }
    return [ordered]@{
        id = $hwnd
        title = [UiaWin32]::Title($ptr)
        app = $process
        left = $rect.Left
        top = $rect.Top
        width = $rect.Right - $rect.Left
        height = $rect.Bottom - $rect.Top
    }
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "no command JSON on stdin" }
    $req = $raw | ConvertFrom-Json
    $op = [string]$req.op
    if ($op -eq "probe") {
        Write-Result ([ordered]@{ ok = $true; backend = "uia"; assembly = "UIAutomationClient" })
        exit 0
    }
    if ($op -eq "start-apps") {
        $apps = @(Get-StartApps | Select-Object Name, AppID)
        Write-Result ([ordered]@{ ok = $true; backend = "uia"; apps = $apps })
        exit 0
    }
    $hwnd = [long]$req.hwnd
    if ($hwnd -eq 0) { throw "missing hwnd" }
    $ptr = [IntPtr]$hwnd

    if ($req.activate -ne $false) {
        if ([UiaWin32]::IsIconic($ptr)) { [void][UiaWin32]::ShowWindow($ptr, 9) }
        [void][UiaWin32]::SetForegroundWindow($ptr)
        Start-Sleep -Milliseconds 200
    }

    if ($op -eq "tree") {
        $script:maxElements = 800
        if ($null -ne $req.maxElements) { $script:maxElements = [int]$req.maxElements }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($ptr)
        if ($null -eq $root) { throw "could not create UIA element for window" }
        Walk-Element $root @() 0

        $tree = ($script:lines -join "`n")
        $outDir = [string]$req.outDir
        if ([string]::IsNullOrWhiteSpace($outDir)) { throw "missing outDir" }
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        $treePath = Join-Path $outDir "tree.txt"
        [System.IO.File]::WriteAllText($treePath, $tree, (New-Object System.Text.UTF8Encoding($false)))

        $focused = $null
        try {
            $f = [System.Windows.Automation.AutomationElement]::FocusedElement
            if ($null -ne $f) {
                $focused = (Get-ControlType $f) + " " + [string](Safe-Get { $f.Current.Name } "")
            }
        } catch { }

        $stateId = [int](Get-Date -UFormat %s)
        $win = Get-WindowInfo $hwnd
        $stateFile = Join-Path $outDir "state.json"
        $state = [ordered]@{
            version = 2
            backend = "uia"
            stateId = $stateId
            createdAt = (Get-Date).ToString("o")
            window = $win
            elements = @($script:elements)
            treePath = $treePath
        }
        [System.IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))

        $maxText = 30000
        if ($null -ne $req.maxText) { $maxText = [int]$req.maxText }
        $truncated = $tree.Length -gt $maxText
        if ($truncated) { $tree = $tree.Substring(0, $maxText) }

        Write-Result ([ordered]@{
            ok = $true
            backend = "uia"
            window = $win
            stateId = $stateId
            tree = $tree
            treeTruncated = $truncated
            treePath = $treePath
            stateFile = $stateFile
            elementCount = $script:counter
            focusedElement = $focused
        })
        exit 0
    }

    if ($op -eq "element") {
        $state = Load-State ([string]$req.stateFile)
        $entry = @($state.elements | Where-Object { $_.index -eq [int]$req.element })[0]
        if ($null -eq $entry) { throw "element not found in state file" }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($ptr)
        $el = Find-Element $root $entry
        if ($null -eq $el) { throw "element is no longer present; refresh state" }
        $rect = Safe-Get { $el.Current.BoundingRectangle } $null
        $offscreen = [bool](Safe-Get { $el.Current.IsOffscreen } $false)
        $x = 0; $y = 0; $w = 0; $h = 0
        if ($null -ne $rect) { $x = To-Int $rect.X; $y = To-Int $rect.Y; $w = To-Int $rect.Width; $h = To-Int $rect.Height }
        if ($offscreen -or $w -le 0 -or $h -le 0) {
            $scrollObj = $null
            try {
                if ($el.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scrollObj)) {
                    $scrollObj.ScrollIntoView()
                    Start-Sleep -Milliseconds 120
                    $rect = Safe-Get { $el.Current.BoundingRectangle } $null
                    if ($null -ne $rect) { $x = To-Int $rect.X; $y = To-Int $rect.Y; $w = To-Int $rect.Width; $h = To-Int $rect.Height }
                }
            } catch { }
        }
        Write-Result ([ordered]@{
            ok = $true
            backend = "uia"
            window = $state.window
            element = [ordered]@{
                index = $entry.index
                controlType = $entry.controlType
                name = $entry.name
                automationId = $entry.automationId
                patterns = $entry.patterns
                rect = [ordered]@{ x = $x; y = $y; width = $w; height = $h }
            }
        })
        exit 0
    }

    if ($op -eq "set-value") {
        $state = Load-State ([string]$req.stateFile)
        $entry = @($state.elements | Where-Object { $_.index -eq [int]$req.element })[0]
        if ($null -eq $entry) { throw "element not found in state file" }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($ptr)
        $el = Find-Element $root $entry
        if ($null -eq $el) { throw "element is no longer present; refresh state" }
        $obj = $null
        try {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$obj)) {
                throw "element does not support ValuePattern"
            }
            $obj.SetValue([string]$req.value)
        } catch {
            Write-Result ([ordered]@{ ok = $false; error = [ordered]@{ message = $_.Exception.Message; code = "VALUE_UNSUPPORTED" } })
            exit 1
        }
        Write-Result ([ordered]@{ ok = $true; backend = "uia"; window = $state.window; action = "set-value"; element = [int]$req.element })
        exit 0
    }

    if ($op -eq "invoke") {
        $state = Load-State ([string]$req.stateFile)
        $entry = @($state.elements | Where-Object { $_.index -eq [int]$req.element })[0]
        if ($null -eq $entry) { throw "element not found in state file" }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($ptr)
        $el = Find-Element $root $entry
        if ($null -eq $el) { throw "element is no longer present; refresh state" }
        $action = [string]$req.action
        $method = $null
        $obj = $null
        if ($action -eq "" -or $action -match '^(click|invoke)$') {
            if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$obj)) {
                $obj.Invoke(); $method = "Invoke"
            } elseif ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$obj)) {
                $obj.Select(); $method = "SelectionItem"
            } elseif ($el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$obj)) {
                $obj.Toggle(); $method = "Toggle"
            } elseif ($el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$obj)) {
                $obj.Expand(); $method = "ExpandCollapse"
            } else {
                $el.SetFocus(); $method = "SetFocus"
            }
        } elseif ($action -match '^(close)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$obj)) { throw "element does not support Window.Close" }
            $obj.Close(); $method = "Window.Close"
        } elseif ($action -match '^(expand)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$obj)) { throw "element does not support ExpandCollapse" }
            $obj.Expand(); $method = "Expand"
        } elseif ($action -match '^(collapse)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$obj)) { throw "element does not support ExpandCollapse" }
            $obj.Collapse(); $method = "Collapse"
        } elseif ($action -match '^(select)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$obj)) { throw "element does not support SelectionItem" }
            $obj.Select(); $method = "SelectionItem"
        } elseif ($action -match '^(toggle)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$obj)) { throw "element does not support Toggle" }
            $obj.Toggle(); $method = "Toggle"
        } elseif ($action -match '^(scrollintoview|scroll)$') {
            if (-not $el.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$obj)) { throw "element does not support ScrollItem" }
            $obj.ScrollIntoView(); $method = "ScrollIntoView"
        } elseif ($action -match '^(focus|setfocus|raise)$') {
            $el.SetFocus(); $method = "SetFocus"
        } else {
            throw "unsupported UIA action: $action"
        }
        Write-Result ([ordered]@{ ok = $true; backend = "uia"; window = $state.window; action = "invoke"; element = [int]$req.element; method = $method })
        exit 0
    }

    throw "unknown op: $op"
}
catch {
    $message = $_.Exception.Message
    $code = "UIA_ERROR"
    if ($message -match "no longer present|not found in state file") { $code = "ELEMENT_NOT_FOUND" }
    Write-Result ([ordered]@{ ok = $false; backend = "uia"; error = [ordered]@{ message = $message; type = $_.Exception.GetType().Name; code = $code } })
    exit 1
}

param(
  [string]$Exe = 'F:\PRPR\app\build\windows\x64\runner\Release\PRPR.exe',
  [int]$Wait = 8,
  [string]$Out = 'F:\PRPR\shot.png',
  [int[][]]$Clicks = @(),
  [int]$AfterClick = 6,
  [switch]$Keep,
  [switch]$NoProxy,
  [switch]$DeadProxy
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PrprWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT r, int size);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
# 必须先把所有大小写的代理变量删干净再设。
# Windows 允许 http_proxy / HTTP_PROXY 两个大小写不同的键同时存在（实测 cmd /c set
# 会打出两行），而 Dart 的 Platform.environment 里后者覆盖前者 —— 直接覆盖大写键
# 时，系统里原有的小写那份仍然生效，于是「死代理」实测照样连上了 127.0.0.1:7897。
function Reset-ProxyEnv {
  Get-ChildItem Env: |
    Where-Object { $_.Name -match '(?i)^(https?_proxy|all_proxy)$' } |
    ForEach-Object { Remove-Item "Env:$($_.Name)" -ErrorAction SilentlyContinue }
}
if ($DeadProxy) {
  # 指向一个没人监听的端口，用来截「网络不通」的错误页。
  # 光清环境变量不够：SystemProxy 会退回去读 Windows 系统代理，照样能联网，
  # 所以这里反过来——设一个连不上的代理，让它走代理而不是走注册表。
  Reset-ProxyEnv
  $env:HTTP_PROXY='http://127.0.0.1:9'; $env:HTTPS_PROXY='http://127.0.0.1:9'
} elseif ($NoProxy) {
  Reset-ProxyEnv
} else {
  Reset-ProxyEnv
  $env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'
}
# 本进程按物理像素取窗口矩形，否则 150% 缩放下 GetWindowRect 给逻辑坐标、
# 后端按物理坐标拷，截出来的图会偏移并被裁掉一截。
[void][PrprWin]::SetProcessDPIAware()

# 窗口矩形必须用 DWM 的扩展边框，不能用 GetWindowRect：后者把 Win10/11 那圈
# 不可见的窗口阴影也算进去（实测左右下各 9px），拷屏会带进桌面上压着的别的窗口。
function Get-VisibleRect($h) {
  $r = New-Object PrprWin+RECT
  if ([PrprWin]::DwmGetWindowAttribute($h, 9, [ref]$r, 16) -ne 0) {
    [void][PrprWin]::GetWindowRect($h, [ref]$r)
  }
  return $r
}

$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds $Wait
if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { "PROCESS DIED before screenshot"; exit 1 }
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "no MainWindowHandle"; Stop-Process -Id $p.Id -Force; exit 1 }
[void][PrprWin]::ShowWindow($h, 9)
[void][PrprWin]::SetForegroundWindow($h)
# 置顶 + 挪到屏幕左上角（保留原尺寸）：窗口可能比屏幕可视区大，
# 不挪位置的话右侧/底部会落在屏幕外，拷屏拿到的是别的窗口或黑色。
# 0x0041 = SWP_NOSIZE | SWP_SHOWWINDOW，HWND_TOP = -1。
[void][PrprWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0041)
Start-Sleep -Milliseconds 1200

if ($Clicks.Count -gt 0) {
  foreach ($c in $Clicks) {
    $cr = Get-VisibleRect $h
    $x = $cr.Left + $c[0]
    $y = $cr.Top + $c[1]
    [void][PrprWin]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 200
    [PrprWin]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [PrprWin]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 600
  }
  Start-Sleep -Seconds $AfterClick
}

$r = Get-VisibleRect $h
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"shot saved: $Out ($w x $ht) at ($($r.Left),$($r.Top)), pid $($p.Id)"
if (-not $Keep) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "process stopped" } else { "process kept running" }

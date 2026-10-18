param(
  [string]$Exe = 'F:\PRPR\app\build\windows\x64\runner\Release\PRPR.exe',
  [int]$Wait = 8,
  [string]$Out = 'F:\PRPR\shot.png',
  [switch]$Keep,
  [switch]$NoProxy
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PrprWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
if ($NoProxy) {
  # 模拟双击快捷方式启动：清掉代理环境变量，只留 Windows 系统代理设置
  Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY,Env:http_proxy,Env:https_proxy -ErrorAction SilentlyContinue
} else {
  $env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'
}
# 必须让本进程按物理像素取窗口矩形，否则 125% 缩放下 GetWindowRect 给逻辑坐标、
# CopyFromScreen 按物理坐标拷，截出来的图会偏移并被裁掉一截。
[void][PrprWin]::SetProcessDPIAware()
$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds $Wait
if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { "PROCESS DIED before screenshot"; exit 1 }
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { "no MainWindowHandle"; Stop-Process -Id $p.Id -Force; exit 1 }
$r = New-Object PrprWin+RECT
[void][PrprWin]::GetWindowRect($h, [ref]$r)
[void][PrprWin]::ShowWindow($h, 9)
[void][PrprWin]::SetForegroundWindow($h)
# 置顶，否则被浏览器等窗口挡住，拷屏拷到的是别人的窗口
[void][PrprWin]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0043)
Start-Sleep -Milliseconds 1200
[void][PrprWin]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"shot saved: $Out ($w x $ht), pid $($p.Id)"
if (-not $Keep) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; "process stopped" } else { "process kept running" }

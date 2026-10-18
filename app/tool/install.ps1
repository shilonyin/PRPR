<#
  把 PRPR 安装到当前用户目录，并创建开始菜单 / 桌面快捷方式。
  不需要管理员权限，不写注册表（卸载就是删目录 + 删两个快捷方式）。

  用法：
    powershell -ExecutionPolicy Bypass -File install.ps1
    powershell -ExecutionPolicy Bypass -File install.ps1 -NoDesktopShortcut -NoLaunch
#>
[CmdletBinding()]
param(
  [string]$Source,
  [string]$InstallDir,
  [switch]$NoDesktopShortcut,
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

# 刻意不在 param 默认值里用 $PSScriptRoot：用 -File 调用时那里还是空的（实测 PS 5.1），
# 放到脚本体里才有值。同理 $InstallDir 的默认值也只能在这里算。
if (-not $Source) { $Source = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release' }
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\PRPR' }

if (-not (Test-Path -LiteralPath (Join-Path $Source 'PRPR.exe'))) {
  throw "找不到 PRPR.exe，请先构建：flutter build windows --release（当前查找位置：$Source）"
}

Write-Host "安装目录：$InstallDir"
if (Test-Path -LiteralPath $InstallDir) {
  # 正在运行的实例会锁住 dartcv.dll 之类被加载的文件，必须先把进程停掉，
  # 否则 Remove-Item 会半途失败、留下一个残缺的安装目录。
  $running = @(Get-Process -Name 'PRPR' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) {
    Write-Host "先关闭正在运行的 $($running.Count) 个 PRPR 实例"
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Process -Name 'PRPR' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 100
    }
  }
  Write-Host '清理旧文件'
  Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# 复制整个 Release 目录（exe + flutter_windows.dll + data\）
Copy-Item -Path (Join-Path $Source '*') -Destination $InstallDir -Recurse -Force
$exe = Join-Path $InstallDir 'PRPR.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw '复制后仍找不到 PRPR.exe' }

# ---- 快捷方式 ----
$shell = New-Object -ComObject WScript.Shell
function New-PrprShortcut([string]$Path) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $lnk = $shell.CreateShortcut($Path)
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $InstallDir
  $lnk.IconLocation = "$exe,0"
  $lnk.Description = 'PRPR — Moebooru 壁纸客户端'
  $lnk.Save()
  Write-Host "快捷方式：$Path"
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-PrprShortcut (Join-Path $startMenu 'PRPR.lnk')
if (-not $NoDesktopShortcut) {
  New-PrprShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PRPR.lnk')
}

# ---- 卸载脚本 ----
$uninstallLines = @(
  '# 卸载 PRPR：删除安装目录、桌面快捷方式、开始菜单快捷方式。',
  '$ErrorActionPreference = ''SilentlyContinue''',
  'Get-Process -Name ''PRPR'' | Stop-Process -Force',
  '$dir = Split-Path -Parent $MyInvocation.MyCommand.Path',
  '$desktop = Join-Path ([Environment]::GetFolderPath(''Desktop'')) ''PRPR.lnk''',
  '$startMenu = Join-Path $env:APPDATA ''Microsoft\Windows\Start Menu\Programs\PRPR.lnk''',
  'Remove-Item -LiteralPath $desktop -Force',
  'Remove-Item -LiteralPath $startMenu -Force',
  'Write-Host ''已删除快捷方式''',
  'Write-Host "应用数据（设置、下载的壁纸、历史）仍在：$env:APPDATA\io.github.shilonyin\prpr"',
  'Start-Sleep -Milliseconds 500',
  'Set-Location $env:TEMP',
  'Remove-Item -LiteralPath $dir -Recurse -Force',
  'Write-Host "已删除 $dir"'
)
Set-Content -LiteralPath (Join-Path $InstallDir '卸载.ps1') -Value $uninstallLines -Encoding UTF8

Write-Host ''
Write-Host "安装完成：$exe"
if (-not $NoLaunch) {
  Start-Process -FilePath $exe -WorkingDirectory $InstallDir
  Write-Host '已启动 PRPR'
}

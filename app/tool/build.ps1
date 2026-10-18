<#
    构建辅助脚本。

    存在的唯一理由：opencv_dart 通过 native assets hook 编译 OpenCV，
    而它需要一个能被 Flutter 认出版本号的 CMake 在 PATH 里。
    很多机器上 CMake 装着但不在 PATH（或者只在 Android SDK 里），
    于是 `flutter test` 会在 "Building native assets failed" 处莫名其妙地失败。

    用法：
        pwsh -File tool/build.ps1            # 分析 + 测试
        pwsh -File tool/build.ps1 -Release   # 额外产出 release 版 exe
#>
[CmdletBinding()]
param(
    [switch]$Release,
    [string[]]$CmakeCandidates = @(
        'C:\tools\cmake\bin',
        'C:\Program Files\CMake\bin',
        'C:\Program Files (x86)\CMake\bin',
        'C:\Users\24243\AppData\Local\Android\Sdk\cmake\3.22.1\bin'
    )
)

$ErrorActionPreference = 'Stop'
$appRoot = Split-Path -Parent $PSScriptRoot
Push-Location $appRoot
try {
    # --- 找一个可用的 cmake ---
    $cmakeBin = $CmakeCandidates |
        Where-Object { Test-Path (Join-Path $_ 'cmake.exe') } |
        Select-Object -First 1

    if ($cmakeBin) {
        Write-Host "使用 CMake: $cmakeBin"
        $env:PATH = "$cmakeBin;$env:PATH"
    } else {
        $onPath = Get-Command cmake -ErrorAction SilentlyContinue
        if (-not $onPath) {
            throw "找不到 cmake.exe。请安装 CMake 并把它的 bin 目录加进 PATH，" +
                  "或修改本脚本的 -CmakeCandidates 参数。"
        }
        Write-Host "使用 PATH 上的 CMake: $($onPath.Source)"
    }
    & cmake --version | Select-Object -First 1

    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutter) { throw '找不到 flutter 命令，请先把 Flutter SDK 的 bin 目录加进 PATH。' }

    Write-Host '=== flutter pub get ===' -ForegroundColor Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get 失败' }

    Write-Host '=== flutter analyze ===' -ForegroundColor Cyan
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 未通过' }

    Write-Host '=== flutter test ===' -ForegroundColor Cyan
    # 首次运行会从源码编译 OpenCV，可能要十几分钟；之后走缓存。
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test 未通过' }

    if ($Release) {
        Write-Host '=== flutter build windows --release ===' -ForegroundColor Cyan
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'release 构建失败' }
        Write-Host "产物: $appRoot\build\windows\x64\runner\Release\PRPR.exe" -ForegroundColor Green
    }

    Write-Host '全部通过。' -ForegroundColor Green
}
finally {
    Pop-Location
}

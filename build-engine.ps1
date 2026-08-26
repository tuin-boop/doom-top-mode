param(
    [string]$Source = (Join-Path $PSScriptRoot 'runtime\uzdoom-cutaway-src'),
    [ValidateSet('Release', 'RelWithDebInfo')]
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

$upstreamCommit = '4ca590945524330d94530c0558c8d547d457e16c'
$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$cmake = if ($cmakeCommand) { $cmakeCommand.Source } else {
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
}
$python = if ($pythonCommand) { $pythonCommand.Source } else { $null }
$build = Join-Path $Source 'build-cutaway'
$patch = Join-Path $PSScriptRoot 'renderer\uzdoom-ortho-renderer.patch'
$target = Join-Path $PSScriptRoot 'runtime\uzdoom-cutaway'
$stock = Join-Path $PSScriptRoot 'runtime\uzdoom'

if (-not (Test-Path -LiteralPath $Source)) {
    & git clone https://github.com/UZDoom/UZDoom.git $Source
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone UZDoom.' }
    & git -C $Source checkout $upstreamCommit
    if ($LASTEXITCODE -ne 0) { throw 'Could not check out the supported UZDoom revision.' }
}
if (-not (Test-Path -LiteralPath $cmake)) { throw "CMake is missing: $cmake" }
if (-not $python -or -not (Test-Path -LiteralPath $python)) { throw 'Python 3 is missing from PATH.' }
if (-not (Test-Path -LiteralPath $stock)) {
    & (Join-Path $PSScriptRoot 'setup.ps1')
}

$alreadyPatched = Select-String -LiteralPath (Join-Path $Source 'src\common\rendering\hwrenderer\data\hw_vrmodes.cpp') -SimpleMatch 'r_ortho_cutaway' -Quiet
if (-not $alreadyPatched) {
    & git -C $Source apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'Could not apply ortho-cutaway.patch.' }
}

& $cmake -S $Source -B $build -G 'Visual Studio 17 2022' -A x64 "-DPython3_EXECUTABLE=$python"
if ($LASTEXITCODE -ne 0) { throw 'UZDoom configuration failed.' }

& $cmake --build $build --config $Configuration --parallel 16
if ($LASTEXITCODE -ne 0) { throw 'UZDoom compilation failed.' }

$builtExe = Join-Path $build "$Configuration\uzdoom.exe"
if (-not (Test-Path -LiteralPath $builtExe)) { throw "Built executable was not found: $builtExe" }
$builtCore = Join-Path $build 'uzdoom.pk3'
if (-not (Test-Path -LiteralPath $builtCore)) { throw "Built core package was not found: $builtCore" }

New-Item -ItemType Directory -Path $target -Force | Out-Null
Get-ChildItem -LiteralPath $stock | Copy-Item -Destination $target -Recurse -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $target 'uzdoom.exe') -Force
Copy-Item -LiteralPath $builtCore -Destination (Join-Path $target 'uzdoom.pk3') -Force

Write-Host "Custom renderer installed at $target"

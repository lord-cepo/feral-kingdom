param([string] $Output = "exports/FeralKingdomLauncher.exe")

$ErrorActionPreference = "Stop"
$compiler = Join-Path $env:WINDIR "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
$source = Join-Path $PSScriptRoot "Launcher.cs"
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$Output" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll $source
exit $LASTEXITCODE

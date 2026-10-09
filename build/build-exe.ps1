# Rebuilds "Convert EML to PDF.exe" from convert-eml-to-pdf.bat. Run after editing the .bat.
$dir = Split-Path $PSScriptRoot
$bat = Get-Content -LiteralPath "$dir\convert-eml-to-pdf.bat" -Raw
$ps = ($bat -split ('#PS' + 'START\r?\n'), 2)[1]
$ps1 = "$PSScriptRoot\script.ps1"
[IO.File]::WriteAllText($ps1, $ps, (New-Object Text.UTF8Encoding $true))
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /out:"$dir\Convert EML to PDF.exe" /win32icon:"$dir\assets\convert-eml-to-pdf.ico" /resource:"$ps1,script.ps1" "$PSScriptRoot\launcher.cs"
Remove-Item $ps1



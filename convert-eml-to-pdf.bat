@echo off
rem Drag one or more .eml files onto this file, or double-click it to pick files, to create tagged PDFs.
rem Each PDF is saved next to its .eml file.
setlocal
set "EML_ARGS=%*"
set "EML_SELF=%~f0"
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$s = (Get-Content -LiteralPath $env:EML_SELF -Raw) -split ('#PS' + 'START\r?\n'), 2; & ([scriptblock]::Create($s[1]))"
exit /b
#PSSTART
$ErrorActionPreference = 'Stop'

function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

function ConvertTo-PdfText([string]$value) {
    '<FEFF' + [BitConverter]::ToString([Text.Encoding]::BigEndianUnicode.GetBytes($value)).Replace('-', '') + '>'
}

function Set-PdfMetadata([string]$pdfPath, [string]$title, [string]$author) {
    $bytes = [IO.File]::ReadAllBytes($pdfPath)
    $pdf = [Text.Encoding]::ASCII.GetString($bytes)
    $trailerMatch = [regex]::Match($pdf, '(?s)trailer\s*<<(.*?)>>\s*startxref\s+(\d+)\s*%%EOF\s*$')
    if (-not $trailerMatch.Success) { throw 'Could not read the PDF trailer.' }

    $trailer = $trailerMatch.Groups[1].Value
    $sizeMatch = [regex]::Match($trailer, '/Size\s+(\d+)')
    $rootMatch = [regex]::Match($trailer, '/Root\s+(\d+\s+\d+\s+R)')
    $infoMatch = [regex]::Match($trailer, '/Info\s+(\d+)\s+(\d+)\s+R')
    if (-not $sizeMatch.Success -or -not $rootMatch.Success -or -not $infoMatch.Success) {
        throw 'The PDF trailer is missing required document references.'
    }

    $objectNumber = [int]$infoMatch.Groups[1].Value
    $generation = [int]$infoMatch.Groups[2].Value
    $objectPattern = '(?s)(?m)^' + $objectNumber + '\s+' + $generation + '\s+obj\s*<<(.*?)>>\s*endobj'
    $objectMatch = [regex]::Match($pdf, $objectPattern)
    if (-not $objectMatch.Success) { throw 'Could not read the PDF metadata object.' }

    $metadata = $objectMatch.Groups[1].Value
    $values = @{
        Title = ConvertTo-PdfText $title
        # Author = ConvertTo-PdfText $author
    }
    foreach ($key in $values.Keys) {
        $pattern = '/' + $key + '\s+(?:\((?:\\.|[^\\)])*\)|<[^>]*>)'
        if ([regex]::IsMatch($metadata, $pattern)) {
            $metadata = [regex]::Replace($metadata, $pattern, '/' + $key + ' ' + $values[$key], 1)
        } else {
            $metadata += "`n/$key $($values[$key])"
        }
    }

    $priorXref = $trailerMatch.Groups[2].Value
    $xrefOffset = $bytes.Length
    $prefix = if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10 -and $bytes[$bytes.Length - 1] -ne 13) { "`n" } else { '' }
    $xrefOffset += [Text.Encoding]::ASCII.GetByteCount($prefix)
    $newObject = "`n$objectNumber $generation obj`n<<$metadata`n>>`nendobj`n"
    $newXrefOffset = $xrefOffset + [Text.Encoding]::ASCII.GetByteCount($newObject)
    $xref = "xref`n$objectNumber 1`n$('{0:D10}' -f $xrefOffset) $('{0:D5}' -f $generation) n `n"
    $newTrailer = "trailer`n<< /Size $($sizeMatch.Groups[1].Value) /Root $($rootMatch.Groups[1].Value) /Info $objectNumber $generation R /Prev $priorXref"
    $idMatch = [regex]::Match($trailer, '/ID\s*(\[[^\]]*\])')
    if ($idMatch.Success) { $newTrailer += ' /ID ' + $idMatch.Groups[1].Value }
    $newTrailer += " >>`nstartxref`n$newXrefOffset`n%%EOF`n"

    $stream = [IO.File]::Open($pdfPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $append = [Text.Encoding]::ASCII.GetBytes($prefix + $newObject + $xref + $newTrailer)
        $stream.Write($append, 0, $append.Length)
    } finally {
        $stream.Dispose()
    }
}

$files = [regex]::Matches([string]$env:EML_ARGS, '"([^"]+)"|(\S+)') | ForEach-Object {
    if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
}

# Double-clicked with no files: show a window to drop or browse for .eml files
if (-not $files) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $script:picked = @()

    $form = New-Object Windows.Forms.Form
    $form.Text = 'EML to Tagged PDF'
    $form.ClientSize = New-Object Drawing.Size(460, 240)
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.AllowDrop = $true

    $drop = New-Object Windows.Forms.Label
    $drop.Text = "Drag and drop .eml files here`r`n`r`nor"
    $drop.TextAlign = 'MiddleCenter'
    $drop.Font = New-Object Drawing.Font('Segoe UI', 12)
    $drop.BorderStyle = 'FixedSingle'
    $drop.SetBounds(20, 20, 420, 140)
    $drop.AllowDrop = $true

    $browse = New-Object Windows.Forms.Button
    $browse.Text = 'Select .eml files...'
    $browse.Font = New-Object Drawing.Font('Segoe UI', 11)
    $browse.SetBounds(130, 175, 200, 40)

    $accept = {
        param($s, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' }
    }
    $take = {
        param($s, $e)
        $dropped = @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop) | Where-Object { $_ -like '*.eml' })
        if ($dropped) { $script:picked = $dropped; $form.Close() }
    }
    foreach ($c in @($form, $drop)) { $c.Add_DragEnter($accept); $c.Add_DragDrop($take) }

    $browse.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Email files (*.eml)|*.eml'
        $dlg.Multiselect = $true
        if ($dlg.ShowDialog($form) -eq 'OK') { $script:picked = $dlg.FileNames; $form.Close() }
    })

    $form.Controls.Add($drop)
    $form.Controls.Add($browse)
    [void]$form.ShowDialog()
    $files = $script:picked
}
if (-not $files) { return }

$browser = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $browser) { return }

$work = Join-Path $env:TEMP ('eml2pdf_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$profileDir = Join-Path $work 'profile'

function Get-AllParts($part) {
    $part
    $bp = $part.BodyParts
    for ($i = 1; $i -le $bp.Count; $i++) { Get-AllParts $bp.Item($i) }
}

foreach ($path in $files) {
    $name = Split-Path $path -Leaf
    try {
        if (-not (Test-Path -LiteralPath $path)) { throw 'File not found.' }
        if ([IO.Path]::GetExtension($path) -ne '.eml') { throw 'Not an .eml file.' }

        # Parse the email with Windows' built-in CDO library
        $stream = New-Object -ComObject ADODB.Stream
        $stream.Open()
        $stream.LoadFromFile($path)
        $msg = New-Object -ComObject CDO.Message
        $msg.DataSource.OpenObject($stream, '_Stream')
        $stream.Close()

        $subject = [string]$msg.Subject
        if (-not $subject.Trim()) { $subject = [IO.Path]::GetFileNameWithoutExtension($path) }
        # Author metadata disabled
        # $author = [string]$msg.From
        # try {
        #     $sender = New-Object -TypeName System.Net.Mail.MailAddress -ArgumentList $author
        #     if ($sender.DisplayName) { $author = $sender.DisplayName } else { $author = $sender.Address }
        # } catch { }
        $date = ''
        try { $date = ([datetime]$msg.SentOn).ToString('dddd, MMMM d, yyyy h:mm tt') } catch { }
        if (-not $date) { try { $date = [string]$msg.Fields.Item('urn:schemas:mailheader:date').Value } catch { } }

        $attachNames = @()
        for ($i = 1; $i -le $msg.Attachments.Count; $i++) {
            $fn = [string]$msg.Attachments.Item($i).FileName
            if ($fn) { $attachNames += $fn }
        }

        # Body: prefer HTML, fall back to plain text
        $styles = ''
        $htmlBody = [string]$msg.HTMLBody
        if ($htmlBody.Trim()) {
            $styles = ([regex]::Matches($htmlBody, '(?is)<style\b.*?</style>') | ForEach-Object { $_.Value }) -join "`n"
            $m = [regex]::Match($htmlBody, '(?is)<body\b[^>]*>(.*)</body>')
            $inner = if ($m.Success) { $m.Groups[1].Value } else { $htmlBody }

            # Embed inline images (cid: references) so they render in the PDF
            foreach ($p in (Get-AllParts $msg.BodyPart)) {
                $cid = ''
                try { $cid = [string]$p.Fields.Item('urn:schemas:mailheader:content-id').Value } catch { }
                $cid = $cid.Trim().Trim('<', '>')
                if ($cid -and $inner -match ('(?i)cid:' + [regex]::Escape($cid))) {
                    $ds = $p.GetDecodedContentStream()
                    $ds.Type = 1
                    $b64 = [Convert]::ToBase64String([byte[]]$ds.Read())
                    $ds.Close()
                    $mime = [string]$p.ContentMediaType
                    if (-not $mime) { $mime = 'image/png' }
                    $inner = $inner -replace ('(?i)cid:' + [regex]::Escape($cid)), ("data:$mime;base64,$b64")
                }
            }
        } else {
            $text = [string]$msg.TextBody
            $inner = ($text -split '\r?\n\s*\r?\n' | Where-Object { $_.Trim() } | ForEach-Object {
                '<p>' + ((Enc $_.Trim()) -replace '\r?\n', '<br>') + '</p>'
            }) -join "`n"
        }

        # Header block as aligned label/value rows
        $rows = ''
        foreach ($pair in @(@('Date', $date), @('From', $msg.From), @('To', $msg.To), @('Cc', $msg.CC), @('Subject', $subject), @('Attachments', ($attachNames -join ', ')))) {
            if ([string]$pair[1]) { $rows += '<tr><th scope="row">' + $pair[0] + ':</th><td>' + (Enc ([string]$pair[1])) + "</td></tr>`n" }
        }

        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$(Enc $subject)</title>
$styles
<style>
@page { margin: 0.75in; }
body { font-family: Arial, sans-serif; font-size: 11pt; }
img { max-width: 100%; height: auto; }
.eml-metadata-header { font-family: Arial, sans-serif; font-size: 10pt; }
.eml-metadata-header { padding-bottom: 0.5in; }
.eml-metadata-table { border-collapse: collapse; line-height: 1.35; font-family: Arial, sans-serif; font-size: 10pt; }
.eml-metadata-table th, .eml-metadata-table td { padding: 0 0.4em 0 0; text-align: left; vertical-align: top; border: 0; }
.eml-metadata-table th { width: 6.5em; font-weight: bold; white-space: nowrap; padding-right: 0.8em; }
.eml-metadata-table td { font-weight: normal; }
.eml-metadata-header { background: #fff !important; }
.eml-metadata-header * { background: none !important; }
</style>
</head>
<body>
<div class="eml-metadata-header">
<table class="eml-metadata-table">
$rows</table>
</div>
<div class="eml-body">
$inner
</div>
</body>
</html>
"@

        $htmlPath = Join-Path $work ([guid]::NewGuid().ToString('N') + '.html')
        [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding $false))

        $dir = Split-Path $path -Parent
        $base = [IO.Path]::GetFileNameWithoutExtension($path)
        $out = Join-Path $dir ($base + '.pdf')
        $n = 1
        while (Test-Path -LiteralPath $out) { $out = Join-Path $dir ("$base ($n).pdf"); $n++ }

        $uri = ([Uri]$htmlPath).AbsoluteUri
        $argLine = "--headless=new --disable-gpu --no-first-run --no-pdf-header-footer --export-tagged-pdf --generate-pdf-document-outline --user-data-dir=`"$profileDir`" --print-to-pdf=`"$out`" `"$uri`""
        Start-Process -FilePath $browser -ArgumentList $argLine -Wait -WindowStyle Hidden

        if (-not (Test-Path -LiteralPath $out)) { throw 'The browser did not create the PDF.' }
        Set-PdfMetadata -pdfPath $out -title $subject
    } catch { }
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

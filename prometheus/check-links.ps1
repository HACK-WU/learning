$root = "D:/projects/learning/prometheus"
$bad = 0; $ok = 0
$files = Get-ChildItem -Path $root -Recurse -Filter *.md -File |
         Where-Object { $_.FullName -notmatch '\\_draft\\' }
foreach ($f in $files) {
    $dir = $f.DirectoryName
    $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    if (-not $content) { continue }
    $matches = [regex]::Matches($content, '\]\(([^)]+)\)')
    foreach ($m in $matches) {
        $t = $m.Groups[1].Value
        $t = ($t -split '#')[0].Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match '^https?://' -or $t -match '^mailto:') { continue }
        $candidate = Join-Path $dir $t
        try { $candidate = [System.IO.Path]::GetFullPath($candidate) } catch {}
        if (Test-Path -LiteralPath $candidate) { $ok++ }
        else { Write-Output "BROKEN: $($f.FullName) -> $t"; $bad++ }
    }
}
Write-Output "----------------------------------------"
Write-Output "OK: $ok   BROKEN: $bad   (已排除 _draft 归档件)"

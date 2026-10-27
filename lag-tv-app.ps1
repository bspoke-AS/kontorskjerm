# Pakker TV-appen for Samsung signage-skjermene (Custom App / URL Launcher).
# Lager én mappe per skjerm under s-s76bs6c5/tv/ med bspoke-tv.wgt og sssp_config.xml.
# Skjermen peker på mappa, f.eks. https://bspoke-as.github.io/kontorskjerm/s-s76bs6c5/tv/1/
# Kjør på nytt (med høyere -Versjon) hvis tv-app/ endres, og commit resultatet.

param(
    [string]$Versjon = '1.0.0'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Repo = $PSScriptRoot
$Kilde = Join-Path $Repo 'tv-app'
$Base = 'https://bspoke-as.github.io/kontorskjerm/s-s76bs6c5/'
$Utf8 = New-Object System.Text.UTF8Encoding $false

# Mappenavn -> parameter til slidesiden
$Skjermer = [ordered]@{
    'alle' = ''
    '1'    = '?s=1'
    '2'    = '?s=2'
    '3'    = '?s=3'
}

$config = [System.IO.File]::ReadAllText((Join-Path $Kilde 'config.xml'), $Utf8).Replace('__VERSJON__', $Versjon)
$side = [System.IO.File]::ReadAllText((Join-Path $Kilde 'index.html'), $Utf8).Replace('__JSON__', $Base + 'slides.json')

foreach ($navn in $Skjermer.Keys) {
    $mappe = Join-Path $Repo "s-s76bs6c5\tv\$navn"
    New-Item -ItemType Directory -Force -Path $mappe | Out-Null
    $wgt = Join-Path $mappe 'bspoke-tv.wgt'
    if (Test-Path -LiteralPath $wgt) { Remove-Item -LiteralPath $wgt -Force }

    $zip = [System.IO.Compression.ZipFile]::Open($wgt, 'Create')
    try {
        $filer = @{
            'config.xml' = $config
            'index.html' = $side.Replace('__URL__', $Base + $Skjermer[$navn])
        }
        foreach ($fil in $filer.Keys) {
            $entry = $zip.CreateEntry($fil)
            $w = New-Object System.IO.StreamWriter($entry.Open(), $Utf8)
            try { $w.Write($filer[$fil]) } finally { $w.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }

    $storrelse = (Get-Item -LiteralPath $wgt).Length
    $sssp = @"
<?xml version="1.0" encoding="UTF-8"?>
<widget>
    <ver>$Versjon</ver>
    <size>$storrelse</size>
    <widgetname>bspoke-tv</widgetname>
    <webtype>tizen</webtype>
</widget>
"@
    [System.IO.File]::WriteAllText((Join-Path $mappe 'sssp_config.xml'), $sssp, $Utf8)

    # Mappeadressen må svare 200: noen skjermer sjekker den før de henter sssp_config.xml.
    # I en vanlig nettleser sender den videre til slidesiden.
    $mal = $Base + $Skjermer[$navn]
    $index = @"
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="robots" content="noindex,nofollow">
<meta http-equiv="refresh" content="0; url=$mal"><title>bspoke kontorskjerm</title></head>
<body style="background:#000"></body></html>
"@
    [System.IO.File]::WriteAllText((Join-Path $mappe 'index.html'), $index, $Utf8)
    '{0,-5} {1,6} byte  -> {2}{3}' -f $navn, $storrelse, $Base, $Skjermer[$navn]
}

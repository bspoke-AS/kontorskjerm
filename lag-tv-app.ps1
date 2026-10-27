# Pakker TV-appen for Samsung signage-skjermene (Custom App / URL Launcher).
# Lager én mappe per skjerm under s-s76bs6c5/tv/ med bspoke-tv.wgt og sssp_config.xml.
# Skjermen peker på mappa, f.eks. https://bspoke-as.github.io/kontorskjerm/s-s76bs6c5/tv/1/
# Kjør på nytt (med høyere -Versjon) hvis tv-app/ endres, og commit resultatet.
#
# Skjermen installerer bare signerte apper. Signeringen gjøres med Tizen Studio CLI og
# signeringsprofilen 'kontorskjerm' (Tizen-forfattersertifikat + Tizens offentlige
# distributørsertifikat). Begge ligger bare lokalt på Henriks PC under %USERPROFILE%\tizen-studio(-data).

param(
    [string]$Versjon = '1.0.1',
    [string]$Profil = 'kontorskjerm',
    [string]$Tizen = "$env:USERPROFILE\tizen-studio\tools\ide\bin\tizen.bat"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Tizen)) { throw "Finner ikke Tizen CLI: $Tizen" }

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

    # Bygg i en tom midlertidig mappe og la Tizen CLI pakke og signere
    $bygg = Join-Path ([System.IO.Path]::GetTempPath()) ("kontorskjerm-tv-" + [guid]::NewGuid().ToString('N'))
    $src = Join-Path $bygg 'src'
    $ut = Join-Path $bygg 'ut'
    New-Item -ItemType Directory -Force -Path $src, $ut | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $src 'config.xml'), $config, $Utf8)
        [System.IO.File]::WriteAllText((Join-Path $src 'index.html'), $side.Replace('__URL__', $Base + $Skjermer[$navn]), $Utf8)

        & $Tizen package -t wgt -s $Profil -o $ut -- $src | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "tizen package feilet for '$navn' (kode $LASTEXITCODE)" }
        $pakket = @(Get-ChildItem -LiteralPath $ut -Filter *.wgt)
        if ($pakket.Count -ne 1) { throw "Fant ikke signert .wgt for '$navn'" }
        Copy-Item -LiteralPath $pakket[0].FullName -Destination $wgt -Force
    } finally {
        Remove-Item -LiteralPath $bygg -Recurse -Force -ErrorAction SilentlyContinue
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

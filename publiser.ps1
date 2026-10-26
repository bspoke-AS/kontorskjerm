# Publiserer kontorskjerm-slidene til GitHub Pages.
# Kopierer PNG-ene fra den SharePoint-synkede Slides-mappa inn i repoet, skriver slides.json
# og gjør commit + push bare hvis noe er endret. Én linje per kjøring logges til publiser.log.

param(
    [string]$Kilde = 'C:\Users\HenrikHolum\bspoke\bspoke - felles - Dokumenter\Prosjekter (internt)\Kontorskjerm\Slides'
)

$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot
$Sti = 's-s76bs6c5'
$Maal = Join-Path $Repo "$Sti\slides"
$Json = Join-Path $Repo "$Sti\slides.json"
$Logg = Join-Path $Repo 'publiser.log'
$Utf8 = New-Object System.Text.UTF8Encoding $false

$endret = 0

function Skriv-Logg([string]$status, [string]$melding) {
    $linje = '{0}  {1,-4}  endret={2}  {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $status, $endret, $melding
    [System.IO.File]::AppendAllText($Logg, $linje + [Environment]::NewLine, $Utf8)
}

function Kjor-Git {
    & git.exe -C $Repo @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') feilet (kode $LASTEXITCODE)" }
}

function Hent-Png([string]$mappe) {
    @(Get-ChildItem -LiteralPath $mappe -File | Where-Object { $_.Extension -eq '.png' } | Sort-Object Name)
}

try {
    if (-not (Test-Path -LiteralPath $Kilde)) { throw "Finner ikke kildemappa: $Kilde" }
    $kildeFiler = Hent-Png $Kilde
    # Tom kildemappe er nesten alltid en synkfeil. Ikke tøm skjermene på grunn av det.
    if ($kildeFiler.Count -eq 0) { throw 'Ingen PNG-er i kildemappa' }

    New-Item -ItemType Directory -Force -Path $Maal | Out-Null

    # 1. Kopier nye og endrede bilder
    foreach ($f in $kildeFiler) {
        $mal = Join-Path $Maal $f.Name
        if (-not (Test-Path -LiteralPath $mal) -or
            (Get-FileHash -LiteralPath $f.FullName).Hash -ne (Get-FileHash -LiteralPath $mal).Hash) {
            Copy-Item -LiteralPath $f.FullName -Destination $mal -Force
            $endret++
        }
    }

    # 2. Fjern bilder som ikke lenger finnes i kilden
    $kildeNavn = @($kildeFiler | ForEach-Object { $_.Name })
    foreach ($f in (Hent-Png $Maal)) {
        if ($kildeNavn -notcontains $f.Name) {
            Remove-Item -LiteralPath $f.FullName -Force
            $endret++
        }
    }

    # 3. Skriv slides.json når bildene er endret (eller lista ikke stemmer)
    $gammelListe = ''
    if (Test-Path -LiteralPath $Json) {
        try { $gammelListe = (@((Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json).slides) -join '|') } catch { }
    }
    if ($endret -gt 0 -or $gammelListe -ne ($kildeNavn -join '|')) {
        $data = [ordered]@{
            oppdatert = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
            slides    = $kildeNavn
        }
        [System.IO.File]::WriteAllText($Json, (ConvertTo-Json -InputObject $data), $Utf8)
    }

    # 4. Commit og push bare hvis noe er endret
    Kjor-Git add -A -- "$Sti/slides" "$Sti/slides.json"
    & git.exe -C $Repo diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        Kjor-Git commit -q -m ("Oppdater slides " + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
    }

    # Pusher også commits som ble liggende igjen etter en tidligere feilet push
    $upstream = Kjor-Git for-each-ref --format='%(upstream:short)' refs/heads/main
    if ($upstream) {
        $foran = [int](Kjor-Git rev-list --count '@{u}..HEAD')
    } else {
        $foran = 1   # første push, ingen upstream ennå
    }
    if ($foran -gt 0) {
        Kjor-Git push -q -u origin main
        Skriv-Logg 'OK' 'pushet'
    } else {
        Skriv-Logg 'OK' 'ingen endringer'
    }
}
catch {
    Skriv-Logg 'FEIL' $_.Exception.Message
    exit 1
}

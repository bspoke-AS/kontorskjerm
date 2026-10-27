# Gjør en ledig Windows-PC om til spiller for kontorskjermen (virker også på Windows Home).
# Kjøres én gang i PowerShell som administrator på skjerm-PC-en:
#
#   irm https://bspoke-as.github.io/kontorskjerm/pc.ps1 | iex
#
# Skriptet:
#  - lager standardbrukeren «Kontorskjerm» med et tilfeldig passord ingen trenger å kunne
#  - logger den inn automatisk ved oppstart
#  - starter Edge i fullskjerm-kiosk med slidesiden når nettet er oppe, og på nytt hvis Edge lukkes
#  - slår av hvilemodus og skjermsparing på strøm, og lar PC-en stå med lokket lukket
#
# Angre: slett brukeren Kontorskjerm og oppgaven «Kontorskjerm» i Oppgaveplanleggeren,
# og sett AutoAdminLogon til 0 under HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon.

& {
    $ErrorActionPreference = 'Stop'
    $Base = 'https://bspoke-as.github.io/kontorskjerm/s-s76bs6c5/'
    $Bruker = 'Kontorskjerm'
    $Mappe = Join-Path $env:ProgramData 'Kontorskjerm'

    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Start PowerShell som administrator og kjor pa nytt.' -ForegroundColor Red
        return
    }

    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
              "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw 'Finner ikke Microsoft Edge.' }

    # Hvilke slider denne skjermen skal vise
    $valg = (Read-Host 'Hvilke slider? Trykk Enter for alle, eller skriv f.eks. 1 eller 2,3') -replace '\s', ''
    if ($valg -and $valg -notmatch '^\d+(,\d+)*$') { throw "Ugyldig valg: $valg" }
    $url = if ($valg) { $Base + '?s=' + $valg } else { $Base }

    # 1. Egen standardbruker med tilfeldig passord
    $tegn = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $passord = -join ($bytes | ForEach-Object { $tegn[$_ % $tegn.Length] })
    $sikker = ConvertTo-SecureString $passord -AsPlainText -Force
    if (Get-LocalUser -Name $Bruker -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $Bruker -Password $sikker -PasswordNeverExpires $true
    } else {
        New-LocalUser -Name $Bruker -Password $sikker -FullName 'Kontorskjerm' -Description 'Viser kontorskjermen' `
            -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
        Add-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-545').Name -Member $Bruker
    }

    function Sett-Verdi([string]$sti, [string]$navn, $verdi, [string]$type = 'DWord') {
        if (-not (Test-Path -LiteralPath $sti)) { New-Item -Path $sti -Force | Out-Null }
        New-ItemProperty -LiteralPath $sti -Name $navn -Value $verdi -PropertyType $type -Force | Out-Null
    }

    # 2. Automatisk innlogging
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Sett-Verdi $wl 'AutoAdminLogon' '1' 'String'
    Sett-Verdi $wl 'DefaultUserName' $Bruker 'String'
    Sett-Verdi $wl 'DefaultPassword' $passord 'String'
    Sett-Verdi $wl 'DefaultDomainName' $env:COMPUTERNAME 'String'
    Sett-Verdi $wl 'EnableFirstLogonAnimation' 0
    Remove-ItemProperty -LiteralPath $wl -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
    Sett-Verdi 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' 'DevicePasswordLessBuildVersion' 0
    # Ingen personvern-veiviser ved første innlogging
    Sett-Verdi 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' 'DisablePrivacyExperience' 1

    # 3. Edge uten velkomstsider, innlogging, oversettelse eller bakgrunnsprosesser
    $ep = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Sett-Verdi $ep 'HideFirstRunExperience' 1
    Sett-Verdi $ep 'BrowserSignin' 0
    Sett-Verdi $ep 'SyncDisabled' 1
    Sett-Verdi $ep 'TranslateEnabled' 0
    Sett-Verdi $ep 'BackgroundModeEnabled' 0
    Sett-Verdi $ep 'StartupBoostEnabled' 0

    # 4. Startskript: vent på nett, start Edge i kiosk, start på nytt hvis den lukkes
    New-Item -ItemType Directory -Force -Path $Mappe | Out-Null
    $start = Join-Path $Mappe 'start.ps1'
    $innhold = @"
`$edge = '$edge'
`$url = '$url'
`$sjekk = '${Base}slides.json'
while (`$true) {
    if (-not (Get-Process msedge -ErrorAction SilentlyContinue)) {
        try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 (`$sjekk + '?v=' + [DateTime]::Now.Ticks) | Out-Null } catch { Start-Sleep -Seconds 15; continue }
        Start-Process `$edge -ArgumentList ('--kiosk "' + `$url + '" --edge-kiosk-type=fullscreen --no-first-run')
    }
    Start-Sleep -Seconds 30
}
"@
    [IO.File]::WriteAllText($start, $innhold, (New-Object Text.UTF8Encoding $false))

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$start`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$Bruker"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$Bruker" -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'Kontorskjerm' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    # 5. Strøm: aldri hvile eller slukke skjermen på strøm, ingenting skjer når lokket lukkes
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
    powercfg /setactive SCHEME_CURRENT

    # 6. Windows Update starter ikke PC-en på nytt mellom 06 og 23
    $wu = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    Sett-Verdi $wu 'ActiveHoursStart' 6
    Sett-Verdi $wu 'ActiveHoursEnd' 23
    Sett-Verdi $wu 'SmartActiveHoursState' 0

    Write-Host ''
    Write-Host "Ferdig. Skjermen skal vise: $url" -ForegroundColor Green
    Write-Host 'Start PC-en pa nytt for a teste: Restart-Computer' -ForegroundColor Green
}

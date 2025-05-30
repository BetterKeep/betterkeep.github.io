# Setup folder & file paths
$folder = ".\WebhookFiles"
if (-not (Test-Path $folder)) {
    New-Item -ItemType Directory -Path $folder | Out-Null
}

$nameFile = Join-Path $folder "name.json"
$webhooksFile = Join-Path $folder "webhooks.json"

# Create default name.json if missing
if (-not (Test-Path $nameFile)) {
    $defaultNameData = @{
        name = "James's Webhook manager"
        settings_label = "settings"
    }
    $defaultNameData | ConvertTo-Json | Out-File $nameFile
}

# Create default webhooks.json if missing (empty array)
if (-not (Test-Path $webhooksFile)) {
    @() | ConvertTo-Json | Out-File $webhooksFile
}

# Load name.json (menu titles)
$nameData = Get-Content -Raw -Path $nameFile | ConvertFrom-Json
$title = $nameData.name
$settingsLabel = $nameData.settings_label

# Load or initialize webhooks array
function Load-Webhooks {
    return Get-Content -Raw -Path $webhooksFile | ConvertFrom-Json
}

function Save-Webhooks($list) {
    $list | ConvertTo-Json -Depth 10 | Out-File $webhooksFile
}

# Starter Guide if no webhooks
function Starter-Guide {
    Clear-Host
    Write-Host "Starter's Guide"
    Write-Host "Add a new webhook? (Y/N)"
    $yn = Read-Host
    if ($yn.ToUpper() -eq 'Y') {
        Add-NewWebhook
    } else {
        Write-Host "No webhooks to use. Exiting..."
        Start-Sleep -Seconds 2
        Exit
    }
}

# Add new webhook
function Add-NewWebhook {
    while ($true) {
        $name = Read-Host "Name? (min 2 characters)"
        if ($name.Length -ge 2) { break }
        Write-Host "Name too short." -ForegroundColor Red
    }
    $url = Read-Host "Webhook?"
    while ($true) {
        $password = Read-Host "Password? (Type h!pass for info)" -AsSecureString
        $pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        if ($pwPlain -eq "h!pass") {
            Write-Host "Password is needed to encrypt your webhook URL for security." -ForegroundColor Cyan
            Write-Host "It must be exactly 8 characters long." -ForegroundColor Cyan
            continue
        }
        if ($pwPlain.Length -ne 8) {
            Write-Host "Password must be exactly 8 characters." -ForegroundColor Red
            continue
        }
        break
    }
    $encrypted_url = Encrypt-WebhookUrl -url $url -password $pwPlain
    $salt = [System.Convert]::ToBase64String((New-Object byte[] 16 | ForEach-Object {Get-Random -Maximum 256}))
    $list = Load-Webhooks
    $list += [PSCustomObject]@{
        name = $name
        encrypted_url = $encrypted_url
        salt = $salt
    }
    Save-Webhooks $list
    Write-Host "Webhook added!"
    Start-Sleep -Seconds 2
}

function Encrypt-WebhookUrl {
    param($url, $password)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url))
}

function Decrypt-WebhookUrl {
    param($encryptedUrl, $salt, $password)
    try {
        $bytes = [Convert]::FromBase64String($encryptedUrl)
        return [Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        Write-Host "Failed to decrypt webhook URL" -ForegroundColor Red
        return $null
    }
}

function Show-WebhooksPage {
    param([int]$page = 1)
    $list = Load-Webhooks
    $perPage = 10
    $count = $list.Count
    $pages = [math]::Ceiling($count / $perPage)
    $page = [math]::Max(1, [math]::Min($page, $pages))
    $start = ($page - 1) * $perPage
    $end = [math]::Min($start + $perPage, $count) - 1

    Clear-Host
    Write-Host "SELECT (Page $page of $pages)"
    for ($i = $start; $i -le $end; $i++) {
        Write-Host "($([int]($i - $start + 1))) $($list[$i].name)"
    }
    Write-Host ""
    Write-Host "E (Edit) X (Exit) N (Next Page) B (Back Page) A (Add new webhook)"
    return @{pages=$pages; start=$start}
}

function Select-WebhookMenu {
    $page = 1
    while ($true) {
        $info = Show-WebhooksPage -page $page
        $input = Read-Host "Choose number or command"
        switch ($input.ToUpper()) {
            {$_ -match '^[1-9]$'} {
                $idx = $info.start + [int]$input - 1
                $list = Load-Webhooks
                if ($idx -ge 0 -and $idx -lt $list.Count) {
                    $name = $list[$idx].name
                    $pw = Read-Host "Password for $name (8 chars)" -AsSecureString
                    $pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
                    if ($pwPlain.Length -ne 8) {
                        Write-Host "Password must be exactly 8 characters." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                        continue
                    }
                    $url = Decrypt-WebhookUrl -encryptedUrl $list[$idx].encrypted_url -salt $list[$idx].salt -password $pwPlain
                    if ($url) {
                        Write-Host "✅ Decrypted URL: $url"
                        $script:currentWebhook = @{
                            name = $name
                            url = $url
                        }
                        Read-Host "Press Enter to continue"
                        return
                    }
                }
            }
            'E' { Edit-WebhookMenu }
            'X' { return }
            'N' { if ($page -lt $info.pages) { $page++ } }
            'B' { if ($page -gt 1) { $page-- } }
            'A' { Add-NewWebhook }
            default { Write-Host "Invalid input." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Edit-WebhookMenu {
    $page = 1
    while ($true) {
        $info = Show-WebhooksPage -page $page
        Write-Host "EDIT MODE"
        $input = Read-Host "Choose number to edit or command"
        switch ($input.ToUpper()) {
            {$_ -match '^[1-9]$'} {
                $idx = $info.start + [int]$input - 1
                $list = Load-Webhooks
                if ($idx -ge 0 -and $idx -lt $list.Count) {
                    $webhook = $list[$idx]
                    Write-Host "Editing $($webhook.name)"
                    $newName = Read-Host "New name (leave blank to keep)"
                    if ($newName.Length -ge 2) {
                        $list[$idx].name = $newName
                    }
                    Save-Webhooks $list
                    Write-Host "Webhook updated."
                    Start-Sleep -Seconds 2
                }
            }
            'E' { return }
            'X' { return }
            'N' { if ($page -lt $info.pages) { $page++ } }
            'B' { if ($page -gt 1) { $page-- } }
            default { Write-Host "Invalid input." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

function Upload-Files {
    if (-not $script:currentWebhook) {
        Write-Host "No webhook selected. Go select one first."
        Read-Host "Press Enter to continue"
        return
    }

    Write-Host "Drag and drop files here then press Enter:"
    $input = Read-Host
    $files = $input -split '"?\s+"?' | Where-Object { $_ -ne "" }

    foreach ($file in $files) {
        if (-not (Test-Path $file)) {
            Write-Host "File not found: $file"
            continue
        }
        Write-Host "Uploading $file..."
        try {
            Invoke-RestMethod -Uri $script:currentWebhook.url -Method Post -InFile $file -ContentType "multipart/form-data"
            Write-Host "Uploaded $file"
        } catch {
            Write-Host "Upload failed for $file" -ForegroundColor Red
        }
    }
    Read-Host "Press Enter to continue"
}

function Settings-Menu {
    Clear-Host
    Write-Host "Settings Menu"
    Write-Host "1. Rename Menu Items"
    Write-Host "2. Change Console Text Color"
    Write-Host "X. Exit"
    $choice = Read-Host "Pick option"
    switch ($choice.ToUpper()) {
        "1" {
            $newTitle = Read-Host "New Title"
            $newLabel = Read-Host "New label for Settings"
            $nameData.name = $newTitle
            $nameData.settings_label = $newLabel
            $nameData | ConvertTo-Json | Out-File $nameFile
            Write-Host "Menu names updated. Restart script to see changes."
            Read-Host "Press Enter to continue"
        }
        "2" {
            Write-Host "Available colors: Black, Blue, Cyan, DarkBlue, DarkCyan, DarkGray, DarkGreen, DarkMagenta, DarkRed, DarkYellow, Gray, Green, Magenta, Red, White, Yellow"
            $color = Read-Host "Enter console foreground color"
            try {
                $host.UI.RawUI.ForegroundColor = $color
                Write-Host "Color changed."
            } catch {
                Write-Host "Invalid color."
            }
            Read-Host "Press Enter to continue"
        }
        "X" { return }
        default {
            Write-Host "Invalid choice."
            Start-Sleep -Seconds 1
        }
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "========================="
    Write-Host "$title"
    Write-Host "========================="
    Write-Host "1. Select Webhook"
    Write-Host "2. Upload Files (Drag and Drop)"
    Write-Host "3. $settingsLabel"
    Write-Host "4. Exit"
}

# MAIN LOOP
while ($true) {
    $webhooks = Load-Webhooks
    if ($webhooks.Count -eq 0) {
        Starter-Guide
        $webhooks = Load-Webhooks
    }
    Show-Menu
    $choice = Read-Host "Pick an option"
    switch ($choice) {
        "1" { Select-WebhookMenu }
        "2" { Upload-Files }
        "3" { Settings-Menu }
        "4" { break }
        default { Write-Host "Invalid choice."; Start-Sleep -Seconds 1 }
    }
}

Write-Host "Goodbye bro!" -ForegroundColor Green

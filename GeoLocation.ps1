$ErrorActionPreference = 'SilentlyContinue'

# Stable per-device key (must not change between runs)
$machineGuid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid).MachineGuid
if (-not $machineGuid) { $machineGuid = $env:COMPUTERNAME }

# Currently logged-on user (works when the script runs as SYSTEM)
$loggedOn = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $loggedOn) {
    # Fallback: owner of the explorer.exe process (covers some RDP/console cases)
    $proc = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
    if ($proc) {
        $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwner
        if ($owner.User) { $loggedOn = "$($owner.Domain)\$($owner.User)" }
    }
}
$userName = if ($loggedOn) { ($loggedOn -split '\\')[-1] } else { '(no user logged in)' }

# Local IP and MAC of the adapter that carries the default route
$localIP = ''
$mac     = ''
try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
             Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4).InterfaceMetric } |
             Select-Object -First 1
    if ($route) {
        $localIP = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 |
                    Where-Object { $_.IPAddress -notlike '169.254.*' } |
                    Select-Object -First 1).IPAddress
        $mac = ((Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).MacAddress) -replace '-', ':'
    }
} catch {}

$result = [ordered]@{
    'Endpoint\User'    = "$env:COMPUTERNAME\$userName"
    'Source'           = 'Unknown'
    'Latitude'         = ''
    'Longitude'        = ''
    'Accuracy (m)'     = ''
    'City (IP)'        = ''
    'Region (IP)'      = ''
    'Country (IP)'     = ''
    'Current IP (Local)' = $localIP
    'MAC Address'      = $mac
    'ISP'              = ''
    'Public IP'        = ''
    'Note'             = ''
    'Collected UTC'    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
}

# 1) Windows Location API
try {
    Add-Type -AssemblyName System.Device
    $watcher = New-Object System.Device.Location.GeoCoordinateWatcher([System.Device.Location.GeoPositionAccuracy]::Default)
    $null = $watcher.TryStart($false, [TimeSpan]::FromSeconds(10))

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($watcher.Permission -ne 'Denied' -and
           $watcher.Position.Location.IsUnknown -and
           $sw.Elapsed.TotalSeconds -lt 10) {
        Start-Sleep -Milliseconds 500
    }

    $loc = $watcher.Position.Location
    if (-not $loc.IsUnknown) {
        $result['Source']       = 'Windows Location API'
        $result['Latitude']     = [math]::Round($loc.Latitude, 5)
        $result['Longitude']    = [math]::Round($loc.Longitude, 5)
        $result['Accuracy (m)'] = [math]::Round($loc.HorizontalAccuracy)
    }
    $watcher.Stop()
} catch {
    $result['Note'] = "Location API error: $($_.Exception.Message)"
}

# 2) IP lookup: always run for public IP, ISP, and city/region context
try {
    $fields = 'status,message,country,regionName,city,lat,lon,isp,query'
    $ip = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=$fields" -TimeoutSec 10 -ErrorAction Stop

    if ($ip.status -eq 'success') {
        # Only use IP coordinates if the Location API gave nothing
        if ($result['Source'] -eq 'Unknown') {
            $result['Source']    = 'IP Geolocation'
            $result['Latitude']  = $ip.lat
            $result['Longitude'] = $ip.lon
        }
        $result['City (IP)']    = $ip.city
        $result['Region (IP)']  = $ip.regionName
        $result['Country (IP)'] = $ip.country
        $result['ISP']          = $ip.isp
        $result['Public IP']    = $ip.query
    } else {
        $result['Note'] = "ip-api failed: $($ip.message)"
    }
} catch {
    $result['Note'] = "ip-api request error: $($_.Exception.Message)"
}
if ($result['Latitude'] -ne '' -and $result['Longitude'] -ne '') {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $lat = ([double]$result['Latitude']).ToString('0.#####', $inv)
    $lon = ([double]$result['Longitude']).ToString('0.#####', $inv)
    $result['Map Link'] = "https://www.google.com/maps/search/?api=1&query=$lat,$lon"
}
# A1_Key must be last, and stable between runs
$result['A1_Key'] = $machineGuid

Write-Output ([PSCustomObject]$result)

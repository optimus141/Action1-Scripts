# Action1 Device Location Data Source

A PowerShell script for an [Action1](https://www.action1.com/) **custom data source** that reports where each managed Windows endpoint is, who is using it, and how to find it on your network, all in one row per device.

It is built for the everyday IT question: *"This IP or MAC showed up in the DHCP leases. Whose machine is it, and where is it?"*

> **Disclaimer:** This project is community-made and is not affiliated with or endorsed by Action1 Corporation. Provided as is, without warranty. Test before deploying to production.

## What it collects

| Column | Description |
|---|---|
| `Endpoint\User` | Computer name plus the currently logged-on user (for example `PC-0123\jdoe`) |
| `Source` | How the coordinates were found: `Windows Location API` or `IP Geolocation` |
| `Latitude`, `Longitude` | Approximate coordinates |
| `Accuracy (m)` | Accuracy radius in meters (Windows Location API only) |
| `Map Link` | Clickable Google Maps URL for the coordinates |
| `City (IP)`, `Region (IP)`, `Country (IP)` | Location of the public IP, as reported by ip-api.com |
| `Current IP (Local)` | IPv4 address of the adapter that carries the default route |
| `MAC Address` | MAC of that same adapter (`AA:BB:CC:DD:EE:FF` format) |
| `ISP` | Internet provider of the public IP |
| `Public IP` | The device's public IP as seen from the internet |
| `Note` | Error or failure message, empty when everything worked |
| `Collected UTC` | When the script ran |
| `A1_Key` | Required by Action1: the Windows MachineGuid (unique per device, stable between runs) |

## How it works

1. **Windows Location API** (`System.Device.Location.GeoCoordinateWatcher`) is asked for a position, waiting up to 10 seconds. It uses GPS, Wi-Fi positioning, or Windows' own estimate.
2. **IP geolocation** via [ip-api.com](https://ip-api.com/) always runs. It supplies the public IP, ISP, and city/region. Its coordinates are used only if step 1 found nothing. Requesting the URL without an IP makes ip-api look up the caller, so the script never has to discover the public IP itself.
3. **Local IP and MAC** come from the default-route adapter (lowest combined route and interface metric), skipping link-local `169.254.x.x` addresses.
4. **Map Link** is built from whichever coordinates were found, using invariant culture so regional settings that use a decimal comma cannot break the URL.

The script always returns exactly one object, and every column always exists, even when a lookup fails.

## Requirements

- Windows endpoints enrolled in Action1
- Windows PowerShell 5.1 (uses `Get-CimInstance`, `Get-NetAdapter`, `Get-NetRoute`, `System.Device`)
- Outbound HTTP access to `ip-api.com` from endpoints (optional: without it you still get the Windows Location API result, local IP, MAC and user, plus a message in `Note`)
- For the Windows Location API path: Location Services enabled on the device

## Setup in Action1

Menu names may differ slightly between Action1 versions.

1. Go to **Reports** and create a **custom data source**, choosing PowerShell as the script type.
2. Paste the contents of [`Get-DeviceLocation.ps1`](Get-DeviceLocation.ps1).
3. In the column detection step, enter the name of an **online** enrolled endpoint and click **Detect**. All columns above should appear, including `A1_Key`.
4. Set `Latitude`, `Longitude` and `Accuracy (m)` to numeric types if offered. Leave the others as text.
5. Create a report from the data source.

### Simple or summary report?

- A **simple report** lists every device with all columns, which is usually all you need.
- A **summary report** groups rows. For example, use `Country (IP)` and `City (IP)` as summary columns, and `Endpoint\User`, `Current IP (Local)`, `MAC Address` and `Map Link` as drilldown columns, to see how many devices are in each place and expand to see which ones.

## Test before you deploy

Action1 runs scripts as **SYSTEM**, which behaves differently from your own account, so test both ways.

1. Run the script in a normal PowerShell window and check the output.
2. Run it as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec) from an elevated prompt:

   ```
   psexec -s -i powershell.exe
   ```

3. Run the script in the window that opens. If `Source` is `IP Geolocation` there, the Windows Location API is not available to SYSTEM on that device, and the IP fallback is doing the work. This is common.

### Example output (fictional values)

```
Endpoint\User      : PC-0123\jdoe
Source             : Windows Location API
Latitude           : 40.7128
Longitude          : -74.006
Accuracy (m)       : 5000
Map Link           : https://www.google.com/maps/search/?api=1&query=40.7128,-74.006
City (IP)          : Example City
Region (IP)        : Example Region
Country (IP)       : Example Country
Current IP (Local) : 192.168.1.50
MAC Address        : AA:BB:CC:DD:EE:FF
ISP                : Example ISP
Public IP          : 203.0.113.25
Note               :
Collected UTC      : 2026-01-01 08:00:00
A1_Key             : 00000000-0000-0000-0000-000000000000
```

## Known limitations

- **Accuracy varies a lot.** Desktops and servers have no GPS. Windows estimates from Wi-Fi or IP, so results can be off by kilometers. IP-based locations reflect the ISP's network, not the device, and can be in the wrong part of a city.
- **VPNs and proxies.** The public IP, ISP and IP-based location will be those of the VPN exit. The default-route adapter may also be the virtual VPN adapter, so the local IP and MAC can be those of the virtual adapter.
- **The user is a hint, not proof of ownership.** It is whoever is logged on when the script runs. With no session you get `(no user logged in)`. With several RDP sessions you get one of them. The domain part is dropped to match the `ENDPOINT\user` format (edit `$userName` to keep it).
- **`A1_Key` must never change.** Do not put the user, IP, or coordinates in it. They change between runs.
- **Rate limits.** ip-api's free tier allows 45 requests per minute per source IP, and devices in one office often share a public IP. Stagger schedules on large fleets.

## Privacy, legal and terms of use

- **Device location and user names are personal data** in many jurisdictions. Involve HR and legal, tell employees what is collected and why, and limit who can view the report. Sharing a Map Link also sends a request to Google when it is opened.
- **Review the ip-api.com terms.** The free tier is HTTP only and is intended for non-commercial use. Commercial use needs a paid plan. For an organization-wide deployment, consider a paid HTTPS provider or a self-hosted database such as MaxMind GeoLite2, and change the URL and field mapping in section 2 of the script.
- Do not commit real device names, IP addresses, MAC addresses, or report exports to a public repository.

## Contributing

Issues and pull requests are welcome, especially for:

- Alternative GeoIP providers (HTTPS, self-hosted)
- Better handling of multiple sessions and VPN adapters
- IPv6 support

## License

Released under the MIT License (add a `LICENSE` file to the repository).

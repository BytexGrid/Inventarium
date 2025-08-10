# Inventarium

**Inventarium** is a PowerShell utility for Windows that performs a comprehensive discovery of installed applications from multiple sources.
It aggregates software listings from the Windows Registry, popular Windows package managers, and optional sources, then deduplicates and formats the results for clear reporting or export.

---

## Features

* Queries multiple data sources for installed applications:

  * **Windows Registry** (`HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall`)
  * **winget**
  * **Chocolatey**
  * **Scoop**
* Deduplicates results intelligently, prioritizing Registry entries.
* Displays output in a user-friendly table or `Out-GridView` if available.
* Summarizes counts of applications found per source.
* Optional export of results to `.txt` or `.json` formats.
* Handles missing tools gracefully and continues with available sources.

---

## Why the Name “Inventarium”

From the Latin *inventarium* — meaning “inventory” or “detailed list of possessions” — the name reflects the tool’s purpose: a precise, methodical catalog of the software installed on a Windows system.
It embodies both practical utility and a spirit of systematic discovery.

---

## Requirements

* Windows PowerShell 5.1 or later, or PowerShell 7+
* For `Out-GridView` support, the **Microsoft.PowerShell.GraphicalTools** module (on PowerShell 7+) or inclusion in Windows PowerShell (optional as it handles and skips `Out-GridView`silently if not found :)

---

## Usage

1. Download `Inventarium.ps1` to your system.
2. Open PowerShell in the directory containing the script.
3. If necessary, allow script execution for the session:

   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. Run the script:

   ```powershell
   .\Inventarium.ps1
   ```

> **Note:** Administrator rights are **not required**. The script only queries publicly accessible application data.

---

## Output

The script will:

1. Query each available source.
2. Deduplicate and sort the results.
3. Display the application list in:

   * **Out-GridView** if available.
   * A formatted table otherwise.
4. Show a summary of counts per source.
5. Optionally prompt to save the results to `.txt` or `.json` on your Desktop.

---

## Example Summary

```
Items found per source (before deduplication):
  - Registry:   124
  - winget:     38
  - Chocolatey: 12
  - Scoop:      7
-----------------------------------------
Total initial entries found: 181
Unique applications after deduplication: 142
```

---

## Limitations

* The script relies on the output formats of winget, Chocolatey, and Scoop.
  Significant changes to these tools may require script updates.
* Portable applications that do not register with the system or a package manager will not appear.
* Haven't yet discovered any other problems with it yet, if you encounter any issue please [open an Issue](https://github.com/BytexGrid/Inventarium/issues).

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

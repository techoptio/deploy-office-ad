# Deploy Office with Active Directory

Install Office on domain-joined computers with a computer Group Policy scheduled task. The domain controllers store the Office Deployment Tool, a configuration file, and a version label in SYSVOL. They do not store Office itself. Each computer downloads Office from Microsoft when the task runs, so the computer needs internet. The domain controllers do not.

The script looks for `setup.exe`, `config.xml`, and `desired_version.txt` in its own folder. Keep those files together on SYSVOL.

The task is the same for any product the Office Deployment Tool can install. `config.xml` chooses the products, the update channel, the languages, and what happens to Office that is already installed. [Configuration](#configuration) lists those choices. [`config.example.xml`](config.example.xml) is one filled-in file.

A [step-by-step guide based on a real example](https://www.techopt.io/windows/deploy-office-with-active-directory-step-by-step-gpo-guide) follows one domain through the same deploy.

## Put the files in SYSVOL

Copy this folder to the domain SYSVOL share, for example:

```text
\\example.com\SYSVOL\example.com\software\ODT\
```

Use the domain name, not one domain controller. Either DC can serve the files after SYSVOL replication.

That folder needs:

- `Deploy-Office.ps1`
- `config.xml`, the Office Deployment Tool configuration for the licenses you have. `config.xml` is gitignored. Do not commit it, and do not commit a real product key.
- `desired_version.txt`, made from [`desired_version.example.txt`](desired_version.example.txt). One line. The line is a label you choose, not an Office build number. `2024Volume` is only an example label.
- `setup.exe`, the Office Deployment Tool from Microsoft. It is gitignored. Do not commit it.

Download the Office Deployment Tool and extract `setup.exe` into the folder:

<https://www.microsoft.com/en-us/download/details.aspx?id=49117>

`SourcePath` in `config.xml` has to stay `C:\ProgramData\OfficeODT\staging\src`. The script downloads Office there, installs from there, and deletes the staging folder when the run finishes. The other settings are yours. [Configuration](#configuration) covers them.

## Configuration

`setup.exe` reads `config.xml`. The script copies that file locally and passes it to `/download` and `/configure`.

Microsoft documents every element in [Configuration options for the Office Deployment Tool](https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options). Product IDs are listed in [Product IDs supported by the Office Deployment Tool](https://learn.microsoft.com/en-us/troubleshoot/office/office-suite-issues/product-ids-supported-office-deployment-click-to-run).

`Product ID` and `Channel` have to name the same release. A Microsoft 365 product on `PerpetualVL2024`, or a volume product on a Microsoft 365 channel, installs the wrong product. Several `Product` elements can sit in one `Add`, so Office, Visio, and Project can be one install.

| What you are installing | Product ID | Channel |
| --- | --- | --- |
| Microsoft 365 Apps for enterprise | `O365ProPlusRetail` | `Current`, `MonthlyEnterprise`, or `SemiAnnual` |
| Microsoft 365 Apps for business | `O365BusinessRetail` | `Current`, `MonthlyEnterprise`, or `SemiAnnual` |
| Office LTSC Professional Plus 2024 | `ProPlus2024Volume` | `PerpetualVL2024` |
| Office LTSC Standard 2024 | `Standard2024Volume` | `PerpetualVL2024` |
| Visio or Project, with Microsoft 365 | `VisioProRetail`, `ProjectProRetail` | The same channel as the Microsoft 365 Apps install |
| Visio or Project LTSC 2024 | `VisioPro2024Volume`, `VisioStd2024Volume`, `ProjectPro2024Volume`, `ProjectStd2024Volume` | `PerpetualVL2024` |

Office LTSC 2021 uses channel `PerpetualVL2021` and product IDs that end in `2021Volume`, such as `ProPlus2021Volume`. Single apps (Word, Excel, and the rest) and the no-Teams Microsoft 365 IDs are on the product ID page.

The other elements change the install around that product:

- `OfficeClientEdition` is `64` or `32`. Every Office product on the computer has to use the same architecture.
- `Language` takes an ID such as `en-us`. Each product lists its own languages, and a product can list more than one.
- `ExcludeApp` leaves an app out of that product. Common IDs are `Access`, `Publisher`, `OneDrive`, and `Lync`. With no `ExcludeApp`, the product installs its default apps.
- `PIDKEY` is the volume product key: a MAK, or the KMS generic volume license key when the computers activate from KMS. Put the key only in the `config.xml` on SYSVOL. Microsoft 365 Apps products have no `PIDKEY`.
- `Remove All="True"` removes Click-to-Run products that this file does not list. Omit `Remove` when an existing Click-to-Run install should stay.
- `RemoveMSI` removes legacy Windows Installer Office. Omit it when those products should stay.
- `Display Level="None" AcceptEULA="TRUE"` keeps the install silent. The task runs as SYSTEM with nobody there to click through setup.
- `AUTOACTIVATE` set to `1` activates a volume product during the install. Microsoft 365 Apps activates on its own, so leave that property out for those products.
- `SharedComputerLicensing` set to `1` is for Microsoft 365 Apps on a computer many people sign in to, such as Remote Desktop.
- `FORCEAPPSHUTDOWN` set to `TRUE` closes open Office apps so `/configure` can finish while someone is logged on.
- `SourcePath` stays `C:\ProgramData\OfficeODT\staging\src` for this script.

[`config.example.xml`](config.example.xml) is one combination: 64-bit Office LTSC Professional Plus 2024, Visio, and Project, English, Lync excluded, other Click-to-Run and MSI Office removed, silent, with placeholder volume keys and auto-activate. Use it when that is the install you want. For anything else, write `config.xml` from the table and the list above.

## Scheduled task

Create a computer Group Policy Preference scheduled task. Run it as `NT AUTHORITY\System` with highest privileges, so Office installs for the computer with nobody logged on.

Program:

```text
cmd.exe
```

Arguments:

```text
/c start "" /abovenormal powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\example.com\SYSVOL\example.com\software\ODT\Deploy-Office.ps1"
```

Triggers:

- At startup.
- When the task is registered, so a computer that has just received the policy does not wait for the next boot.
- Daily, with start when available, so a computer that was off still runs.

A full Office download can take a long time. Set the execution time limit to three days. Ignore a new instance if one is already running.

The task priority itself sits below a normal process. `start /abovenormal` raises the PowerShell process.

At boot, SYSVOL is often not ready when the startup trigger fires. The script waits up to 150 seconds for the three files before it gives up.

If the task is set to stop when the computer switches to battery power, unplugging a laptop aborts the install. Leave that unset when laptops should finish on battery.

## Limit the task to some computers

The task is installed on every computer that applies the GPO. Linking and security filtering choose those computers. With the default filter, a GPO linked at the domain installs Office on workstations, servers, and domain controllers.

Link the GPO to an organizational unit that contains only the computers that should get Office. The built-in Computers container is not an organizational unit, so a GPO cannot be linked to it. Create an OU, move the computer accounts into it, and link the GPO there.

To leave the computers where they are, link the GPO at the domain or a parent OU and use security filtering:

1. Create a security group for the computers, for example `Office Computers`.
2. Add the computer accounts to that group. A user account does not receive a computer policy.
3. In Group Policy Management, on the Scope tab, remove Authenticated Users from Security Filtering and add the computer group.
4. On the Delegation tab, give that group Read. Group Policy Management warns when Authenticated Users loses Read. The computers in the group need Read or they cannot open the GPO in SYSVOL. Authenticated Users can keep Read and lose Apply, or the computer group can hold both.
5. Restart each computer after adding it to the group. Group membership is on the computer's token from startup, so `gpupdate` alone does not see a group joined in the current boot.

A computer outside the group never registers the task. Changing `desired_version.txt` does not install Office there.

Item-level targeting on the scheduled task can match a security group or a computer name. Security filtering is enough when this task is the whole GPO.

## Rolling out a change

Computers record the label from `desired_version.txt` in `C:\ProgramData\OfficeODT\state.json` after a successful install. The next run does nothing while that label still matches.

Change the one line in `desired_version.txt` on SYSVOL when every computer that runs the task should apply the config again. Editing `config.xml` alone does not redeploy.

A failed download or configure does not record the new label, so the next startup or the daily run tries again. The log on the computer is `C:\ProgramData\OfficeODT\deploy.log`. Lines older than 30 days are removed. Active Directory does not record which computers have the label.

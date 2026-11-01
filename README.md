# Deploy Office with Active Directory

Put Office LTSC 2024 on domain-joined computers with a computer Group Policy scheduled task. The domain controllers store the Office Deployment Tool, a configuration file, and a version label in SYSVOL. They do not store Office itself. Each computer downloads Office when the task runs.

The script looks for `setup.exe`, `config.xml`, and `desired_version.txt` in its own folder. Keep those files together on SYSVOL.

## Put the files in SYSVOL

Copy this folder to the domain SYSVOL share, for example:

```text
\\example.com\SYSVOL\example.com\software\ODT\
```

Use the domain name, not one domain controller. Either DC can serve the files after SYSVOL replication.

That folder needs:

- `Deploy-Office.ps1`
- `config.xml`, made from [`config.example.xml`](config.example.xml) with your own product keys. `config.xml` is gitignored. Do not commit it.
- `desired_version.txt`, made from [`desired_version.example.txt`](desired_version.example.txt). One line. The line is a label you choose, not an Office build number.
- `setup.exe`, the Office Deployment Tool from Microsoft. It is gitignored. Do not commit it.

Download the Office Deployment Tool and extract `setup.exe` into the folder:

<https://www.microsoft.com/en-us/download/details.aspx?id=49117>

`SourcePath` in `config.xml` has to stay `C:\ProgramData\OfficeODT\staging\src`. The script downloads Office there, installs from there, and deletes the staging folder when the run finishes.

[`config.example.xml`](config.example.xml) is 64-bit Office LTSC 2024 volume (`PerpetualVL2024`), English, plus Visio and Project. It excludes Lync, removes other Click-to-Run products, and removes legacy MSI Office. The install is silent and auto-activates. This is not Microsoft 365 Apps, and it is not a KMS configuration.

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

Triggers that cover a domain:

- At startup.
- When the task is registered, so a newly linked computer does not wait for the next boot.
- Daily, with start when available, so a computer that was off still runs.

Give the task a long execution limit. A download can take a while. Ignore a new instance if one is already running.

The task priority itself sits below a normal process. `start /abovenormal` raises the PowerShell process.

At boot, SYSVOL is often not ready when the startup trigger fires. The script waits up to 150 seconds for the three files before it gives up.

If the task is set to stop when the computer switches to battery power, unplugging a laptop aborts the install. Leave that unset when laptops should finish on battery.

## Rolling out a change

Computers record the label from `desired_version.txt` in `C:\ProgramData\OfficeODT\state.json` after a successful install. The next run does nothing while that label still matches.

Change the one line in `desired_version.txt` on SYSVOL when every domain computer should apply the config again. Editing `config.xml` alone does not redeploy.

A failed download or configure does not record the new label, so the next startup or the daily run tries again. The log on the computer is `C:\ProgramData\OfficeODT\deploy.log`.

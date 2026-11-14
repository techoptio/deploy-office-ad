# Deploy Office with Active Directory

Install Office on domain-joined computers with a computer Group Policy scheduled task. The domain controllers store the Office Deployment Tool, a configuration file, and a version label in SYSVOL. They do not store Office itself. Each computer downloads Office from Microsoft when the task runs, so the computer needs internet. The domain controllers do not.

The script looks for `setup.exe`, `config.xml`, and `desired_version.txt` in its own folder. Keep those files together on SYSVOL.

The task is the same for any product the Office Deployment Tool can install: Microsoft 365 Apps, Office LTSC, Visio, and Project. `config.xml` chooses the product and the update channel. [`config.example.xml`](config.example.xml) is one working example: 64-bit Office LTSC Professional Plus 2024 volume (`PerpetualVL2024`), English, plus Visio and Project. For a different release, change `Channel` and `Product ID`. Microsoft lists both in the [Office Deployment Tool configuration options](https://learn.microsoft.com/en-us/microsoft-365-apps/deploy/office-deployment-tool-configuration-options).

## Put the files in SYSVOL

Copy this folder to the domain SYSVOL share, for example:

```text
\\example.com\SYSVOL\example.com\software\ODT\
```

Use the domain name, not one domain controller. Either DC can serve the files after SYSVOL replication.

That folder needs:

- `Deploy-Office.ps1`
- `config.xml`, made from [`config.example.xml`](config.example.xml) with your own product keys when the product uses them. `config.xml` is gitignored. Do not commit it.
- `desired_version.txt`, made from [`desired_version.example.txt`](desired_version.example.txt). One line. The line is a label you choose, not an Office build number. `2024Volume` is only an example label.
- `setup.exe`, the Office Deployment Tool from Microsoft. It is gitignored. Do not commit it.

Download the Office Deployment Tool and extract `setup.exe` into the folder:

<https://www.microsoft.com/en-us/download/details.aspx?id=49117>

`SourcePath` in `config.xml` has to stay `C:\ProgramData\OfficeODT\staging\src`. The script downloads Office there, installs from there, and deletes the staging folder when the run finishes.

The example config excludes Lync, removes other Click-to-Run products (`Remove All="True"`), and removes legacy MSI Office (`RemoveMSI All="True"`). The install is silent and auto-activates. The example uses product keys in the config. It is not a KMS configuration. Microsoft 365 Apps uses a different `Product ID` and `Channel`, and usually no `PIDKEY`. Delete `Remove` and `RemoveMSI` when the computer should keep another Office product.

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

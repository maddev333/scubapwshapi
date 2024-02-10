gci env:* | sort-object name
Import-Module -Name C:\\scuba\\ScubaGear-1.0.0\\PowerShell\\ScubaGear
Invoke-SCuBA -ProductNames aad -Organization $Env:Organization -OPAPath c:\scuba\ScubaGear-1.0.0\ -OutPath: c:/out
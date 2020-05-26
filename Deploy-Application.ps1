<#
.SYNOPSIS
	This script performs the installation or uninstallation of an application(s).
	# LICENSE #
	PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
	Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
	You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is provided as a template to perform an install or uninstall of an application(s).
	The script either performs an "Install" deployment type or an "Uninstall" deployment type.
	The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.
	The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
	The type of deployment to perform. Default is: Install.
.PARAMETER DeployMode
	Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.
.PARAMETER AllowRebootPassThru
	Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.
.PARAMETER TerminalServerMode
	Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Destkop Session Hosts/Citrix servers.
.PARAMETER DisableLogging
	Disables logging to file for the script. Default is: $false.
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"
.EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"
.EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"
.NOTES
	Toolkit Exit Code Ranges:
	60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
	69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
	70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
.LINK
	http://psappdeploytoolkit.com
#>
[CmdletBinding()]
Param (
	[Parameter(Mandatory=$false)]
	[ValidateSet('Install','Uninstall','Repair')]
	[string]$DeploymentType = 'Install',
	[Parameter(Mandatory=$false)]
	[ValidateSet('Interactive','Silent','NonInteractive')]
	[string]$DeployMode = 'Interactive',
	[Parameter(Mandatory=$false)]
	[switch]$AllowRebootPassThru = $false,
	[Parameter(Mandatory=$false)]
	[switch]$TerminalServerMode = $false,
	[Parameter(Mandatory=$false)]
	[switch]$DisableLogging = $false,
	[Parameter(Mandatory=$false)]
	[string]$FahDefaultsFile = 'defaults.txt', # Specify text file containing default values for FAHClient config.xml
	[Parameter(Mandatory=$false)]
	[ValidatePattern('^.*\\FAHClient$')] # Enforce requirement in 7.6.4 and later that Windows data directory ends with '\FAHClient'.
	[string]$FahDataDirectory = "$($env:AllUsersProfile)\FAHClient" # Specify data directory to use for FAHClient.
)

Try {
	## Set the script execution policy for this process
	Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

	##*===============================================
	##* VARIABLE DECLARATION
	##*===============================================
	## Variables: Application
	[string]$appVendor = 'Folding@home.org'
	[string]$appName = 'Folding@home'
	[string]$appVersion = '7.6.13'
	[string]$appArch = 'x86'
	[string]$appLang = 'EN'
	[string]$appRevision = '01'
	[string]$appScriptVersion = '1.0.0'
	[string]$appScriptDate = '10/05/2020'
	[string]$appScriptAuthor = 'Scott Ladewig'
	##*===============================================
	## Variables: Install Titles (Only set here to override defaults set by the toolkit)
	[string]$installName = ''
	[string]$installTitle = ''

	##* Do not modify section below
	#region DoNotModify

	## Variables: Exit Code
	[int32]$mainExitCode = 0

	## Variables: Script
	[string]$deployAppScriptFriendlyName = 'Deploy Application'
	[version]$deployAppScriptVersion = [version]'3.8.2'
	[string]$deployAppScriptDate = '08/05/2020'
	[hashtable]$deployAppScriptParameters = $psBoundParameters

	## Variables: Environment
	If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
	[string]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

	## Dot source the required App Deploy Toolkit Functions
	Try {
		[string]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
		If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
		If ($DisableLogging) { . $moduleAppDeployToolkitMain -DisableLogging } Else { . $moduleAppDeployToolkitMain }
	}
	Catch {
		If ($mainExitCode -eq 0){ [int32]$mainExitCode = 60008 }
		Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
		## Exit the script, returning the exit code to SCCM
		If (Test-Path -LiteralPath 'variable:HostInvocation') { $script:ExitCode = $mainExitCode; Exit } Else { Exit $mainExitCode }
	}

	#endregion
	##* Do not modify section above
	##*===============================================
	##* END VARIABLE DECLARATION
	##*===============================================

	If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
		##*===============================================
		##* PRE-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Installation'

		## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
		Show-InstallationWelcome -CloseApps 'iexplore' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Installation tasks here>

		# Create FAHClient data directory if it does not exist
		If (-Not (Test-Path -Path $FahDataDirectory)) {
			New-Item -Path $FahDataDirectory -ItemType Directory
		}

		# If installed as a service, FAHClient runs as Local System by default. For security reasons, we want to use LocalService which runs as a standard user.
		# Grant Local Service modify permissions on the data directory. https://win32.io/posts/How-To-Set-Perms-With-Powershell
		$FahUserAccount = 'NT AUTHORITY\LocalService'
		$FahUserPassword = '' # Password needs to be an empty string for Local Service when we modify the service later
		$Rights = 'Modify'
		$Inheritance = 'Containerinherit, ObjectInherit'
		$Propagation = 'None'
		$RuleType = 'Allow'

		$Acl = Get-Acl $FahDataDirectory
		$Perm = $FahUserAccount, $Rights, $Inheritance, $Propagation, $RuleType
		$Rule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $Perm
		$Acl.SetAccessRule($Rule)
		$Acl | Set-Acl -Path $FahDataDirectory

		##*===============================================
		##* INSTALLATION
		##*===============================================
		[string]$installPhase = 'Installation'

		## Handle Zero-Config MSI Installations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Install'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat; If ($defaultMspFiles) { $defaultMspFiles | ForEach-Object { Execute-MSI -Action 'Patch' -Path $_ } }
		}

		## <Perform Installation tasks here>
		# Specify FAHClient installer
		$FahInstaller = "fah-installer_$($appVersion)_x86.exe"

		# Run FAHClient installer in silent mode
		Execute-Process -Path "$dirFiles\$FahInstaller" -Parameters "/S" -WindowStyle Hidden

		##*===============================================
		##* POST-INSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Installation'

		## <Perform Post-Installation tasks here>

		# Set DataDirectory registry value in FAHClient Uninstall key
		Set-RegistryKey -Key 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\FAHClient' -Name 'DataDirectory' -Type 'String'-Value $FahDataDirectory

		# Set FAHClient.exe path
		$FahClientFolder = "$envProgramFilesX86\FAHClient"
		$FahClientExe = "$FahClientFolder\FAHClient.exe"

		# Add firewall rule allowing communication
		New-NetFirewallRule -DisplayName "Allow Folding@home" -Direction Inbound -Action Allow -Program $FahClientExe -Profile Private, Domain

		# Create Start Menu shortcuts. Installing FAHClient as SYSTEM does not create shortcuts
		# Do not create Uninstall or Folding@home shortcuts since client will start automatically and uninstall should use this uninstaller.
		#New-Folder -Path "$envCommonStartMenuPrograms\Folding@home"
		New-Shortcut -Path "$envCommonStartMenuPrograms\Folding@home\About Folding@home.lnk" -TargetPath "$FahClientFolder\About Folding@home.url" -WorkingDirectory $FahDataDirectory
		New-Shortcut -Path "$envCommonStartMenuPrograms\Folding@home\Data Directory.lnk" -TargetPath $FahDataDirectory -WorkingDirectory $FahDataDirectory
		New-Shortcut -Path "$envCommonStartMenuPrograms\Folding@home\FAHControl.lnk" -TargetPath "$FahClientFolder\FAHControl.exe" -WorkingDirectory $FahDataDirectory -IconLocation "$FahClientFolder\FAHClient.ico"
		New-Shortcut -Path "$envCommonStartMenuPrograms\Folding@home\FAHViewer.lnk" -TargetPath "$FahClientFolder\FAHViewer.exe" -WorkingDirectory $FahDataDirectory -IconLocation "$FahClientFolder\FAHViewer.ico"
		New-Shortcut -Path "$envCommonStartMenuPrograms\Folding@home\Web Control.lnk" -TargetPath "$FahClientFolder\FAHWebClient.url" -WorkingDirectory $FahDataDirectory -IconLocation "$FahClientFolder\FAHClient.ico"

		# Download GPUs.txt because 7.6.9 failed to download the file. Fixed in later versions.
		#Invoke-WebRequest -Uri "https://apps.foldingathome.org/GPUs.txt" -OutFile "$FahDataDirectory\GPUs.txt"

		# Run FAHClient to do the following without downloading any work units
		# 1. Change directory to $FahDataDirectory
		# 2. Create basic config.xml with automatic slot configuration
		# 3. Stay active to receive configuration commands
		Execute-Process -Path $FahClientExe -Parameters "--chdir `"$FahDataDirectory`" --pause-on-start=true" -WindowStyle Hidden -NoWait

		# Read custom settings for config.xml from text file into hash table
		$FahDefaults = Get-Content -Raw -Path "$dirSupportFiles\$FahDefaultsFile" | ConvertFrom-StringData

		# Build arguments for setting options from hash table
		$FahOptions = $null
		$IsUserSet = $false
		$FahDefaults.GetEnumerator() | ForEach-Object {
			$FahOptions += "$($_.Name)=$($_.Value) "
			If ($_.Name -eq "User" -and $IsUserSet -eq $false) {
				$IsUserSet = $true
			}
		}

		# If username was not specified in defaults.txt, get username for system using custom function
		If ($IsUserSet -eq $false) {
			$FahUsername = Get-FahUsername
			$FahOptions += "user=$FahUsername"
		}

		# Run FAHClient and send commands to set options
		Execute-Process -Path $FahClientExe -Parameters "--send-command `"options $FahOptions`"" -WindowStyle Hidden

		# Run FAHClient and send command to save configuration
		Execute-Process -Path $FahClientExe -Parameters "--send-command save" -WindowStyle Hidden

		# Run FAHClient and send command to shutdown running FAHClient process
		Execute-Process -Path $FahClientExe -Parameters "--send-command shutdown" -WindowStyle Hidden

		# Read config.xml and Check to see if GPU was detected by presence of a GPU slot
		[xml]$FahConfig = Get-Content -Path "$FahDataDirectory\config.xml"

		If ($FahConfig.config.slot.type -eq 'GPU') {
			# A supported GPU was detected, run FAHClient using a scheduled task because a service doesn't have access to the GPU

			# Create the scheduled task
			$TaskName = 'FAHClient_Start'
			New-FAHScheduledTask -Name $TaskName -PathExe $FahClientExe -PathWorking $FahDataDirectory -User $FahUserAccount -Password $FahUserPassword

			# Start the scheduled task
			Start-ScheduledTask -TaskName $TaskName

		} else {
			# No supported GPU detected, run FAHClient as a service
			
			# Install service
			Execute-Process -Path $FahClientExe -Parameters "--install-service" -WindowStyle Hidden
			
			# Service is set to use Local System by default. For security reasons, change this to Local Service which runs as a standard user
			$Service = Get-CimInstance Win32_Service -Filter "Name='FAHClient'"
			$null = Invoke-CimMethod -InputObject $Service -MethodName Change -Arguments @{StartName=$FahUserAccount;StartPassword=$FahUserPassword}

			# Pause before starting service
			Start-Sleep -Seconds 3

			# Start-Service. 
			Start-ServiceAndDependencies -Name 'FAHClient'
		}

		## Display a message at the end of the install
		If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'You can customize text to appear at the end of an install or remove it completely for unattended installations.' -ButtonRightText 'OK' -Icon Information -NoWait }
	}
	ElseIf ($deploymentType -ieq 'Uninstall')
	{
		##*===============================================
		##* PRE-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Pre-Uninstallation'

		## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
		Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Uninstallation tasks here>
		# Set FAHClient.exe path
		$FahClientFolder = "$envProgramFilesX86\FAHClient"
		$FahClientExe = "$FahClientFolder\FAHClient.exe"

		##*===============================================
		##* UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Uninstallation'

		## Handle Zero-Config MSI Uninstallations
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Uninstall'; Path = $defaultMsiFile }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}

		# <Perform Uninstallation tasks here>
		# Check to see if FAHClient service exists. Uninstall if service exists.
		If (Test-ServiceExists -Name 'FAHClient') {
			Execute-Process -Path $FahClientExe -Parameters '--uninstall-service' -WindowStyle Hidden
		}

		# Run FAHClient uninstaller. Will handle shutting down a running client
		$UninstallString = (Get-InstalledApplication -ProductCode 'FAHClient').UninstallString
		Execute-Process -Path $UninstallString -Parameters "/S" -WindowStyle Hidden

		# If scheduled task exists for FAHClient, remove it.
		$TaskName = 'FAHClient_Start'

		# Delete the scheduled task if it exists
		Remove-FAHScheduledTask -Name $TaskName 
		
		# Remove data directory. Sleep for a few seconds to give the file handle on the log file to clear
		# You may want to leave the Data Directory in place after an uninstall if there are unfinished work units.
		Start-Sleep -Seconds 5
		Remove-Folder -Path $FahDataDirectory

		# Remove Start Menu shortcuts
		Remove-Folder -Path "$envCommonStartMenuPrograms\Folding@home"

		# remove firewall rule allowing communication
		If (Get-NetFirewallRule -DisplayName "Allow Folding@home" -ErrorAction SilentlyContinue) {
			Remove-NetFirewallRule -DisplayName "Allow Folding@home"
		}

		##*===============================================
		##* POST-UNINSTALLATION
		##*===============================================
		[string]$installPhase = 'Post-Uninstallation'

		## <Perform Post-Uninstallation tasks here>


	}
	ElseIf ($deploymentType -ieq 'Repair')
	{
		##*===============================================
		##* PRE-REPAIR
		##*===============================================
		[string]$installPhase = 'Pre-Repair'

		## Show Progress Message (with the default message)
		Show-InstallationProgress

		## <Perform Pre-Repair tasks here>

		##*===============================================
		##* REPAIR
		##*===============================================
		[string]$installPhase = 'Repair'

		## Handle Zero-Config MSI Repairs
		If ($useDefaultMsi) {
			[hashtable]$ExecuteDefaultMSISplat =  @{ Action = 'Repair'; Path = $defaultMsiFile; }; If ($defaultMstFile) { $ExecuteDefaultMSISplat.Add('Transform', $defaultMstFile) }
			Execute-MSI @ExecuteDefaultMSISplat
		}
		# <Perform Repair tasks here>

		##*===============================================
		##* POST-REPAIR
		##*===============================================
		[string]$installPhase = 'Post-Repair'

		## <Perform Post-Repair tasks here>


    }
	##*===============================================
	##* END SCRIPT BODY
	##*===============================================

	## Call the Exit-Script function to perform final cleanup operations
	Exit-Script -ExitCode $mainExitCode
}
Catch {
	[int32]$mainExitCode = 60001
	[string]$mainErrorMessage = "$(Resolve-Error)"
	Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
	Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
	Exit-Script -ExitCode $mainExitCode
}

<#
.SYNOPSIS
	This script is a template that allows you to extend the toolkit with your own custom functions.
    # LICENSE #
    PowerShell App Deployment Toolkit - Provides a set of functions to perform common application deployment tasks on Windows.
    Copyright (C) 2017 - Sean Lillis, Dan Cunningham, Muhammad Mashwani, Aman Motazedian.
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
.DESCRIPTION
	The script is automatically dot-sourced by the AppDeployToolkitMain.ps1 script.
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
)

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

# Variables: Script
[string]$appDeployToolkitExtName = 'PSAppDeployToolkitExt'
[string]$appDeployExtScriptFriendlyName = 'App Deploy Toolkit Extensions'
[version]$appDeployExtScriptVersion = [version]'3.8.2'
[string]$appDeployExtScriptDate = '08/05/2020'
[hashtable]$appDeployExtScriptParameters = $PSBoundParameters

##*===============================================
##* FUNCTION LISTINGS
##*===============================================

Function New-FAHScheduledTask {
    [CmdletBinding()]
    Param (
        [string]$Name = 'FAHClient_Start',
        [string]$PathExe = "$envProgramFilesX86\FAHClient\FAHClient.exe",
        [string]$PathWorking = "$envProgramData\FAHClient",
        [string]$User = 'LocalSystem',
        [string]$Password = ''
    )

    # Check path variables and add escaped quotation marks around path if spaces are found in the path.
    If ($PathExe -match " ") {
        $PathExe = "`"$PathExe`""
    }

    If ($PathWorking -match " ") {
        $PathWorking = "`"$PathWorking`""
    }

    # Create task action
    $TaskAction = New-ScheduledTaskAction -Execute $PathExe -WorkingDirectory $PathWorking
    
    # Create task trigger to run daily at midnight
    $TaskTrigger = New-ScheduledTaskTrigger -Daily -At 00:00

    # Create default task settings set.
    $TaskSettings = New-ScheduledTaskSettingsSet

    # Create task principal. Check if account is a service account and specify the logontype as such, otherwise use password.
    If ($User -match '^(NT AUTHORITY\\(LocalService|NetworkService)|LocalSystem)') {
        $TaskPrincipal = New-ScheduledTaskPrincipal -UserId $User -LogonType ServiceAccount
        $IsServiceAccount= $true
    } Else {
        $TaskPrincipal = New-ScheduledTaskPrincipal -UserId $User -LogonType Password
        $IsServiceAccount= $false
    }
    
    # Create the task and register it
    $Task = New-ScheduledTask -Action $TaskAction -Principal $TaskPrincipal -Trigger $TaskTrigger -Settings $TaskSettings
    If ($IsServiceAccount) {
        $null = Register-ScheduledTask -TaskName $Name -InputObject $Task
    } else {
        $null = Register-ScheduledTask -TaskName $Name -InputObject $Task -Password $Password
    }
    
    # Export task to XML so that we can add a second trigger
    [xml]$TaskXml = Export-ScheduledTask -TaskName $Name

    # Get the namespace to use for creating elements
    $TaskXmlNs = $TaskXml.Task.NamespaceURI

    # Add hourly recurrence for the daily trigger to ensure that client restarts if it stops due to error or other reason
    # Create Repetition element
    $RepetitionXml = $TaskXml.CreateElement("Repetition", $TaskXmlNs)

    # Create Interval element, set value to one hour, and append to Repetition
    $IntervalXml = $TaskXml.CreateElement("Interval", $TaskXmlNs)
    $IntervalXml.InnerText = "PT1H"
    $null = $RepetitionXml.AppendChild($IntervalXml)

    # Create duration element, set value to one day, and append to Repetition
    $DurationXml = $TaskXml.CreateElement("Duration", $TaskXmlNs)
    $DurationXml.InnerText = "P1D"
    $null = $RepetitionXml.AppendChild($DurationXml)

    # Add Repetition element to CalendarTrigger
    $null = $TaskXml.Task.Triggers.CalendarTrigger.AppendChild($RepetitionXml)

    # We want the task to start on boot, so create a BootTrigger element
    $BootTriggerXml = $TaskXml.CreateElement("BootTrigger", $TaskXmlNs)
    
    # Add the BootTrigger element to the Triggers
    $null = $TaskXML.Task.Triggers.AppendChild($BootTriggerXml)
    
    # Remove the existing task, then register a new task using the updated definition
    $null = Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    $null = Register-ScheduledTask -TaskName $Name -Xml $TaskXml.OuterXml
}

Function Remove-FAHScheduledTask {
    [CmdletBinding()]
    Param (
        [string]$Name = "FAHClient_Start"
    )

    # Remove the scheduled task
    If (Get-ScheduledTask -TaskName $TaskName) {
        $null = Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

}

Function Get-FAHUsername {

    # Generate username based on department using department number in machine name
    
    # Get department info, exclude empty and any dept code 0
    $Departments = Import-CSV "$dirSupportFiles\departments.csv" | Where-Object {$_.'Dept Code' -ne '0' -and $_.'Dept Code' -ne ''}

    # Set username prefix if desired
    $UsernamePrefix = 'YourPrefix_'

    # Define hash table
    $DeptLookup = @{}

    # Add generic department for machines without a department number in name
    $DeptLookup.Add('0000', "$($UsernamePrefix)Other")

    # Process all departments and add to hash table
    $Departments | ForEach-Object {
        # Pad department code with leading zeros
        $DeptCodeCsv = $_.'Dept Code'.PadLeft(4,'0')
        $DeptNameCsv = $_.'Dept Name'

        # Replace "Unknown" department name with "Other"
        If ($DeptNameCsv -eq 'Unknown') {
            $DeptNameCsv = 'Other'
        }

        # Usernames should only have letters, numbers, and underscore per Folding@Home FAQ
        # Replace forward slash, space, and hyphen with underscore; remove period,  parentheses (all characters found in our department names)
        $Pattern_Underscore = "/| |-"
        $Pattern_Null = '\.|\(|\)'
        $DeptUsername = $DeptNameCsv -replace($Pattern_Underscore,'_') -replace($Pattern_Null,'')

        # Trim any trailing underscores in case one was added
        $DeptUsername = $DeptUsername.TrimEnd('_')

        # Add username prefix if defined.
        If ($UsernamePrefix -and $DeptUsername -notmatch "^$UsernamePrefix") {
            $DeptUsername = "$UsernamePrefix$DeptUsername"
        }
        $DeptLookup.Add($DeptCodeCsv,$DeptUsername) 
    }

    # Get local computer name
    $ComputerName = $envComputerName

    # Get Department prefix
    $Result = $ComputerName -match '^(\d{4})'

    # Check to see if we have a four digit department code
    If ($Result) {
        $DeptCode = $Matches[1]
    } Else {
        # Machine doesn't have a four digit code so give it to generic dept
        $DeptCode = '0000'
    }

    $Username = $DeptLookup[$DeptCode]

    Return $Username

}

##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================

If ($scriptParentPath) {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $appDeployToolkitExtName
} Else {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $appDeployToolkitExtName
}

##*===============================================
##* END SCRIPT BODY
##*===============================================

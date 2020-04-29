Param(
[string]$xmlFilePath,
[string]$ProfileName
)

$a = Test-Path $xmlFilePath
echo $a

$ProfileXML = Get-Content $xmlFilePath

echo $XML

$ProfileNameEscaped = $ProfileName -replace ' ', '%20'

$Version = 201606090004

$ProfileXML = $ProfileXML -replace '<', '&lt;'
$ProfileXML = $ProfileXML -replace '>', '&gt;'
$ProfileXML = $ProfileXML -replace '"', '&quot;'

$nodeCSPURI = './Vendor/MSFT/VPNv2'
$namespaceName = "root\cimv2\mdm\dmmap"
$className = "MDM_VPNv2_01"

$session = New-CimSession

try
{
$newInstance = New-Object Microsoft.Management.Infrastructure.CimInstance $className, $namespaceName
$property = [Microsoft.Management.Infrastructure.CimProperty]::Create("ParentID", "$nodeCSPURI", 'String', 'Key')
$newInstance.CimInstanceProperties.Add($property)
$property = [Microsoft.Management.Infrastructure.CimProperty]::Create("InstanceID", "$ProfileNameEscaped", 'String', 'Key')
$newInstance.CimInstanceProperties.Add($property)
$property = [Microsoft.Management.Infrastructure.CimProperty]::Create("ProfileXML", "$ProfileXML", 'String', 'Property')
$newInstance.CimInstanceProperties.Add($property)

$session.CreateInstance($namespaceName, $newInstance)
$Message = "Created $ProfileName profile."
Write-Host "$Message"
}
catch [Exception]
{
$Message = "Unable to create $ProfileName profile: $_"
Write-Host "$Message"
exit
}



# // Function to update rasphone.pbk settings
Function Update-Rasphone {

    [CmdletBinding(SupportsShouldProcess)]

    Param(
    
        [string]$Path,
        [string]$ProfileName,
        [hashtable]$Settings
    
    )
    
    $RasphoneProfiles = (Get-Content $Path -Raw) -split "\[" | Where-Object { $_ } # "`n\s?`n\["
    $Output = @()
    $Pass = @()
    
    # // Create a hashtable of VPN profiles
    Write-Verbose "Searching for VPN profiles..."
    $ProfileHash = [ordered]@{ }
    
    ForEach ($Profile in $RasphoneProfiles) {
    
        $RasphoneProfile = [regex]::Match($Profile, ".*(?=\])")
        Write-Verbose "Found VPN profile ""$RasphoneProfile""..."
        $ProfileHash.Add($RasphoneProfile, $profile)
    
    }
    
    $Profiles = $ProfileHash.GetEnumerator()
    
    ForEach ($Name in $ProfileName) {
    
        Write-Verbose "Searching for VPN profile ""$Name""..."
    
        ForEach ($Entry in $Profiles) {
    
            If ($Entry.Name -Match $Name) {
    
                Write-Verbose "Updating settings for ""$($Entry.Name)""..."
                $Profile = $Entry.Value
                $Pass += "[$($Entry.Name)]"
                $Settings.GetEnumerator() | ForEach-Object {
    
                    $SettingName = $_.Name
                    Write-Verbose "Searching VPN profile ""$($Entry.Name)"" for setting ""$Settingname""..."
                    $Value = $_.Value
                    $Old = "$SettingName=.*\s?`n"
                    $New = "$SettingName=$value`n"
                    
                    If ($Profile -Match $Old) {
    
                        Write-Verbose "Setting ""$SettingName"" to ""$Value""..."
                        $Profile = $Profile -Replace $Old, $New
                        $Pass += ($Old).TrimEnd()
                        
                        # // Set a flag indicating the file should be updated
                        $Changed = $True
    
                    }
    
                    Else {
    
                        Write-Warning "Could not find setting ""$SettingName"" under ""$($entry.name)""."
    
                    }
    
                } # ForEach setting
    
                $Output += $Profile -Replace '^\[?.*\]', "[$($entry.name)]"
                $Output = $Output.Trimstart()
    
            } # Name match
    
            Else {
    
                # Keep the entry
                $Output += $Entry.value -Replace '^\[?.*\]', "[$($entry.name)]"
                $Output = $output.Trimstart()
    
            }
    
        } # ForEach entry in profile hashtable
    
        If ( -Not $Changed) {
    
            Write-Warning "No changes were made to VPN profile ""$name""."
    
        }
    
    } # ForEach Name in ProfileName
    
    # // Only update the file if changes were made
    If (($Changed) -AND ($PsCmdlet.ShouldProcess($Path, "Update rasphone.pbk"))) {
    
        Write-Verbose "Updating $Path..."
        $Output | Out-File -FilePath $Path -Encoding ASCII
    
        If ($PassThru) {
    
            $Pass | Where-Object { $_ -match "\w+" }
    
        }
        
    } # Whatif

} # End Function Update-Rasphone
Start-Sleep -s 2

$RasphonePath = "$env:ProgramData\Microsoft\Network\Connections\Pbk\rasphone.pbk"
$Settings = @{ }
$Settings.Add('IpInterfaceMetric', 2)
$Settings.Add('Ipv6InterfaceMetric', 2)

Update-Rasphone -Path $RasphonePath -ProfileName $ProfileName -Settings $Settings

$Message = "Complete."
Write-Host "$Message"
#PerfCol-HostDSStats.ps1

##TODO
#create gHostingClassName


#TO CHANGE
##change $requiredArgs
##modify parent data
##modify attributes discovered
##modify discovery data class creation MPElement
##change scriptName
##change ending message

Param($vCenterServer,$hostName,$stat,$units,$IntervalSeconds,$viUsername,$viPassword)
#$vCenterServer = $args[0]
#$hostName = $args[1]

$error.clear()
$fail = $false
$scriptName = "PerfCol-HostDSStats.ps1 b04 (auto)"
$opsmgrAPI = New-Object -comObject 'MOM.ScriptAPI'

#global vars
$script:debugLevel = 4									#verbosity
$script:blnWriteToScreen = $false				#write to the screen
$script:blnWriteToOpsMgrLog = $false		#write to the opsmgr log

#$script:strStatToCollect = "disk.write.average"					#stat counter we're grabbing
$script:strStatToCollect = $stat					#stat counter we're grabbing
#$script:strUnits = "kbps"			#units of the stat
$script:strUnits = $units

###COMMON FUNCTIONS
Function Write-Out($msg,$severity)
	{
		$intLevel = 4
		If($intLevel -eq $null)
			{$intLevel = 4}
		
		If($severity -eq $null)
			{$severity = 0}
		
		If($intLevel -le $script:debugLevel)
			{
				If($script:blnWriteToScreen -eq $true)
					{
						Switch($severity)
							{
								0 {$color = "white"}
								1 {$color = "yellow"}
								2 {$color = "magenta"}
							}
						Write-Host -f $color $msg
					}
				Else{}
				If($script:blnWriteToOpsMgrLog -eq $true)
					{
						If($severity -eq 1){$severity = 2}
						ElseIf($severity -eq 2){$severity = 1}
						$opsmgrAPI.LogScriptEvent($scriptName,0,$severity,$msg)
					}
				Else{}
			}
	}

$msg = "Script starting, viUsername: " + $viUsername
write-out $Msg

#parse args
$requiredArgs = $null
$requiredArgs = @()
$requiredArgs += "vCenterServer"
$requiredArgs += "hostName"
$requiredArgs += "IntervalSeconds"
$requiredArgs += "viUsername"
$requiredArgs += "stat"
$requiredArgs += "units"

$failedArgs = $null
$failedArgs = @()
Foreach($requiredArg in $requiredArgs)
	{
		If((Get-Variable $requiredArg -ea silentlycontinue).Value -eq $null)
			{$failedArgs += $requiredArg}
		Else
			{}
	}

If($failedArgs.Count -gt 0)
	{
		$OFS = ","; [string]$strFailedArgs = $failedArgs; $OFS = " "
		$failedArgs = $null
		$msg = "The following required arguments are missing: " + $strFailedArgs
		Write-Out $msg 2
		$fail = $true
	}
Else
	{
		$arrPairs = $null
		$arrPairs = @()
		Foreach($requiredArg in $requiredArgs)
			{
				$argValue = $null
				$argValue = (Get-Variable $requiredArg -ea silentlycontinue).Value
				$arrPairs += $requiredArg + " : " + $argValue
			}
		$OFS = " , "; [string]$strArgPairs = $arrPairs; $OFS = " "
		$msg = "The following args were passed: " + $strArgPairs
		Write-Out $msg
	}

Function Load-MOMSnapin
	{
		$fail = $null
		$fail = $false
		$snapin = "Microsoft.EnterpriseManagement.OperationsManager.Client"
		$msg = "Script is attempting to load snap-in: """ + $snapin + """."
		Write-Out $msg
		$snapinTest = $null
		$snapinTest = Get-PSSnapin $snapin -registered -ea silentlycontinue
		If($snapinTest -ne $null)
			{
				$msg = "The required snap-in is installed on this system: """ + $snapin + """. Adding the snap-in."
				Write-Out $msg
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin -ea silentlycontinue
				If($snapinTest -eq $null)
					{$blnAdded = Add-PSSnapin $snapin}
				Else
					{}
			}
		Else
			{
				$fail = $true
				$msg = "Required Snap-In is not installed on this system: """ + $snapin + """."
				Write-Out $msg 2
			}
		
		If($fail -eq $false)
			{
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin
				if($snapinTest -eq $null)
					{
						$fail = $true
						$msg = "Script didn't complete loading snap-ins; could not add the snapin: """ + $snapin + """."
						Write-Out $msg 2
					}
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function Get-RMSServer
	{
		$RMSServer = $null
		
		$machineKey = "HKLM:\\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Machine Settings"
		If((Test-Path $machineKey) -eq $true)
			{
				$objKey = Get-ItemProperty -path:$machineKey -name:"DefaultSDKServiceMachine" -ErrorAction:SilentlyContinue
				If($objKey -ne $null -and $objKey -ne "")
					{$RMSServer = $objKey.DefaultSDKServiceMachine}
			}
		
		If($RMSServer -eq $null -or $RMSServer -eq "")
			{
				#write-host -f green "ehy"
				$MgmtGroupsKey = $null
				$MgmtGroupsKey = "HKLM:\\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Agent Management Groups"
				If((Test-Path $mgmtGroupsKey) -eq $false)
					{
						$msg = "Error, can't find the RMS Server name in registry"
						Write-Out $msg 2
					}
				Else
					{
						$mgmtGroups = $null
						$mgmtGroups = GCI $MgmtGroupsKey
						#write-host -f cyan $MgmtGroupsKey
						
						If($mgmtGroups -is [array])
							{$strMgmtGroupKey = $mgmtGroups[0].Name}
						Else
							{$strMgmtGroupKey = $mgmtGroups.Name}
						
						$strMgmtGroupKey = $strMgmtGroupKey -replace("HKEY_LOCAL_MACHINE","HKLM:\") 
						#write-host -f yellow $strMgmtGroupKey
						
						$strMachineKey = $null
						$strMachineKey = $strMgmtGroupKey + "\Parent Health Services\0"
						$RMSServer = $null
						$RMSServer = (Get-ItemProperty -path:$strMachineKey -name:"NetworkName" -ErrorAction:SilentlyContinue).NetworkName
					}
			}
		#write-host -f yellow "RMSServer: $RMSServer"
		Return $RMSServer
	}

Function Load-VCSnapin
	{
		$fail = $null
		$fail = $false
		$snapin = "VMware.VimAutomation.Core"
		$msg = "Script is attempting to load snap-in: """ + $snapin + """."
		Write-Out $msg
		$snapinTest = $null
		$snapinTest = Get-PSSnapin $snapin -registered -ea silentlycontinue
		If($snapinTest -ne $null)
			{
				$msg = "The required snap-in is installed on this system: """ + $snapin + """. Adding the snap-in."
				Write-Out $msg
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin -ea silentlycontinue
				If($snapinTest -eq $null)
					{$blnAdded = Add-PSSnapin $snapin}
				Else
					{}
			}
		Else
			{
				$fail = $true
				$msg = "Required Snap-In is not installed on this system: """ + $snapin + """."
				Write-Out $msg 2
			}
		
		If($fail -eq $false)
			{
				$snapinTest = $null
				$snapinTest = Get-PSSnapin $snapin
				if($snapinTest -eq $null)
					{
						$fail = $true
						$msg = "Script didn't complete loading snap-ins; could not add the snapin: """ + $snapin + """."
						Write-Out $msg 2
					}
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function Connect-ToVCenter($user,$pass)
	{
		$fail = $null
		$fail = $false
		
		#it sometimes complains about these variables getting set, probably by other scripts.
		$global:DefaultVIServers = $null
		$global:DefaultVIServer = $null
		
		$wprefTmp = $warningPreference
		$warningPreference = "SilentlyContinue"
		#$blnConnected = Connect-VIServer -server $vCenterServer -User $user -Password $pass| out-null
		$blnConnected = Connect-VIServer -server $vCenterServer # -User $user -Password $pass| out-null
		$warningPreference = $wprefTmp
		$objDC = $null
		$objDC = Get-Datacenter
		If($objDC -eq $null)
			{
				$fail = $true
				$msg = "Could not connect to the vcenter server: """ + $vCenterServer + """."
				Write-Out $msg 2
			}
		Else
			{
				$msg = "Connected to the vcenter server: """ + $vCenterServer + """."
				Write-Out $msg
			}
		
		If($fail -eq $false)
			{$retval = $true}
		Else
			{$retval = $false}
		Return $retval
	}

Function Lookup-DatastoreGUID($datastoreName)
	{
		$hshHostnamesAndGUIDs = $null
		$hshHostnamesAndGUIDs = @{}
		
		$strClassID = $null
		$strClassID = "JPPacks.VMWare.vCenter.vCenterServer.Datacenter.Datastore"
		
		$objClass = $null
		$objClass = Get-MonitoringClass -name $strClassID -path "OperationsManagerMonitoring::"
		If($objClass -is [array])
			{$objClass = $objClass[0]}
		If($objClass -eq $null)
			{
				$msg = "Unable to lookup the class """ + $strClassID + """."
				Write-Out $msg 2
			}
		
		$arrObjHosts = Get-MonitoringObject -monitoringclass $objClass -path "OperationsManagerMonitoring::"
		If($objClass -eq $null)
			{
				$msg = "Unable to lookup the objects of class """ + $strClassID + """."
				Write-Out $msg 2
			}
		Else
			{
				Foreach($objHost in $arrObjHosts)
					{
						$strHostname = $objHost.DisplayName
						If($strHostname -eq $datastoreName)
							{$strGUID = $objHost.Id}
					}
			}
		Return $strGUID
	}

Function Get-SCSIlunUUID($DSName,$objHost)
	{
		$ds = Get-View (Get-View $objHost.ID).ConfigManager.StorageSystem
		foreach ($vol in $ds.FileSystemVolumeInfo.MountInfo) {
			if ($vol.Volume.Name -eq $dsname) {
#				Write-host "DS Name:`t" $vol.Volume.Name
#				Write-host "VMFS UUID:`t" $vol.Volume.Uuid
				foreach ($volid in $vol.Volume.Extent) {
					foreach ($lun in $ds.StorageDeviceInfo.MultipathInfo.Lun){
						if ($lun.Id -eq $volid.DiskName) {
							break
						}
					}
				}
			#Write-Host "LUN Name:`t" $lun.ID
			$lunUUID = $lun.Id
#			$mid = $lun.ID
#			foreach ($id in $ds.StorageDeviceInfo.ScsiLun) {
#				if ($id.CanonicalName -eq $mid) {
#					$uuid = $id.Uuid
#					Write-host "LUN UUID:`t" $uuid
#					}
#				}
			}
		}
		Return $lunUUID
	}

Function Construct-XMLProp ($DSName,$objHost,$strStat,$Statvalue)
	{
		$strHost = $objHost.Name
		$strCounter = $strStat + " from " + $strHost + " (" + $script:strUnits + ")"
		$strCMO_GUID = Lookup-DatastoreGUID $DSName
		$strObject = $DSName
		$strValue = $statValue
		
		$xmlString = $null
		$xmlString += "<Dataitem>"
		$xmlString += "<CustomMonitoringObjectGUID>"
		$xmlString += $strCMO_GUID
		$xmlString += "</CustomMonitoringObjectGUID>"
		$xmlString += "<Object>"
		$xmlString += $strObject
		$xmlString += "</Object>"
		$xmlString += "<Counter>"
		$xmlString += $strCounter
		$xmlString += "</Counter>"
		$xmlString += "<Value>"
		$xmlString += $strValue
		$xmlString += "</Value>"
		$xmlstring += "</Dataitem>"
		
		REturn $xmlString
	}

Function Construct-CSVProp ($DSName,$objHost,$strStat,$Statvalue)
	{
		$strHost = $objHost.Name
		$strCounter = $strStat + " from " + $strHost + " (" + $script:strUnits + ")"
		$strCMO_GUID = Lookup-DatastoreGUID $DSName
		$strObject = $DSName
		$strValue = $Statvalue
		
		$csvString = $null
		$csvString = """"
		$csvString += $strCMO_GUID
		$csvString += ""","""
		$csvString += $strObject
		$csvString += ""","""
		$csvString += $strCounter
		$csvString += ""","""
		$csvString += $strValue
		$csvString += """"
		REturn $csvString
	}

Function Generate-DSNameLunMap($arrDatastores,$objHost)
	{
		$hshMap = $null
		$hshMap = @{}
		
		$ds = Get-View (Get-View $objHost.ID).ConfigManager.StorageSystem
		$arrMounts = $ds.FileSystemVolumeInfo.MountInfo
		Foreach ($mount in $arrMounts)
			{
				$DSLunId = $null
				$DSName = $null
				$DSName = $mount.Volume.Name
				$extent = $mount.volume.extent
				If($extent -ne $null)
					{$DSLunID = $mount.volume.extent[0].diskname}
				Else {}
				$hshMap.Add($DSName,$DSLunID)
			}
		
		Return $hshMap
	}

###MAIN LOOP###

#Load MOM Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-MOMSnapin
		If($blnLoaded -ne $true)
			{$fail = $true}
	}

#Load vCenter Snap-Ins
If($fail -eq $false)
	{
		$blnLoaded = Load-VCSnapin
		If($blnLoaded -ne $true)
			{$fail = $true}
	}

#Connect to vCenter
If($fail -eq $false)
	{
		$blnConnected = Connect-ToVCenter $viUsername $viPassword
		If($blnConnected -eq $false)
			{$fail = $true}
		Else
			{}
	}

$opsmgrRMS = Get-RMSServer
If($opsmgrRMS -eq $null -or $opsmgrRMS -eq "")
	{
		$msg = "Could not get the RMS server name from the registry."
		Write-Out $msg
		$fail = $true
	}

If($fail -eq $false)
	{
		$msg = "Connecting to the management server """ + $opsmgrRMS + """."
		Write-Out $msg
		$strConnect = New-ManagementGroupConnection $opsmgrRMS
		$msg = "Connection result: """ + $strConnect + """."
		Write-Out $msg
	}

#create the pbag
If($fail -eq $false)
	{
		$intSeconds = 10
		[int]$maxSamples = $IntervalSeconds / $intSeconds
		$strStat = $script:strStatToCollect
		$bag = $opsmgrAPI.CreatePropertyBag()
		
		#grab the host we're working on
		$objHost = Get-VMHost -name $hostName
		
		#grab the host's datastores (all)
		$arrDatastores = $null
		$arrDatastores = Get-Datastore -VMHost $objHost
		$strCounter = $strStat + " from " + $hostName
		
		#grab the stats
		$arrStats = Get-Stat -entity $objHost -stat $strStat -intervalsecs $IntervalSeconds -maxsamples 1
		#write-host -f yellow "dblStatValue: $dblStatValue"
		#$arrStats | out-host
		
		#generate a map of dsName to DS_SCSILunId
		$hshDSNamesIds = $null
		$hshDSNamesIds = Generate-DSNameLunMap $arrDatastores $objHost
		
		#generate the pbags
		$i = 0
		$keys = $hshDSNamesIds.Keys
		Foreach($DSName in $keys)
			{
				#$DSName = $DSName
				$DSLunId = $hshDSNamesIds.$DSName
				$strValue = $arrStats | Where-Object {$_.Instance -eq $DSLunId}
				
#				Write-Host "`nStat: $strStat"
#				Write-Host "DSName: $DSName"
#				Write-Host "DSLunId: $DSLunId"
#				Write-Host "Stat Value: $strValue"
				
				$pBagName = $i
				#[xml]$pBagValue = Construct-XMLProp $DSName $objHost $stat $Statvalue
				$pBagValue = Construct-CSVProp $DSName $objHost $strStat $strValue
				$bag.AddValue($pBagName,$pBagValue)
				$i++
			}
		
		$bag
		# $opsmgrAPI.Return($bag)
		$msg = "Errors for run on host """ + $hostName + """: " + $Error
		Write-Out $msg
	}

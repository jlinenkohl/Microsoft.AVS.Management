<#
    .SYNOPSIS
     This function updates all hosts in the specified cluster to have the following iSCSI configurations:

     1. SCSI IP address are added as dynamic iSCSI addresses.
     2. iSCSI Software Adapter is enabled.
     3. Apply iSCSI best practices configuration on dynamic targets.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER ScsiIpAddress
     IP Address to add as dynamic iSCSI target

    .PARAMETER LoginTimeout
     Optional. Login timeout in seconds (default 30)

    .PARAMETER NoopOutTimeout
    Optional. NoopOut timeout in seconds (default 30)

    .PARAMETER RecoveryTimeout
    Optional. Recovery timeout in seconds (default 45)

    .EXAMPLE
     Set-VmfsIscsi -ClusterName "myCluster" -ScsiIpAddress "192.168.0.1"

    .INPUTS
     vCenter cluster name, Primary SCSI IP Addresses.

    .OUTPUTS
     None.
#>
function Set-VmfsIscsi {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Primary IP Address to add as dynamic iSCSI target')]
        [ValidateNotNull()]
        [String]
        $ScsiIpAddress,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'Login timeout in seconds'
        )]
        [ValidateRange(1, 60)]
        [int] $LoginTimeout = 30,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'NoopOut timeout in seconds'
        )]
        [ValidateRange(10, 30)]
        [int] $NoopOutTimeout = 30,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'Recovery timeout in seconds'
        )]
        [ValidateRange(1, 120)]
        [int] $RecoveryTimeout = 45
    )

    try {
        [ipaddress] $ScsiIpAddress
    }
    catch {
        throw "Invalid SCSI IP address $ScsiIpAddress provided."
    }

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $VMHosts = $Cluster | Get-VMHost
    foreach ($VMHost in $VMHosts) {
        $Iscsi = $VMHost | Get-VMHostStorage
        if ($Iscsi.SoftwareIScsiEnabled -ne $true) {
            $VMHost | Get-VMHostStorage | Set-VMHostStorage -SoftwareIScsiEnabled $True | Out-Null
        }

        $IscsiAdapter = $VMHost | Get-VMHostHba -Type iScsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
        if (!(Get-IScsiHbaTarget -IScsiHba $IscsiAdapter -Type Send -ErrorAction stop | Where-Object {$_.Address -cmatch $ScsiIpAddress})) {
            New-IScsiHbaTarget -IScsiHba $IscsiAdapter -Address $ScsiIpAddress -ErrorAction stop
        }

        $EsxCli = $VMHost | Get-EsxCli -v2
        $IscsiArgs = $EsxCli.iscsi.adapter.discovery.sendtarget.param.get.CreateArgs()
        $IscsiArgs.adapter = $IscsiAdapter.Device
        $IscsiArgs.address = $ScsiIpAddress

        function Set-IscsiConfig($Name, $Value) {
            $CurrentValue = $EsxCli.iscsi.adapter.discovery.sendtarget.param.get.invoke($IscsiArgs) | Where-Object {$_.name -eq $Name}
            if ($CurrentValue.Current -ne $Value) {
                $IscsiArgs = $EsxCli.iscsi.adapter.discovery.sendtarget.param.set.CreateArgs()
                $IscsiArgs.adapter = $IscsiAdapter.Device
                $IscsiArgs.address = $ScsiIpAddress
                $IscsiArgs.value = $Value
                $IscsiArgs.key = $Name
                $EsxCli.iscsi.adapter.discovery.sendtarget.param.set.invoke($IscsiArgs) | Out-Null
            }
        }

        Set-IscsiConfig -Name "DelayedAck" -Value "false"
        Set-IscsiConfig -Name "LoginTimeout" -Value $LoginTimeout
        Set-IscsiConfig -Name "NoopOutTimeout" -Value $NoopOutTimeout
        Set-IscsiConfig -Name "RecoveryTimeout" -Value $RecoveryTimeout
    }

    Write-Host "Successfully configured VMFS iSCSI for cluster $ClusterName."
}

<#
    .SYNOPSIS
     This function updates all hosts in the specified cluster to have the following iSCSI configurations:

     1. SCSI IP address are added as static iSCSI addresses.
     2. iSCSI Software Adapter is enabled.
     3. Apply iSCSI best practices configuration on static targets.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER ScsiIpAddress
     IP Address to add as static iSCSI target

     .PARAMETER ScsiName
     iSCSI target name

     .PARAMETER LoginTimeout
     Optional. Login timeout in seconds (default 30)

    .PARAMETER NoopOutTimeout
    Optional. NoopOut timeout in seconds (default 30)

    .PARAMETER RecoveryTimeout
    Optional. Recovery timeout in seconds (default 45)

    .EXAMPLE
     Set-VmfsIscsi -ClusterName "myCluster" -ScsiIpAddress "192.168.0.1" -IscsitName "iqn.1998-01.com.vmware:target-1"

    .INPUTS
     vCenter cluster name, Primary SCSI IP Addresses. iSCSI target name

    .OUTPUTS
     None.
#>
function Set-VmfsStaticIscsi {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Primary IP Address to add as static iSCSI target')]
        [ValidateNotNull()]
        [String]
        $ScsiIpAddress,

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'iSCSI target name')]
        [String] $ScsiName,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'Login timeout in seconds'
        )]
        [ValidateRange(1, 60)]
        [int] $LoginTimeout = 30,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'NoopOut timeout in seconds'
        )]
        [ValidateRange(10, 30)]
        [int] $NoopOutTimeout = 30,

        [Parameter (
            Mandatory = $false,
            HelpMessage = 'Recovery timeout in seconds'
        )]
        [ValidateRange(1, 120)]
        [int] $RecoveryTimeout = 45
    )
    try {
        [ipaddress] $ScsiIpAddress
    }
    catch {
        throw "Invalid SCSI IP address $ScsiIpAddress provided."
    }

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $VMHosts = $Cluster | Get-VMHost
    foreach ($VMHost in $VMHosts) {
        $Iscsi = $VMHost | Get-VMHostStorage
        if ($Iscsi.SoftwareIScsiEnabled -ne $true) {
            $VMHost | Get-VMHostStorage | Set-VMHostStorage -SoftwareIScsiEnabled $True | Out-Null
        }

        $IscsiAdapter = $VMHost | Get-VMHostHba -Type iScsi | Where-Object { $_.Model -eq "iSCSI Software Adapter" }
        if (!(Get-IScsiHbaTarget -IScsiHba $IscsiAdapter -Type "Static" -ErrorAction stop | Where-Object { $_.Address -cmatch $ScsiIpAddress })) {
            New-IScsiHbaTarget -IScsiHba $IscsiAdapter -Type "Static" -Address $ScsiIpAddress -IScsiName $ScsiName -ErrorAction stop
            Write-Verbose "Added static iSCSI target $ScsiName with address $ScsiIpAddress to $VMHost"
        }

        $EsxCli = $VMHost | Get-EsxCli -v2

        function Set-StaticIscsiConfig($Name, $Value) {
            $IscsiArgs = $EsxCli.iscsi.adapter.target.portal.param.get.CreateArgs()
            $IscsiArgs.adapter = $IscsiAdapter.Device
            $IscsiArgs.address = $ScsiIpAddress
            $IscsiArgs.name = $ScsiName
            $CurrentValue = $EsxCli.iscsi.adapter.target.portal.param.get.invoke($IscsiArgs) | Where-Object { $_.name -eq $Name }
            if ($CurrentValue.Current -ne $Value) {
                $IscsiArgs = $EsxCli.iscsi.adapter.target.portal.param.set.CreateArgs()
                $IscsiArgs.adapter = $IscsiAdapter.Device
                $IscsiArgs.address = $ScsiIpAddress
                $IscsiArgs.name = $ScsiName
                $IscsiArgs.inherit = $false
                $IscsiArgs.value = $Value
                $IscsiArgs.key = $Name
                $EsxCli.iscsi.adapter.target.portal.param.set.invoke($IscsiArgs) | Out-Null
                Write-verbose "Set $Name to $Value for $ScsiName"
            }
        }

        Set-StaticIscsiConfig -Name "DelayedAck" -Value "false"
        Set-StaticIscsiConfig -Name "LoginTimeout" -Value $LoginTimeout
        Set-StaticIscsiConfig -Name "NoopOutTimeout" -Value $NoopOutTimeout
        Set-StaticIscsiConfig -Name "RecoveryTimeout" -Value $RecoveryTimeout
    }

    Write-Host "Successfully configured VMFS iSCSI for cluster $ClusterName."
}

<#
    .SYNOPSIS
     Creates a new VMFS datastore and mounts to a VMware cluster.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER DatastoreName
     Datastore name

    .PARAMETER DeviceNaaId
     NAA ID of device used to create a new VMFS datastore

    .PARAMETER Size
     Datastore capacity size in bytes

    .EXAMPLE
     New-VmfsDatastore -ClusterName "myCluster" -DatastoreName "myDatastore" -DeviceNaaId $DeviceNaaId -Size <size-in-bytes>

    .INPUTS
     vCenter cluster name, datastore name, device NAA ID and datastore size.

    .OUTPUTS
     None.
#>
function New-VmfsDatastore {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Name of VMFS datastore to be created in vCenter')]
        [ValidateNotNull()]
        [String]
        $DatastoreName,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'NAA ID of device used to create a new VMFS datastore')]
        [ValidateNotNull()]
        [String]
        $DeviceNaaId,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Capacity of new datastore in bytes')]
        [ValidateNotNull()]
        [String]
        $Size
    )

    try {
        $SizeInBytes = [UInt64] $Size
    } catch {
        throw "Invalid Size $Size provided."
    }

    if (($SizeInBytes -lt 1GB) -or ($SizeInBytes -gt 64TB)) {
        throw "Invalid Size $SizeInBytes provided. Size should be between 1 GB and 64 TB."
    }

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
    if ($Datastore) {
        throw "Unable to create a datastore. Datastore '$DatastoreName' already exists."
    }

    # Create a new VMFS datastore with the specified size and rescan storage
    try {
        Write-Host "Creating datastore $DatastoreName..."

        $TotalSectors = $SizeInBytes / 512
        $Esxi = $Cluster | Get-VMHost | Where-Object { ($_.ConnectionState -eq 'Connected') } | Select-Object -last 1
        $EsxiView = Get-View -ViewType HostSystem -Filter @{"Name" = $Esxi.name}
        $DatastoreSystem = Get-View -Id $EsxiView.ConfigManager.DatastoreSystem
        $Device = $DatastoreSystem.QueryAvailableDisksForVmfs($null) | Where-Object { ($_.CanonicalName -eq $DeviceNaaId) }
        $DatastoreCreateOptions = $DatastoreSystem.QueryVmfsDatastoreCreateOptions($Device.DevicePath, $null)

        $VmfsDatastoreCreateSpec = New-Object VMware.Vim.VmfsDatastoreCreateSpec
        $VmfsDatastoreCreateSpec.DiskUuid = $Device.Uuid
        $VmfsDatastoreCreateSpec.Partition = $DatastoreCreateOptions[0].Spec.Partition
        $VmfsDatastoreCreateSpec.Partition.Partition[0].EndSector = $VmfsDatastoreCreateSpec.Partition.Partition[0].StartSector + $TotalSectors
        $VmfsDatastoreCreateSpec.Partition.TotalSectors = $TotalSectors
        $VmfsDatastoreCreateSpec.Vmfs = New-Object VMware.Vim.HostVmfsSpec
        $VmfsDatastoreCreateSpec.Vmfs.VolumeName = $DatastoreName

        $HostScsiDiskPartition = New-Object VMware.Vim.HostScsiDiskPartition
        $HostScsiDiskPartition.DiskName = $DeviceNaaId
        $HostScsiDiskPartition.Partition = $DatastoreCreateOptions[0].Info.Layout.Partition[0].Partition

        $VmfsDatastoreCreateSpec.Vmfs.Extent = $HostScsiDiskPartition
        $VmfsDatastoreCreateSpec.vmfs.MajorVersion = $DatastoreCreateOptions[0].Spec.Vmfs.MajorVersion

        $DatastoreSystem.CreateVmfsDatastore($VmfsDatastoreCreateSpec)
    } catch {
        Write-Error $Global:Error[0]
    }

    $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs | Out-Null
    $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
    if (-not $Datastore -or $Datastore.type -ne "VMFS") {
        throw "Failed to create datastore $DatastoreName."
    }
}

<#
    .DESCRIPTION
     Detach and unmount a VMFS datastore from a cluster.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER DatastoreName
     Datastore name

    .EXAMPLE
     Dismount-VmfsDatastore -ClusterName "myCluster" -DatastoreName "myDatastore"

    .INPUTS
     vCenter cluster name and datastore name.

    .OUTPUTS
     None.
#>
function Dismount-VmfsDatastore {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Name of VMFS datastore to be unmounted in vCenter')]
        [ValidateNotNull()]
        [String]
        $DatastoreName
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
    if (-not $Datastore) {
        throw "Datastore $DatastoreName does not exist."
    }
    if ("VMFS" -ne $Datastore.Type) {
        throw "Datastore $DatastoreName is of type $($Datastore.Type). This cmdlet can only process VMFS datastores."
    }

    Write-Host "Unmounting datastore $DatastoreName from all hosts, detaching SCSI devices, NVMe/TCP devices are not detached."
    $VMHosts = $Cluster | Get-VMHost
    foreach ($VMHost in $VMHosts) {
        $IsDatastoreConnectedToHost = Get-Datastore -VMHost $VMHost | Where-Object {$_.name -eq $DatastoreName}
        if ($null -ne $IsDatastoreConnectedToHost) {
            $VMs = $Datastore | Get-VM
            if ($VMs -and $VMs.Count -gt 0) {
                $vmNames = $VMs | Join-String -SingleQuote -Property {$_.Name}  -Separator ", "
                throw "Cannot unmount datastore $DatastoreName. It is already in use by $vmNames."
            }

            $Datastore = Get-Datastore -Name $DatastoreName
            $VmfsUuid = $Datastore.ExtensionData.info.Vmfs.uuid
            $ScsiLunUuid = ($Datastore | Get-ScsiLun).ExtensionData.uuid | Select-Object -last 1
            $HostStorageSystem = Get-View $VMHost.Extensiondata.ConfigManager.StorageSystem

            $HostStorageSystem.UnmountVmfsVolume($VmfsUuid) | Out-Null
            Write-Host "Datastore unmounted."

            $HostViewDiskName = $Datastore.ExtensionData.Info.vmfs.extent[0].Diskname;
            if(($null -ne $HostViewDiskName) -and ($HostViewDiskName.StartsWith("eui."))){
               Write-Host "Device UUID $($VmfsUuid) is an NVMe/TCP volume, not required to be detached, and can be mounted back to host as needed."
            }
            else {
                  $HostStorageSystem.DetachScsiLun($ScsiLunUuid) | Out-Null
            }
            Write-Host "Rescanning now.."
            $VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs | Out-Null
        }
    }
}

<#
    .DESCRIPTION
     Expand existing VMFS volume to new size.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER DeviceNaaId
     NAA ID of device associated with the existing VMFS volume (optional). If not provided, the DatastoreName value must be provided instead.

    .PARAMETER DatastoreName
     Datastore name (optional). If not provided, the DeviceNaaId value must be provided instead.

    .EXAMPLE
     Resize-VmfsVolume -ClusterName "myClusterName" -DeviceNaaId $DeviceNaaId

    .INPUTS
     vCenter cluster name and device NAA ID.

    .OUTPUTS
     None.
#>
function Resize-VmfsVolume {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]
    Param (
        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory=$false,
            HelpMessage = 'NAA ID of device associated with the existing VMFS volume')]
        [String]
        $DeviceNaaId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'Existing datastore name')]
        [String]
        $DatastoreName
    )

    if ((-not $DeviceNaaId) -and (-not $DatastoreName)) {
        throw "One of DeviceNaaId or DatastoreName values must be provided."
    }

    if ($DeviceNaaId -and $DatastoreName) {
        throw "Cannot provide values for both DeviceNaaId and DatastoreName."
    }

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    if ($DatastoreName) {
        $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
        if (-not $Datastore) {
            throw "Datastore $DatastoreName does not exist."
        }

        if ($Datastore.Type -ne "VMFS") {
            throw "Datastore $DatastoreName is of type $($Datastore.Type). This cmdlet can only process iSCSI datastores."
        }

        $DatastoreToResize = $Datastore
    } else {
        $Esxi = $Cluster | Get-VMHost | Where-Object { ($_.ConnectionState -eq 'Connected') } | Select-Object -last 1
        $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba | Out-Null
        $Datastores = $Esxi | Get-Datastore -ErrorAction stop
        foreach ($Datastore in $Datastores) {
            $CurrentNaaId = $Datastore.ExtensionData.Info.Vmfs.Extent.DiskName

            if ($CurrentNaaId -eq $DeviceNaaId) {
                $DatastoreToResize = $Datastore
                break
            }
        }
    }

    if (-not $DatastoreToResize) {
        throw "Failed to re-size VMFS volume, datastore not found."
    }

    $NaaId = $DatastoreToResize.ExtensionData.Info.Vmfs.Extent.DiskName
    if (-not(
        $NaaId.StartsWith("naa.60003ff") -or # Microsoft
        $NaaId.StartsWith("naa.600a098") -or # NetApp
        $NaaId.StartsWith("naa.624a937"))) { # Pure Storage
        throw "The datastore with NAA $NaaId is not supported for VMFS volume re-size."
    }

    foreach ($DatastoreHost in $DatastoreToResize.ExtensionData.Host.Key) {
      Get-VMHost -id "HostSystem-$($DatastoreHost.value)" | Get-VMHostStorage -RescanAllHba -RescanVmfs -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    }

    $Esxi = Get-View -Id ($DatastoreToResize.ExtensionData.Host | Select-Object -last 1 | Select-Object -ExpandProperty Key)
    $DatastoreSystem = Get-View -Id $Esxi.ConfigManager.DatastoreSystem
    $ExpandOptions = $DatastoreSystem.QueryVmfsDatastoreExpandOptions($DatastoreToResize.ExtensionData.MoRef)

    $LunSizeGB = ($DatastoreToResize | Get-ScsiLun).CapacityGB | Select-Object -last 1
    $CurrentDatastoreSizeGB = $([math]::Ceiling($DatastoreToResize.ExtensionData.Info.Vmfs.Capacity / 1GB))
    if ($CurrentDatastoreSizeGB -lt $LunSizeGB) {
        Write-Host "Increasing the size of the VMFS volume..."
        try {
            $DatastoreSystem.ExpandVmfsDatastore($DatastoreToResize.ExtensionData.MoRef, $ExpandOptions[0].spec)
        } catch {
            $exceptionMessage = $_.Exception.Message
            throw "Unable to expand VMFS datastore $($DatastoreToResize.Name): $exceptionMessage"
        }

        $UpdatedDatastore = Get-Datastore -Name $DatastoreToResize.Name -ErrorAction Ignore
        if (-not $UpdatedDatastore) {
            throw "Datastore $($DatastoreToResize.Name) does not exist after expanding."
        }

        $UpdatedDatastoreSizeGB = $([math]::Ceiling($UpdatedDatastore.ExtensionData.Info.Vmfs.Capacity / 1GB))
        Write-Host "Size of datastore $($DatastoreToResize.Name) has been increased from $CurrentDatastoreSizeGB GB to $UpdatedDatastoreSizeGB GB."
    } else {
        Write-Host "Unable to expand datastore $($DatastoreToResize.Name) since it is already at maximum size."
    }
}

<#
    .DESCRIPTION
     Re-signature existing VMFS volume to recover to previous version.

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER DeviceNaaId
     NAA ID of device associated with the existing VMFS volume

    .PARAMETER DatastoreName
     Datastore name (optional). If not provided, an automatically generated name will be used.

    .EXAMPLE
     Restore-VmfsVolume -ClusterName "myClusterName" -DeviceNaaId $DeviceNaaId

    .INPUTS
     vCenter cluster name and device NAA ID.

    .OUTPUTS
     None.
#>
function Restore-VmfsVolume {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
            Mandatory=$true,
            HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
            Mandatory=$true,
            HelpMessage = 'NAA ID of device associated with the existing VMFS volume')]
        [ValidateNotNull()]
        [String]
        $DeviceNaaId,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'New datastore name')]
        [String]
        $DatastoreName
    )

    if (!($DeviceNaaId -like 'naa.624a9370*' -or $DeviceNaaId -like 'naa.600a098*' -or $DeviceNaaId -like 'eui.*')) {
        throw "Invalid Device NAA ID $DeviceNaaId provided."
    }

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    if ($DatastoreName) {
        $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
        if ($Datastore) {
            throw "Datastore '$Datastore' already exists."
        }
    }

    $Esxi = $Cluster | Get-VMHost | Where-Object { ($_.ConnectionState -eq 'Connected') } | Select-Object -last 1
    $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba | Out-Null

    $HostStorageSystem = Get-View -ID $Esxi.ExtensionData.ConfigManager.StorageSystem
    $ResigVolumes = $HostStorageSystem.QueryUnresolvedVmfsVolume()

    foreach ($ResigVolume in $ResigVolumes) {
        foreach ($ResigExtent in $ResigVolume.Extent) {
            if ($ResigExtent.Device.DiskName -eq $DeviceNaaId) {
                if ($ResigVolume.ResolveStatus.Resolvable -eq $false) {
                    if ($ResigVolume.ResolveStatus.MultipleCopies -eq $true) {
                        Write-Error "The volume cannot be re-signatured as more than one non re-signatured copy is present."
                        Write-Error "The following volume(s) need to be removed/re-signatured first:"
                        $ResigVolume.Extent.Device.DiskName | Where-Object {$_ -ne $DeviceNaaId}
                    }

                    throw "Failed to re-signature VMFS volume."
                } else {
                    $VolumeToResignature = $ResigVolume
                    break
                }
            }
        }
    }

    if ($null -eq $VolumeToResignature) {
        Write-Error "No unresolved volume found on the created volume."
        throw "Failed to re-signature VMFS volume."
    }

    Write-Host "Starting re-signature for VMFS volume..."
    $EsxCli = Get-EsxCli -VMHost $Esxi -v2 -ErrorAction stop
    $ResigOp = $EsxCli.storage.vmfs.snapshot.resignature.createargs()
    $ResigOp.volumelabel = $VolumeToResignature.VmfsLabel
    $EsxCli.storage.vmfs.snapshot.resignature.invoke($ResigOp) | Out-Null

    Start-Sleep -s 5

    # If a new datastore name is specified by the user
    if (-not [string]::IsNullOrEmpty($DatastoreName)) {
        $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS | Out-Null
        $ds = $Esxi | Get-Datastore -ErrorAction stop | Where-Object { $_.ExtensionData.Info.Vmfs.Extent.DiskName -eq $DeviceNaaId }
        # Snapshot datastore will always start with "snap*""
        if (-not $ds.Name -like "snap*") {
            throw "Can't rename datastore $($ds.Name), the datastore is not restored from snapshot..."
        }
        Write-Host "Renaming $($ds.Name) to $DatastoreName...."
        $ds | Set-Datastore -Name $DatastoreName -ErrorAction stop | Out-Null
    }

    $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS | Out-Null
}

<#
    .SYNOPSIS
     Rescans host storage

    .PARAMETER VMHostName
     Name of the VMHost (ESXi server)


    .EXAMPLE
     Sync-VMHostStorage -VMHostName "vmhost1"

    .INPUTS
     VMHostName.

    .OUTPUTS
     None.
#>
function Sync-VMHostStorage {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]
    Param (
        [Parameter(
                Mandatory=$true,
                HelpMessage = 'VMHost name')]
        [ValidateNotNull()]
        [String]
        $VMHostName
    )

    Get-VMHost $VMHostName | Get-VMHostStorage -RescanAllHba -RescanVMFS | Out-Null
}

<#
    .SYNOPSIS
     Rescans all host storage in cluster

    .PARAMETER ClusterName
     Cluster name

    .EXAMPLE
     Sync-ClusterVMHostStorage -ClusterName "myClusterName"

    .INPUTS
     vCenter cluster name

    .OUTPUTS
     None
#>
function Sync-ClusterVMHostStorage {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]
    Param (
        [Parameter(
                Mandatory=$true,
                HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS | Out-Null
}

<#
    .SYNOPSIS
     This function removes the specified static iSCSI configurations from all of Esxi Hosts in a cluster

    .PARAMETER ClusterName
     Cluster name

    .PARAMETER iSCSIAddress
     iSCSI target address. Multiple addresses can be seperated by ","

    .PARAMETER VMHostName
      Name of the VMHost (ESXi server). If not specified, all hosts in the cluster will be updated.

    .EXAMPLE
     Remove-VMHostStaticIScsiTargets -ClusterName "myCluster" -ISCSIAddress "192.168.1.10,192.168.1.11"

    .INPUTS
     vCenter cluster name and iSCSi target address

    .OUTPUTS
     None
#>
function Remove-VMHostStaticIScsiTargets {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param (
        [Parameter(
                Mandatory=$true,
                HelpMessage = 'Cluster name in vCenter')]
        [ValidateNotNull()]
        [String]
        $ClusterName,

        [Parameter(
                Mandatory=$false,
                HelpMessage = 'VMHost name')]        
        [String]
        $VMHostName,

        [Parameter(
                Mandatory=$true,
                HelpMessage = 'IP Address of static iSCSI target to remove. Multiple addresses can be seperated by ","')]
        [ValidateNotNull()]
        [String]
        $iSCSIAddress
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $iSCSIAddressList = $iSCSIAddress.Split(",")
    $DatastoreDisks = Get-Datastore | Select-Object -ExpandProperty ExtensionData | Select-Object -ExpandProperty Info | Select-Object -ExpandProperty Vmfs | Select-Object -ExpandProperty Extent
    $TargetsChanged = $False

    $VMHosts = $null
    if ($VMHostName) {
        $VMHosts = $Cluster| Get-VMHost -Name $VMHostName
    }
    else {
        $VMHosts = $Cluster | Get-VMHost
    }
    if (-not $VMHosts) {
        throw "No hosts found in cluster $ClusterName"
    }

    # Remove iSCSI ip address from static discovery from all of hosts if there is a match
    $HBAs =  $VMHosts | Get-VMHostHba -Type iScsi
    foreach ($HBA in $HBAs) {
        $DeviceIds = ($HBA | Get-ScsiLun).CanonicalName

        # Find if any of the devices is used as backing for a datastore
        $IsDeviceInUse = $False
        foreach ($DeviceId in $DeviceIds) {
            if ($DatastoreDisks.DiskName -contains $DeviceId) {
                $IsDeviceInUse = $True
                break
            }
        }
        if ($IsDeviceInUse) {
            Write-Warning "Datastore disk $DeviceId for host $($HBA.VMHost.Name) is in use, skipping iSCSI target removal"
        }
        else {
            $Targets = $HBA | Get-IScsiHbaTarget | Where-Object {($_.Type -eq "Static") -and ($iSCSIAddressList -contains $_.Address)}
            foreach ($Target in $Targets) {
                Write-Host "Removing iSCSI target $Target from host $($HBA.VMHost.Name)"
                try {
                    $Target | Remove-IScsiHbaTarget -Confirm:$false
                    $TargetsChanged = $True
                }
                catch {
                    Write-Error "Failed to remove iSCSI target $Target from host $($HBA.VMHost.Name) with error: $_"
                }
            }
        }
    }

    if ($TargetsChanged) {
        # Rescan after removing the iSCSI targets
        Write-Host "Rescanning storage"
        $Cluster | Get-VMHost | Get-VMHostStorage -RescanAllHba -RescanVMFS | Out-Null
    }
}

<#
    .SYNOPSIS
     This function connects all ESXi host(s) to the specified storage cluster node/target via NVMe/TCP.

     1. vSphere Cluster Name
     2. Storage Node EndPoint Network address
     3. Storage SystemNQN
     4. NVMe/TCP Admin Queue Size (Optional)
     5. Controller Id (Optional)
     6. IO Queue Number (Optional)
     7. IO Queue Size (Optional)
     8. Keep Alive Timeout (Optional)
     9. Target Port Number (Optional)


    .PARAMETER ClusterName
     vSphere Cluster Name

    .PARAMETER NodeAddress
     Storage Node EndPoint Address

    .PARAMETER StorageSystemNQN
     Storage system NQN

    .PARAMETER  AdminQueueSize
     NVMe/TCP Admin Queue Size, default 32

    .PARAMETER  ControllerId
     NVMe/TCP Controller ID, default 65535

    .PARAMETER  IoQueueNumber
     IO Queue Number, default 8

    .PARAMETER IoQueueSize
     IO Queue Size, default 256

    .PARAMETER KeepAliveTimeout
     Keep Alive Timeout, default 256

    .PARAMETER  PortNumber
     Target Port Number, default 4420

    .EXAMPLE
     Connect-NVMeTCPTarget ClusterName "Cluster-001" -NodeAddress "192.168.0.1" -StorageSystemNQN "nqn.2016-01.com.lightbitslabs:uuid:46edb489-ba18-4dd4-a157-1d8eb8c32e21"

    .INPUTS
     vSphere Cluster Name, Storage Node Address, Storage System NQN

    .OUTPUTS
     None.
#>
function Connect-NVMeTCPTarget {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName,

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Target storage Node datapath address')]
        [string] $NodeAddress,

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Target storage SystemNQN')]
        [string]     $StorageSystemNQN,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'NVMe/TCP Admin Queue Size')]
        [int]     $AdminQueueSize = 32,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'NVMe/TCP Controller Id')]
        [int]     $ControllerId = 65535,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'NVMe/TCP IO Queue Number')]
        [int]     $IoQueueNumber = 8,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'NVMe/TCP IO Queue Size')]
        [int]     $IoQueueSize = 256,


        [Parameter(
            Mandatory = $false,
            HelpMessage = 'Keep Alive Timeout')]
        [int]     $KeepAliveTimeout = 256,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'Port Number')]
        [int]     $PortNumber = 4420

    )

    Write-Host "Connecting to target via Storage Adapter from ESXi host(s) under Cluster " $ClusterName
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $VmHosts = $Cluster | Get-VMHost

    foreach ($VmHost in $VMHosts) {

        if ($VmHost.ConnectionState -ne "Connected") {
            Write-Host "ESXi host $($VmHost.Name) must be in connected state, ignoring operation because of current state "$VmHost.ConnectionState
            Write-Host ""
            continue
        }

        $StorageAdapters = $VmHost | Get-VMHostHba
        $HostEsxcli = $null;
        try {
            $HostEsxcli = Get-EsxCli -VMHost $VmHost.Name
        }
        catch {
            Write-Error "Failed to execute Get-EsxCli cmdlet on host $($VmHost.Name), continue connecting rest of the host(s) "
            continue
        }

        Write-Host "Connected to host via PowerCLI-esxcli $($VmHost.Name)"

        foreach ($StorageAdapter in $StorageAdapters) {

            if (($StorageAdapter.Driver -eq "nvmetcp")) {

                if ($HostEsxcli) {
                    $Name = $StorageAdapter.Name.ToString().Trim()
                    Write-Host "Connecting Adapter $($Name) to storage controller"
                    try {

                        $EsxCliResult = $HostEsxcli.nvme.fabrics.connect(
                            $Name, $AdminQueueSize, $ControllerId,
                            $null, $IoQueueNumber, $IoQueueSize, $NodeAddress,
                            $KeepAliveTimeout, $PortNumber, $StorageSystemNQN, $null, $null
                        );

                        if ($EsxCliResult) {
                            Write-Host "ESXi host $($VmHost.Name) is connected to storage controller via " $Name
                        }
                        else {
                            Write-Host "Failed to connect ESXi host $($VmHost.Name) to storage controller "
                        }

                        Write-Host "Connecting Controller status: "$EsxCliResult;
                    }
                    catch {
                        Write-Error "Failed to connect ESXi NVMe/TCP storage adapter to storage controller. $($_.Exception) "
                    }
                }
            }
        }
        Write-Host "Rescanning NVMe/TCP storage adapter.."
        $RescanResult = Get-VMHostStorage -VMHost $VmHost.Name -RescanAllHba
        Write-Host "Rescanning Completed."
        Write-Host ""
    }


}

<#
    .SYNOPSIS
     This function disconnects all ESXi host(s) from the specified storage cluster node/target.

     1. vSphere Cluster Name
     2. Storage SystemNQN

    .PARAMETER ClusterName
     vSphere Cluster Name

    .PARAMETER StorageSystemNQN
     Storage system NQN

    .EXAMPLE
     Disconnect-NVMeTCPTarget -ClusterName "Cluster-001"  -StorageSystemNQN "nqn.2016-01.com.lightbitslabs:uuid:46edb489-ba18-4dd4-a157-1d8eb8c32e21"

    .INPUTS
     vSphere Cluster Name, Storage SystemNQN

    .OUTPUTS
     None.
#>
function Disconnect-NVMeTCPTarget {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName,

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Target storage SystemNQN')]
        [string] $StorageSystemNQN
    )

    Write-Host "Disconnecting ESXi host(s) from storage target under Cluster " $ClusterName
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $VmHosts = $Cluster | Get-VMHost
    foreach ($VmHost in $VMHosts) {

        if ($VmHost.ConnectionState -ne "Connected") {
            Write-Host "ESXi host $($VmHost.Name)  must be in connected state, ignoring operation because of current state "$VmHost.ConnectionState
            Write-Host ""
            continue
        }

        $ProvisionedDevices = Get-Datastore -VMHost $VmHost.Name | where-object{$_.ExtensionData.Info.Vmfs.Extent.DiskName -like  'eui.*'}
        if(($Null -ne $ProvisionedDevices) -and ($ProvisionedDevices.Length -gt 0)){
            Write-Host "Storage device(s) found on host $($VmHost.Name) from target, skipping to disconnect."
            Write-Host ""
            continue
        }

        $StorageAdapters = $VmHost | Get-VMHostHba
        if (!$StorageAdapters) {
            Write-Host "No Storage adapter to disconnect"
            continue

        }

        $HostEsxcli = $null;
        try {
            $HostEsxcli = Get-EsxCli -VMHost $VmHost.Name
        }
        catch {
            Write-Error "Failed to execute Get-EsxCli cmdlet on host $($VmHost.Name), continue diconnecting rest of the host(s) "
            continue
        }

        Write-Host "Connected to host via PowerCLI-esxcli $($VmHost.Name)"
        if ($HostEsxcli) {
            $Controllers = $HostEsxcli.nvme.controller.list();
            if ($Controllers -and $Controllers.Count -ge 0) {
                foreach ($item in $Controllers) {

                    try {
                        Write-Host "Diconnecting "$item.Adapter
                        $result = $HostEsxcli.nvme.fabrics.disconnect($item.Adapter, $item.ControllerNumber, $StorageSystemNQN);
                        Write-Host "Diconnecting Controller status: "$result;
                    }
                    catch {
                        Write-Host "Failed to disconnect controller $($_.Exception)"
                    }

                }

                Write-Host "Rescanning NVMe/TCP storage adapter.."
                $RescanResult = Get-VMHostStorage -VMHost $VmHost.Name -RescanAllHba
                Write-Host "Rescanning Completed."
            }

            else {
                Write-Host "No NVMe/TCP controller found on given host " $VmHost.Name
            }
        }

        Write-Host ""
    }
}


<#
    .SYNOPSIS
     This function removes VMFS datastore on a given ESXi Cluster.

     1. vSphere Cluster Name
     2. Datastore Name

    .PARAMETER HostAddress
     vSphere Cluster Name

    .PARAMETER DatastoreName
     Datastore Name


    .EXAMPLE
     Remove-VmfsDatastore -ClusterName "vSphere-cluster-001"  -DatastoreName "datastore-name-01"

    .INPUTS
     vSphere Cluster Name, Datastore name

    .OUTPUTS
     None.
#>

function Remove-VmfsDatastore {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]

    Param
    (

        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [string] $ClusterName,

        [Parameter(
            Mandatory = $true,
            HelpMessage = ' Existing datastore name')]
        [string] $DatastoreName
    )

    Write-Host "Removing datastore $($DatastoreName) accessible to ESXi host(s) in the cluster "  $ClusterName
    $AvailableDatastore = $null

    $ClusterName = $ClusterName.Trim()

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $AvailableDatastore = Get-Datastore -Name $DatastoreName -ErrorAction ignore
    if ( (-not $AvailableDatastore)  -or ($AvailableDatastore.State -eq "Unavailable")) {
        throw "Datastore $DatastoreName does not exist Or datastore is in Unvailable state."

    }

    $VMs = Get-VM -Datastore $DatastoreName -ErrorAction ignore
    if ($VMs){
        throw "Datastore $DatastoreName is hosting worker virtual machines and can't be deleted"

    }

    $VmHosts = $Cluster | Get-VMHost -State "Connected"
    $RelatedVmHosts = Get-VMHost -Datastore $DatastoreName -State "Connected"

    $DeleteDs = $true

    foreach ($RltdHost in $RelatedVmHosts){
            if($RltdHost.Parent.Name.Trim() -ne $ClusterName){
                $DeleteDs = $false
                break;
            }
    }

   $IsDatastoreRemoved=$false
   if($DeleteDs){
    try {
        Write-Host "Removing datastore using esxi host $($RelatedVmHosts[0].Name) as reference host."
        Remove-Datastore -VMHost $RelatedVmHosts[0].Name -Datastore $DatastoreName -Confirm:$false
        $AvailableDatastore = $null
        $AvailableDatastore = Get-Datastore -Name $DatastoreName -ErrorAction ignore
        if (-not $AvailableDatastore) {
            Write-Host "Datastore removed. "
            $IsDatastoreRemoved=$true
        }
    }
    catch {
        throw "Failed to remove datasore $($DatastoreName)."
    }
  }

 else{

     Write-Host "Datastore is shared, Unmounting datastore from each host under the cluster $($ClusterName)"
     $VmfsUuid = $AvailableDatastore.ExtensionData.info.Vmfs.uuid
     foreach ($VmHost in $VMHosts) {

        try {
            $HostStorageSystem = Get-View $VmHost.Extensiondata.ConfigManager.StorageSystem
            $HostStorageSystem.UnmountVmfsVolume($VmfsUuid) | Out-Null

        }
        catch {
          Write-Host "Failed to unmount datastore from host "$VmHost.Name
        }
     }
  }

  Write-Host "Rescanning datastore "
  $RescanResult = Get-VMHostStorage -VMHost $RelatedVmHosts[0].Name -RescanAllHba

  if (-not($IsDatastoreRemoved)){
        Write-Host "Datastore was found but did't remove, instead unmounted from ESXi hosts under the given cluster."
   }

   Write-Host " " ;

}


<#
   .DESCRIPTION
    Mount a VMFS datastore to all ESXi host(s) under the given vSphere cluster.

   .PARAMETER ClusterName
    vSphere Cluster name

   .PARAMETER DatastoreName
    Datastore name

   .EXAMPLE
    Mount-VmfsDatastore -ClusterName "myCluster" -DatastoreName "myDatastore"

   .INPUTS
    vCenter vSphere cluster name and datastore name.

   .OUTPUTS
    None.
 #>
function Mount-VmfsDatastore {
  [CmdletBinding()]
  [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
  Param (
         [ Parameter(
            Mandatory=$true,
            HelpMessage = 'vSphere Cluster name in vCenter')]
            [ValidateNotNull()]
            [String]
            $ClusterName,
            [Parameter(
                Mandatory=$true,
                HelpMessage = 'Name of VMFS datastore to be mounted on host(s) in vCenter')]
            [ValidateNotNull()]
            [String]
            $DatastoreName
        )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $ClusterName does not exist."
    }

    $Datastore = Get-Datastore -Name $DatastoreName -ErrorAction Ignore
    if (-not $Datastore) {
                throw "Datastore $DatastoreName does not exist."
    }

    if ("VMFS" -ne $Datastore.Type) {
         throw "Datastore $DatastoreName is of type $($Datastore.Type). This cmdlet can only process VMFS datastores."
    }

    Write-Host "Mounting datastore $DatastoreName to all host(s) in the given vSphere cluster."

    $HostViewDiskName = $Datastore.ExtensionData.Info.vmfs.extent[0].Diskname
    if ($null -eq $HostViewDiskName){
         throw "Could't find backing device for the datastore $($DatastoreName)"
    }

    $VmHosts = $Cluster | Get-VMHost

    foreach ($VmHost in $VmHosts){

      $Devices = $VmHost.ExtensionData.config.StorageDevice.ScsiLun | Where-Object { $_.DevicePath -like "*$($HostViewDiskName)*" }
      if ($null -eq $Devices){
          Write-Host "Could't find device on ESXi host $($VmHost.Name) for device UUID  $($HostViewDiskName), skipping to mount datastore"
         continue
      }

      $HostView = Get-View $VmHost
      $StorageSys = Get-View $HostView.ConfigManager.StorageSystem
      Write-Host "Mounting VMFS Datastore $($Datastore.Name) on host $($HostView.Name)"
      try{
          $StorageSys.MountVmfsVolume($Datastore.ExtensionData.Info.vmfs.uuid);
      }
      catch{
           Write-Error "Failed to VMFS Datastore $($Datastore.Name) on host $($HostView.Name)"
      }

      Write-Host "Datastore $($Datastore.Name) mounted successfully on host, rescanning now.. $($hostview.Name)."
      $VmHost | Get-VMHostStorage -RescanAllHba -RescanVmfs | Out-Null
    }

  }


<#
    .SYNOPSIS
     This function list all VMFS datastores accessible to host(s) under the given ESXi Cluster.

    .PARAMETER ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Get-VmfsDatastore -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name

    .OUTPUTS
     None.
#>

function Get-VmfsDatastore {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]

    Param
    (
      [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
      [string] $ClusterName

    )

    Write-Host "Collecting all available VMFS datastores accessible to ESXi host(s) in the cluster "  $ClusterName
    Write-Host ""
    $ClusterName = $ClusterName.Trim()

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $VmHosts = $Cluster | Get-VMHost -ErrorAction Ignore
    if (-not $VmHosts) {
        throw "No ESXi host found under $($ClusterName)."
    }


    $Datastores = Get-VMHost -Name $VmHosts | Get-Datastore | Where-Object {$_.Type -match "VMFS"} | Get-Unique

    if ( -not $Datastores) {
        Write-Host "No Datastore found under the given cluster."
        return

    }

    $NamedOutputs = @{}

    foreach ($Datastore in $Datastores){
      $Hosts = Get-VMHost -Datastore $Datastore.Name | Select-Object select -ExpandProperty Name -ErrorAction Ignore
      $VmfsUuid = $Datastore.ExtensionData.info.Vmfs.uuid
      $HostViewDiskName = $Datastore.ExtensionData.Info.vmfs.extent[0].Diskname;
      $NamedOutputs[$Datastore.Name] = "
           {
           Name : $($Datastore.Name),
           Capacity : $($Datastore.CapacityGB),
           FreeSpace : $($Datastore.FreeSpaceGB),
           Type : $($Datastore.Type),
           UUID : $($VmfsUuid),
           Device : $($HostViewDiskName),
           State : $($Datastore.State),
           Hosts : $($Hosts),
           }"
    }

   if($NamedOutputs.Count -gt 0){

      Write-host $NamedOutputs | ConvertTo-Json -Depth 10
   }

   Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global

   Write-Host " "

}


    <#
    .SYNOPSIS
     This function collects all ESXi host(s) along with detailed inventory under a given vSphere Cluster.

    .PARAMETER -ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Get-VmfsHosts -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name

    .OUTPUTS
     NamedOutputs Detailed ESXi host(s) inventory
#>

function Get-VmfsHosts {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName

    )

    Write-Host "Collecting detailed inventory of all ESXi host(s) under vSphere Cluster $($ClusterName), takes seconds .."
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }


    $NamedOutputs = @{}
    $VmHosts = $Cluster | Get-VMHost

    foreach ($VmHost in $VmHosts) {
     $Datastores = $VmHost | Get-Datastore | Where-Object { $_.Type -match "VMFS" } | Select-Object select -ExpandProperty Name
     $NamedOutputs[$VmHost.Name] = "
     {
      Name : $($VmHost.Name),
      Version : $($VmHost.Version),
      ConnectionState : $($VmHost.ConnectionState),
      PowerState : $($VmHost.PowerState),
      State : $($VmHost.State),
      HostNQN : $($VmHost.ExtensionData.Hardware.SystemInfo.QualifiedName.Value),
      Uuid : $($VmHost.ExtensionData.Hardware.SystemInfo.Uuid),
      Datastores: $($Datastores),
      Extension : $($VmHost.ExtensionData.config.StorageDevice.NvmeTopology | ConvertTo-JSON -Depth 2)
     }"
   }


   Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
   Write-Host ""

}


<#
    .SYNOPSIS
     This function collects Storage Adapter info for ESXi host(s) in a given vSphere Cluster.

    .PARAMETER -ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Get-StorageAdapters -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name

    .OUTPUTS
     NamedOutputs detailed storage adapters inventory
#>

function Get-StorageAdapters {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName

    )

    Write-Host "Collecting storage adapters inventory of all ESXi host(s) under vSphere Cluster $($ClusterName)"
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $NamedOutputs = @{}
    $VmHosts = $Cluster | Get-VMHost
    foreach ($VmHost in $VmHosts) {
        $Adapters = $Null
        try {
            $Adapters = Get-VMHostHba -VMHost $VmHost.Name -ErrorAction Ignore
        }
        catch {
            Write-Error "Failed to collect VMKernel Info on host $($VmHost.Name), continue collecting about rest of the host(s)."
            continue
        }

        $StorageAdapters = New-Object System.Collections.ArrayList
        if (-not $Adapters) {
            continue
        }

        foreach ($Adapter in $Adapters) {
            $St = $Adapter | Select-Object -Property * -ExcludeProperty "VMHost"
            $StorageAdapters.Add($St) | Out-Null

        }
        $NamedOutputs.Add($VmHost.Name.Trim(), ($StorageAdapters | ConvertTo-Json -Depth 2))
    }


    Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
    Write-Host ""

}

<#
    .SYNOPSIS
     This function collects storage vmkernel adapter for ESXi host(s) in a given vSphere Cluster.

    .PARAMETER -ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Get-VmKernelAdapters -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name

    .OUTPUTS
     NamedOutputs detailed storage vmkernel adapters inventory.
#>

function Get-VmKernelAdapters {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName

    )

    Write-Host "Collecting VMKernel adapters inventory of all ESXi host(s) under vSphere Cluster $($ClusterName)"
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }


    $NamedOutputs = @{}
    $VmHosts = $Cluster | Get-VMHost

    foreach ($VmHost in $VmHosts) {
        $KernelAdapters = $null
        try {
            $KernelAdapters = Get-VMHostNetworkAdapter -VMHost $VmHost.Name -VMKernel
        }
        catch {
            Write-Error "Failed to collect VMKernel info on host $($VmHost.Name), continue collecting from other host(s)."
            continue
        }

        $VmKernelAdapters = New-Object System.Collections.ArrayList
        if (-not $KernelAdapters) {
            continue
        }

        foreach ($Adapter in $KernelAdapters) {
            $Vmk = $Adapter | Select-Object -Property * -ExcludeProperty "VMHost"
            $VmKernelAdapters.Add($Vmk) | Out-Null

        }
        $NamedOutputs.Add($VmHost.Name.Trim(), ($VmKernelAdapters | ConvertTo-Json -Depth 2))
    }


    Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
    Write-Host ""

}

<#
    .SYNOPSIS
     This function enables NVMeTCP storage services on given vmkernel adapter for a host.

    .PARAMETER -HostAddress
     ESXi host network address

    .PARAMETER VmKernel
     Storage VMKernel name

    .EXAMPLE
     Set-NVMeTCP -HostAddress "192.168.10.11" -VmKernel "vmk0"

    .INPUTS
     ESXi host network address
     Storage VMKernel name

    .OUTPUTS
     NamedOutputs operation result.
#>

function Set-NVMeTCP {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'ESXi host network address')]
        [String] $HostAddress,
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Existing VMKernel adapter name')]
        [String] $VmKernel

    )

    Write-Host "Enabling NVMeTCP services on given VMKernal adapter for host $($HostAddress)"
    Write-Host " " ;

    $VmHost = Get-VMHost -Name $HostAddress -ErrorAction Ignore
    if (-not $VmHost) {
        throw "ESXi $($HostAddress) does not exist."
    }

    $VmKernel = $VmKernel.Trim()
    $NamedOutputs = @{}

    $KernelAdapters = $null
    try {
        $KernelAdapters = Get-VMHostNetworkAdapter -VMHost $VmHost.Name -VMKernel -Name $VmKernel
    }
    catch {
        Write-Host "Failed to collect VMKernel adapters controller $($_.Exception)"
        throw "Failed to collect VMKernel adapters controller $($_.Exception)"
    }

    if (-not $KernelAdapters -or $KernelAdapters.Count -eq 0) {
        throw "Didn't find VMKernel adapters on host"
    }

    $HostEsxcli = Get-EsxCli -VMHost $VmHost.Name -ErrorAction stop

    $isEnabled = $HostEsxcli.network.ip.interface.tag.add($VmKernel, 'NVMeTCP')

    if ($isEnabled) {
        Get-VMHostStorage -VMHost $HostAddress -RescanAllHba | Out-Null
        $NamedOutputs.Add($VmKernel, "NVMe/TCP Service enabled successfully.")
    }
    else {
        $NamedOutputs.Add($VmKernel, "Failed to enable NVMe/TCP Service on host.")
    }

    if ($NamedOutputs.Count -gt 0) {
        Write-host $NamedOutputs | ConvertTo-Json -Depth 10
    }
    Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
    Write-Host ""

}


<#
    .SYNOPSIS
     This function creates new NVMe/TCP storage adapter on given ESXi host.

    .PARAMETER -HostAddress
     ESXi host network address

    .PARAMETER VmKernel
     Storage Nic name

    .EXAMPLE
     New-NVMeTCPAdapter -HostAddress "192.168.10.11" -VmNic "vmnic0"

    .INPUTS
     ESXi host network address
     Storage NIC name

    .OUTPUTS
     NamedOutputs operation result.
#>

function New-NVMeTCPAdapter {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'ESXi host network address')]
        [String] $HostAddress,
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'Existing Physical NIC  name')]
        [String] $VmNic

    )

    Write-Host "Creating a new NVMe/TCP adapter using storage nic on host $($HostAddress)"
    Write-Host " " ;

    $VmHost = Get-VMHost -Name $HostAddress -ErrorAction Ignore
    if (-not $VmHost) {
        throw "ESXi $($HostAddress) does not exist."
    }

    $VmNic = $VmNic.Trim()
    $NamedOutputs = @{}

    $Nics = $null
    try {
        $Nics = Get-VMHostNetworkAdapter -VMHost $VmHost.Name -Physical -Name $VmNic
    }
    catch {
        Write-Host "Failed to collect physical inventory Nic  $($_.Exception)"
        throw "Failed to collect physical inventory Nic  $($_.Exception)"
    }

    if (-not $Nics -or $Nics.Count -eq 0) {
        throw "Didn't find Nic adapters on host"
    }

    $HostEsxcli = Get-EsxCli -VMHost $VmHost.Name -ErrorAction stop
    $IsCreated = $HostEsxcli.nvme.fabrics.enable($VmNic, 'TCP');
    if ($IsCreated) {
        $NamedOutputs.Add($VmNic, "NVMe/TCP adapter created successfully.")
        Get-VMHostStorage -VMHost $HostAddress -RescanAllHba | Out-Null
    }
    else {
        $NamedOutputs.Add($VmNic, "Failed to create NVMe/TCP adapter.")
    }

    if ($NamedOutputs.Count -gt 0) {
        Write-host $NamedOutputs | ConvertTo-Json -Depth 10
    }

    Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
    Write-Host ""

}

<#
    .SYNOPSIS
     This function collects all VMs on the provided datastore and creates snapshot of each virtual machine.

    .PARAMETER -ClusterName
     vSphere Cluster Name

    .PARAMETER -DatastoreName
     Datastore name


    .EXAMPLE
     New-VmfsVmSnapshot -ClusterName "vSphere-cluster-001" -DatastoreName "myDatastore"

    .INPUTS
     vSphere cluster name, datastore name

    .OUTPUTS
     None.
#>

function New-VmfsVmSnapshot {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]

    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName,
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'datastore name')]
        [String] $datastoreName

    )

    Write-Host "Creating snapshot of all VMs on the given datastore accessible to cluster $($ClusterName)"
    Write-Host " " ;

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $Datastore = Get-Datastore -Name $DatastoreName -RelatedObject $Cluster -ErrorAction Ignore
    if (-not $Datastore) {
        throw "Datastore $DatastoreName does not exist."
    }


    $NamedOutputs = @{}
    $Vms = Get-VM -Datastore $Datastore

    foreach ($Vm in $Vms) {
        $timeStamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "-" }
        $SnapshotName = $Vm.Name + "-" + $timeStamp

        if (!$Vm.ExtensionData) {
            Write-Host "Skipping to create snapshot of virtual machine $($Vm.Name), becuase of unavailable configuration."
            continue
        }

        if (($Vm.ExtensionData.OverallStatus -ne "green") -or ($Vm.ExtensionData.guestHeartbeatStatus -ne "green")) {
            Write-Host "Skipping to create snapshot of virtual machine $($Vm.Name) becuase health status is not OK."
            continue
        }

        try {
            $Snapshot = New-Snapshot -VM $Vm -Quiesce -Name $SnapshotName -ErrorAction Ignore
            Write-Host "Snapshot $($Snapshot.Name) created."
        }
        catch {
            Write-Host "Failed to creat snapshot for $($Vm.Name) $($_.Exception)"
            throw "Failed to creat snapshot for $($Vm.Name) $($_.Exception)"
        }
    }

    Set-Variable -Name NamedOutputs -Value $NamedOutputs -Scope Global
    Write-Host ""

}

<#
    .SYNOPSIS
     This function repairs HA configuration on all hosts in a given vSphere Cluster.

    .PARAMETER ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Repair-HAConfiguration -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name
#>
function Repair-HAConfiguration {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $VMHosts = $null
    try {
        $VMHosts = Get-Cluster $ClusterName | Get-VMHost
    }
    catch {
        Write-Host "Failed to collect cluster hosts $($_.Exception)"
        throw "Failed to collect cluster hosts $($_.Exception)"
    }

    $Success = $true
    foreach ($VMHost in $VMHosts) {
        $HostAddress = $VMHost.Name
        Write-Host "Repairing HA configuration on host $HostAddress"
        try {
            $VMHost.ExtensionData.ReconfigureHostForDAS()
        } catch {
            Write-Error "Failed to repair HA configuration on host $HostAddress"
            $Success = $false
        }
    }
    if (-not $Success) {
        throw "Failed to repair HA configuration on one or more hosts"
    }
}

<#
    .SYNOPSIS
     This function clears disconnected iSCSI targets on all hosts in a given vSphere Cluster.

    .PARAMETER ClusterName
     vSphere Cluster Name

    .PARAMETER VMHostName
     ESXi host name. If not specified, all hosts in the cluster will be used.

    .EXAMPLE
     Clear-DisconnectedIscsiTargets -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name
#>
function Clear-DisconnectedIscsiTargets {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName,

        [Parameter(
            Mandatory = $false,
            HelpMessage = 'VMHost Name')]
        [String] $VMHostName
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $VMHosts = $null
    try {
        if ($VMHostName) {
            $VMHosts = $Cluster | Get-VMHost -Name $VMHostName
        } else {
            $VMHosts = $Cluster | Get-VMHost
        }
    }
    catch {
        throw "Failed to collect cluster hosts $($_.Exception)"
    }

    if (-not $VMHosts) {
        throw "No matching hosts found in cluster $ClusterName"
    }

    foreach ($VMHost in $VMHosts) {
        $IscsiTargetRemoved = $false
        $HostAddress = $VMHost.Name
        Write-Host "Clearing disconnected iSCSI targets on host $HostAddress"

        $EsxCli = Get-EsxCli -VMHost $VMHost.Name -V2

        $DisconnectedSessions = $Esxcli.iscsi.session.connection.list.Invoke() | Where-Object { $_.State.Trim() -ne "logged_in" }
        foreach ($session in $DisconnectedSessions) {
            try {
                Write-Host "Clearing disconnected iSCSI target $($session.ConnectionAddress) on host $HostAddress"
                $targets = Get-IScsiHbaTarget | Where-Object { $_.Address -eq $session.ConnectionAddress }
                $targets | Remove-IScsiHbaTarget -Confirm:$false
                $IscsiTargetRemoved = $true
            }
            catch {
                Write-Error "Failed to clear disconnected iSCSI targets on host $HostAddress"
            }
        }
        if ($IscsiTargetRemoved) {
            Write-Host "Rescanning storage on host $HostAddress"
            $VMHost | Get-VMHostStorage -RescanAllHba -RescanVmfs
        }
    }
}
<#
    .SYNOPSIS
     This function checks each cluster host connectivity to vmkernel interface

    .PARAMETER ClusterName
     vSphere Cluster Name

    .EXAMPLE
     Test-VMKernelConnectivity -ClusterName "vSphere-cluster-001"

    .INPUTS
     vSphere Cluster Name, Storage VMKernel name

#>

function Test-VMKernelConnectivity {
    [CmdletBinding()]
    [AVSAttribute(10, UpdatesSDDC = $false, AutomationOnly = $true)]
    Param
    (
        [Parameter(
            Mandatory = $true,
            HelpMessage = 'vSphere Cluster Name')]
        [String] $ClusterName
    )

    $Cluster = Get-Cluster -Name $ClusterName -ErrorAction Ignore
    if (-not $Cluster) {
        throw "Cluster $($ClusterName) does not exist."
    }

    $VMHosts = $null
    try {
        $VMHosts = Get-Cluster $ClusterName | Get-VMHost
    }
    catch {
        Write-Host "Failed to collect cluster hosts $($_.Exception)"
        throw "Failed to collect cluster hosts $($_.Exception)"
    }

    $Success = $true
    foreach ($VMHost in $VMHosts) {
        $HostAddress = $VMHost.Name
        $NetworkInterfaces =  Get-VMHostNetworkAdapter -VMHost $VMHost | Where-Object {$_.Ip}
        foreach ($Nic in $NetworkInterfaces) {
            Write-Host "Checking connectivity to vmkernel interface $($Nic.Name) with address $($Nic.IP) on host $HostAddress"
            $esxcli = Get-EsxCli -VMHost $VMHost.Name -V2
            $params = $esxcli.network.diag.ping.CreateArgs()
            $params.host = $Nic.IP
            $result = $esxcli.network.diag.ping.Invoke($params)
            if ($result.Summary.Received -gt 0) {
                Write-Host "Ping to vmkernel interface $($VmKernel) on host $HostAddress is successful"
            }
            else {
                Write-Error "Ping to vmkernel interface $($VmKernel) on host $HostAddress failed"
                $Success = $false
            }
        }
    }
    if (-not $Success) {
        throw "Ping to vmkernel interface failed on one or more hosts"
    }
}

param(  
      [Parameter(Mandatory=$true, 
      HelpMessage="Name your VM")]    
      $vmname,
      [Parameter(Mandatory=$false, 
      HelpMessage="Select your TCBSD image")]
      $tcbsdimagefile="TCBSD-x64-14-126815.iso",
      [Parameter(Mandatory=$false, 
      HelpMessage="Where is your VirtualBox installation?")]    
      $virtualBoxPath = 'C:\Program Files\Oracle\VirtualBox',
      [Parameter(Mandatory=$false, 
      HelpMessage="Administrator password")]    
      $adminPW = "1"
)

function Convert-To-ScanCode {
    param (
        [Parameter(Mandatory=$true)]  
        [string]
        $stringToConvert
    )
    if (-not ([System.Management.Automation.PSTypeName]'User32').Type) {    
        Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class User32 {
        [DllImport("user32.dll")]
        public static extern short VkKeyScan(char ch);
        [DllImport("user32.dll")]
        public static extern uint MapVirtualKey(uint uCode, uint uMapType);
    }
"@
    }
    $scanCodes = @()
    foreach ($char in $stringToConvert.ToCharArray()) {

        $virtualKeyCode = [User32]::VkKeyScan([char]::ToLower($char))
        $shift = [char]::IsUpper($char) -or ($virtualKeyCode -shr 8 -band 0x1)? $true : $false
        $alt = $virtualKeyCode -shr 8 -band 0x4 ? $true : $false
        $keyCode = [User32]::MapVirtualKey($virtualKeyCode -band 0xff, 0)
        
        if ($shift) {
            $scanCodes += "2A" 
        } elseif ($alt) {
            $scanCodes += "E0"
            $scanCodes += "38"
        }
        $scanCodes += $keyCode.ToString("X2")
        $scanCodes += ($keyCode -bor 0x80).ToString("X2")   # key released

        if ($shift) {
            $scanCodes += "AA"
        } elseif ($alt) {
            $scanCodes += "E0"
            $scanCodes += "B8"
        }
    }

    return $scanCodes
}

function Install-Unattended {
    param (
        [string] $adminPW
    )
    Write-Host "Waiting for VM to boot ..."
    Start-Sleep 30

    # https://docs.oracle.com/en/virtualization/virtualbox/6.0/user/vboxmanage-controlvm.html
    # Insert keystrokes, to simulate keyboard inputs
    # key-codes pressed / released (+ 0x80)
    # key-codes 1c = Enter, 9c = Release Enter
    # 1. Welcome screen (TC/BSD Install already selected) --> 1 ENTER 
    Write-Host "Selecting option 1"
    .\VBoxManage controlvm $vmname keyboardputscancode 1c 9c
    # 2. Disk Selection --> 1 ENTER
    Write-Host "Selecting option 1"
    .\VBoxManage controlvm $vmname keyboardputscancode 1c 9c
    # 3. Warning confirm installation --> CURSOR_LEFT ENTER
    Write-Host "Selecting confirming installation"
    .\VBoxManage controlvm $vmname keyboardputscancode 4b cb 1c 9c
    # 4. Enter password for Administrator Accout --> 1 ENTER
    Write-Host "Entering password"
    $pwAsKeyCodes = Convert-To-ScanCode $adminPW
    .\VBoxManage controlvm $vmname keyboardputscancode $pwAsKeyCodes 1c 9c
    # 5. Re-enter password for Administrator Accout --> 1 ENTER
    Write-Host "Re-entering password"
    .\VBoxManage controlvm $vmname keyboardputscancode $pwAsKeyCodes 1c 9c
    # 6. Wait until installed, confirm with ENTER
    Write-Host "Waiting until system has been installed"
    Start-Sleep 35

    Write-Host "Selecting confirming installation finished"
    .\VBoxManage controlvm $vmname keyboardputscancode 1c 9c
    # 7. Reboot
    Write-Host "Selecting reboot"
    .\VBoxManage controlvm $vmname keyboardputscancode 06 86 1c 9c
}

.\Create-TcBsdVM.ps1 $vmname $tcbsdimagefile $virtualBoxPath

$workingDirectory=pwd
cd $virtualBoxPath
Install-Unattended $adminPW
cd $workingDirectory
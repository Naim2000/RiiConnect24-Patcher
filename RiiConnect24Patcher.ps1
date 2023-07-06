$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$version = 'v1.0.0'
$patcherInfo = `
	"RiiConnect24Patcher for Windows [PowerShell] $version
by Naim2000"

$patcherState = @{
	console      = [ConsoleType]::Wii
	region       = [ConsoleRegion]::USA
	patch        = @($true, $true, $false, $false, $false, $true)
	patched      = @($false, $false, $false, $false, $false, $false)
	SD           = $false
	SDPath       = ''
	outPath      = ''
	workPath     = ''
	patchMessage = ''
}

$patchOptions = @(
	'System Patches',
	'Forecast Channel & News Channel'
	'Check Mii Out/Mii Contest Channel'
	'Everybody Votes Channel'
	'Nintendo Channel'
	'Patcher apps'
)

enum ConsoleRegion {
	USA
	EUR
	JPN
}

enum ConsoleType {
	Wii
	vWii
	Dolphin
}

function Set-Cursor {
	[CmdletBinding()]param(
		[int]$X = 0,
		[int]$Y = 0,
		[switch]$Shift
	)
	$newPos = $Host.UI.RawUI.CursorPosition
	if ($Shift) { $newPos.X += $X; $newPos.Y += $Y }
	else { $newPos.X = $X; $newPos.Y = $Y }
	$Host.UI.RawUI.CursorPosition = $newPos
}

function Read-AnyKey {
	[CmdletBinding()]param (
		[string]$verb = 'continue'
	)
	Write-Host "Press any key to ${verb}..."
	$Host.UI.RawUI.ReadKey() >$null
}

function Read-Char {
	[CmdletBinding()]param ()
	do {
		$char = $Host.UI.RawUI.ReadKey().Character
	} until (
		$char
	)
	return $char
}

function fromHexString {
	[CmdletBinding()]param (
		[Parameter(Mandatory = $true)][string]$str 
	)
	if ($str.Length % 2) { 
		$PSCmdlet.ThrowTerminatingError( [System.Management.Automation.ErrorRecord]::new(
				[System.ArgumentException]::new('String length must be even.', 'str'),
				'InvalidString',
				[System.Management.Automation.ErrorCategory]::InvalidArgument,
				$str)
		) 
	}
	return ([char[]][int[]]((0..(($str.Length - 2) / 2)) | ForEach-Object { "0x" + $str.Substring($_ * 2, 2) })) -join ''
}

function Confirm-Path {
	[CmdletBinding()]param(
		[Parameter(Mandatory = $true)][string]$path,
		[switch]$empty
	)
	if (Test-Path $path) {
		if ($empty) { Remove-Item "$path/*" -Recurse -Force }
		return Resolve-Path $path
	}
 else {
		return New-Item -ItemType Directory -Path $path
	}
}

function Title([string]$section, [System.ConsoleColor]$color = 'Gray') {
	Clear-Host
	Write-Host "$patcherInfo`n"
	Write-Host ('    ' + $section + (' ' * ($Host.UI.RawUI.WindowSize.Width - (4 + $section.Length)))) -BackgroundColor $color -ForegroundColor Black
	Write-Host $null
}

<#
function Change_Title([string]$section) {
	Set-Cursor 4 4
	Write-Host $section -BackgroundColor Gray -ForegroundColor Black -NoNewline
}
#>

function Subtitle([string]$title, [string]$message) {
	Write-Host ('====' + $title + ('=' * ($Host.UI.RawUI.WindowSize.Width - (4 + $title.Length))))
	Write-Host $message
	Write-Host ('=' * $Host.UI.RawUI.WindowSize.Width)
	Write-Host $null
}

function RC24get([string]$file, [string]$outFile) {
	Invoke-WebRequest -Uri "https://patcher.rc24.xyz/update/RiiConnect24-Patcher/v1/$file" -OutFile $outFile -UserAgent "RiiConnect24 Patcher [Powershell] $version"
}

function SketchMastergetcetk ([string]$ch, [string]$id) {
	Invoke-WebRequest -Uri "https://patcher.rc24.xyz/update/RiiConnect24-Patcher_Unix/v1/$ch/$($patcherState.region)/cetk" -OutFile "$id/cetk" -UserAgent "RiiConnect24 Patcher [Powershell] $version"
}

function OSCDL([string]$app) {
	Invoke-WebRequest -Uri "https://hbb1.oscwii.org/hbb/$app/$app.zip" -OutFile "$app.zip" -UserAgent "RiiConnect24 Patcher [Powershell] $version"
	Expand-Archive -Path "$app.zip" -DestinationPath $patcherState.outPath -Force
}

function Patch_IOS([int]$IOS, [int]$rev) {
	$ios_string = "IOS$IOS-64-$rev"
	Push-Location $ios_string
	& $Sharpii nusd -ios $IOS -v $rev -wad -q >$null
	& $Sharpii wad -u "$ios_string.wad" '.' -q >$null
	& $xdelta -d -f -s "00000006.app" "00000006.delta" "00000006_patched.app" >$null
	Move-Item -Force "00000006_patched.app" "00000006.app"
	& $Sharpii wad -p '.' "$($patcherState.outPath)/WAD/IOS$IOS (RiiConnect24).wad" -f -q >$null
	& $Sharpii ios "$($patcherState.outPath)/WAD/IOS$IOS (RiiConnect24).wad" -fs -es -np -vp -q >$null
	Pop-Location
}

function Patch_Title([string]$id, [int]$rev, [string[]]$contents, [string]$title) {
	if ($patcherState.console -eq 'vWii') { $title += ' vWii' }

	& $Sharpii nusd -id $id -v $rev -encrypt >$null
	Push-Location "${id}v$rev"
	Move-Item "tmd.$rev" 'tmd' -Force
	& $nusdecrypt >$null
	& $Sharpii wad -u "$(fromHexString $id.Substring(8)).wad" '.' >$null 
	$contents | ForEach-Object {
		& $xdelta -d -f -s "$_.app" "$_.delta" "${_}_patched.app"
		Move-Item -Force "${_}_patched.app" "$_.app"
	}

	& $Sharpii wad -p '.' "$($patcherState.outPath)/WAD/$title ($($patcherState.region)) (RiiConnect24).wad" -f >$null
	Pop-Location
}

function Detect_WiiSD() {
	Title "Detecting SD card..."
	$drives = Get-PSDrive | 
	Where-Object { ($_.Provider.Name -eq "FileSystem") -and !($_.Root -eq $env:SYSTEMDRIVE + '\') }
	for ($c = 0; !$patcherState.SD -and $c -lt $drives.Length; $c++) {
		if (Test-Path "$($drives[$c].Root)apps") {
			$patcherState.SD = $true
			$patcherState.outPath = $drives[$c].Root
		}
	}
}

function Menu_SelectConsoleType() {
 while ($true) {
		Title "Choose your console!"
		Write-Host `
			"Welcome to the RiiConnect24 Patcher!
With this program, you can patch your Wii or Wii U for use with RiiConnect24.

Which console should we patch today?

1. Wii
2. vWii (Wii U)
3. Dolphin Emulator

0. Quit
"

		if ($patcherState.SD) {
			Write-Host 'Your SD card was detected.' -ForegroundColor Green
		}
		else {
			Write-Host 'Could not detect your SD card. Sorry.' -ForegroundColor Red
		} 

		Write-Host "Patch files are saving to: $($patcherState.outPath) `n"
		"4. Reset path `n"
		"5. Try detect SD again `n"
		Write-Host "Choose: " -NoNewline
		switch (Read-Char) {
			'1' {
				$patcherState.console = [ConsoleType]::Wii
				Menu_SelectConsoleRegion
			}
			'2' {
				$patcherState.console = [ConsoleType]::vWii
				Menu_SelectConsoleRegion
			}
			'3' {
				$patcherState.console = [ConsoleType]::Dolphin
				$patcherState.patch[0] = $false
				$patcherState.patch[2] = $true
				$patcherState.patch[3] = $true
				$patcherState.patch[4] = $true
				$patcherState.patch[5] = $false
				$patcherState.outPath = "$($patcherState.workPath)\copyToSD"
				Write-Host "`n`nPatch files will svae to: $($patcherState.outPath)" -ForegroundColor Yellow
				$patcherState.SD = $false
				Start-Sleep 2
				Menu_SelectConsoleRegion
			}
			'4' {
				$patcherState.outPath = "$($patcherState.workPath)\copyToSD"
				$patcherState.SD = $false
			}
			'5' {
				Detect_WiiSD
			}
			'0' { return }
		}
	}
}

function Menu_SelectConsoleRegion() {
 while ($true) {
		Title "Select console region ($([ConsoleType].GetEnumName($patcherState.console)))"
		Write-Host -NoNewline `
			"Now, which region is your console from? `n"`
			"1. USA `n"`
			"2. Europe `n"`
			"3. Japan `n"`
			"`n0. Back`n"`
			"`nChoose: "

		switch (Read-Char) {
			'1' {
				$patcherState.region = [ConsoleRegion]::USA
				Menu_SelectPatchOptions
				return
			}
			'2' {
				$patcherState.region = [ConsoleRegion]::EUR
				Menu_SelectPatchOptions
				return
			}
			'3' {
				$patcherState.region = [ConsoleRegion]::JPN
				Menu_SelectPatchOptions
				return
			}
			'0' { return }
		}

	}
}

function Menu_SelectPatchOptions() {
 while ($true) {
		Title "Patch options ($($patcherState.console), $($patcherState.region))"
		Write-Host "Choose what you would like to patch. `n"`
			"Toggle the options by pressing the digit next to them. `n"`
			"The recommended options for a new RiiConnect24 install are selected by default.`n"
	(1..$patcherState.patch.Length) | ForEach-Object {
			$highlight = [System.ConsoleColor]::Red
			if ($patcherState.patch[$_ - 1]) { $highlight = [System.ConsoleColor]::Green }
			Write-Host "$_. $($patchOptions[$_-1]) " -ForegroundColor $highlight
		}
		Write-Host $null
		Write-Host "7. Start!`n"
		Write-Host "0. Back `n"
		switch ([int][string](Read-Char)) {
			{ $_ -gt 0 -and $_ -le $patcherState.patch.Length } {
				$patcherState.patch[$_ - 1] = !$patcherState.patch[[int][string]$_ - 1]
			}
			7 {
				try { StartPatching }
				catch {
					Pop-Location
					throw $_
				}
				return
			}
			0 { return }
		}
	}
}

function StartPatching() {
	Title "Preparing to patch..."
	$outPath = $patcherState.outPath
	Confirm-Path "$($patcherState.workPath)/Temp" | Push-Location
	if ($patcherState.patch[5]) { Confirm-Path "$outPath/apps" >$null }
	
	if (Test-Path "$outPath/WAD/*") {
		Write-Host "Hey. One quick question. `n"`
			"There's some stuff down here in $(Resolve-Path "$outPath\WAD"). I need to empty it before continuing. `n"`
			"Pro tip: You don't need to keep WAD files on your SD card after installation.`n"
		Start-Sleep 2
		Pause
	}
	Try { Confirm-Path "$outPath/WAD" -empty >$null }
	Catch [System.IO.IOException] {
		Write-Host "$_ << why does this happen ?????"
		Start-Sleep .5
	}
	
	$region = $patcherState.region
	$rgn = @('45', '50', '4a')[$region]
	Menu_UpdatePatchProgress
	Start-Sleep 2
	
	if ($patcherState.patch[0]) {
		if (-not ($patcherState.console -eq 'Dolphin')) {
			if ($patcherState.console -eq 'vWii') {
				RC24get 'IOSPatcher/IOS31_vwii.wad' './IOS31_vWii.wad'
				Move-Item 'IOS31_vWii.wad' "$outPath/WAD/IOS31 (vWii only) (RiiConnect24).wad" >$null
			}
			else {
				Confirm-Path 'IOS31-64-3608' >$null
				Confirm-Path 'IOS80-64-6944' >$null
				RC24get 'IOSPatcher/00000006-31.delta' 'IOS31-64-3608/00000006.delta'
				RC24get 'IOSPatcher/00000006-80.delta' 'IOS80-64-6944/00000006.delta'
				Patch_IOS 31 3608
				Patch_IOS 80 6944
			}
		}

		$patcherState.patched[0] = $true
		Menu_UpdatePatchProgress
	}
	if ($patcherState.patch[1]) {
		# Forecast & News channels
		$idF = "00010002484146$rgn"
		$idN = "00010002484147$rgn"
		Confirm-Path "${idF}v7" >$null
		Confirm-Path "${idN}v7" >$null

		RC24get "NewsChannelPatcher/URL_Patches/$region/00000001_Forecast.delta" "${idF}v7/00000001.delta"
		RC24get "NewsChannelPatcher/URL_Patches/$region/00000001_News.delta"     "${idN}v7/00000001.delta"
				
		Patch_Title $idF 7 @('00000001') 'Forecast Channel'
		Patch_Title $idN 7 @('00000001') 'News Channel'
				
		$patcherState.patched[1] = $true
		Menu_UpdatePatchProgress
	}
	if ($patcherState.patch[2]) {
		# Check Mii Out Channel
		$id = "00010001484150$rgn"
		Confirm-Path "${id}v512" >$null

		RC24get "CMOCPatcher/patch/00000001_$region.delta" "${id}v512/00000001.delta"
		RC24get "CMOCPatcher/patch/00000004_$region.delta" "${id}v512/00000004.delta"
		if ($region -ne "JPN") { SketchMastergetcetk 'CMOC' "${id}v512" }
		Patch_Title $id 512 @('00000001', '00000004') { if ($region -ne 'USA') { 'Mii Contest Channel' } else { 'Check Mii Out Channel' } }

		$patcherState.patched[2] = $true
		Menu_UpdatePatchProgress
	}
	if ($patcherState.patch[3]) {
		# Everybody Votes Channel
		$id = "0001000148414a$rgn"
		Confirm-Path "${id}v512" >$null
		RC24get "EVCPatcher/patch/$region.delta" "${id}v512/00000001.delta"
		if ($region -ne "JPN") { SketchMastergetcetk 'EVC' "${id}v512" }
		Patch_Title "0001000148414a$rgn" 512 @('00000001') 'Everybody Votes Channel'

		$patcherState.patched[3] = $true
		Menu_UpdatePatchProgress
	}
	if ($patcherState.patch[4]) {
		# Nintendo Channel
		$id = "00010001484154$rgn"
		Confirm-Path "${id}v1792" >$null
		RC24get "NCPatcher/patch/$region.delta" "${id}v1792/00000001.delta"
		if ($region -ne "JPN") { SketchMastergetcetk 'NC' "${id}v1792" }
		Patch_Title $id 1792 @('00000001') 'Nintendo Channel'

		$patcherState.patched[4] = $true
		Menu_UpdatePatchProgress
	}
	if ($patcherState.patch[5]) {
		# Patcher apps
		OSCDL 'yawmME'
		OSCDL 'Mail-Patcher'

		$patcherState.patched[5] = $true
		Menu_UpdatePatchProgress
	}
	Start-Sleep 2
	Pop-Location
	Patch_Complete
}

function Menu_UpdatePatchProgress() {
	Title "Patching..." 
	for ($c = 0; $c -lt $patcherState.patch.Length; $c++) {
		if ($patcherState.patch[$c]) {
			$highlight = [System.ConsoleColor]::Red
			if ($patcherState.patched[$c]) { $highlight = [System.ConsoleColor]::Green }
			Write-Host "$($c+1). $($patchOptions[$c]) " -ForegroundColor $highlight
		}
		else {
			Write-Host "$($c+1). $($patchOptions[$c])" -BackgroundColor Red -ForegroundColor Black
		}
	}
	
}

function Patch_Complete() {
	Title "Cleaning up..."
	Remove-Item "$($patcherState.workPath)/Temp" -Recurse -Force
	$patcherState.patched = @($false, $false, $false, $false, $false, $false)
	$patcherState.patch = @($true, $true, $false, $false, $false, $true)
	Title "Patching complete!" -color Green 
	Write-Host "The files have been saved in $($patcherState.outPath)."
	if (!$patcherState.SD -and $patcherState.console -ne 'Dolphin') { Write-Host "Copy the 'apps' and 'WAD' folders to your SD card.`n" }
	Start-Sleep 2
	Read-AnyKey "return to the main menu"
}

Title "Loading..."

$patcherState.workPath = Confirm-Path 'rc24-data'
$patcherState.outPath = Confirm-Path 'rc24-data/copyToSD'
Confirm-Path 'rc24-data/Temp' >$null
Confirm-Path 'rc24-data/tools' >$null

@(
	@('EVCPatcher/pack/Sharpii.exe', "rc24-data/tools/Sharpii.exe"),
	@('EVCPatcher/pack/libWiiSharp.dll', "rc24-data/tools/libWiiSharp.dll"),
	@('EVCPatcher/patch/xdelta3.exe', "rc24-data/tools/xdelta3.exe"),
	@('EVCPatcher/NUS_Downloader_Decrypt.exe', "rc24-data/tools/nusdecrypt.exe")
) | ForEach-Object {
	if (-not (Test-Path $_[1])) {
		RC24Get $_[0] $_[1]
	}
}
$Sharpii = resolve-path 'rc24-data/tools/Sharpii.exe'
$xdelta = resolve-path 'rc24-data/tools/xdelta3.exe'
$nusdecrypt = resolve-path 'rc24-data/tools/nusdecrypt.exe'

Detect_WiiSD
Try { Menu_SelectConsoleType }
Catch [System.Net.WebException] {
	Write-Host -BackgroundColor Yellow -ForegroundColor Black `
"The below exception is from:
$($_.Exception.Response.ResponseURI)"
	throw $_
}
<#
	.SYNOPSIS
		Append to the logfile

	.DESCRIPTION
		Append given text to the logfile 

	.PARAMETER InputFile	
#>
[CmdletBinding(DefaultParameterSetName="Help")]
Param(
    [Parameter(Mandatory=$true, Position=0, ParameterSetName="Command")]	
	[string]
	[ValidateSet("open","close")]
	$Command,

	[Parameter(Mandatory=$true, Position=1, ParameterSetName="Command")]
    [Parameter(Mandatory=$true, Position=0, ParameterSetName="Log")]
    [string]
	$Message,

	[Parameter(Position=0, ParameterSetName="Help")]
    [switch]
    $Help
)

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDirectory 'config.json'
$config = gc $configFile | ConvertFrom-Json

$logfileName = $config.logfile

if(($PSCmdlet.ParameterSetName -eq 'Help')) {
	Get-Help $MyInvocation.MyCommand.Definition -Detailed
	Exit
}

if($PSBoundParameters['Debug']){
	$DebugPreference = 'Continue'
}

switch ($PSCmdlet.ParameterSetName) {
	'Commmand' {
		switch ($Command) {
			open { 
				

			}
			Default { Write-Error "af1 not implemented: $($Command)" }
		}
	}

	'Log' {
		"$(date -f 'ddd, yyyy-MM-dd HH:mm:ss'): $Message" >> $Logfile
	}

	default { Write-Error "eea not implemented: $($PSCmdlet.ParameterSetName)" }
}

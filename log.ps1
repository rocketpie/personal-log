<#
	.SYNOPSIS
		Append to the logfile

	.DESCRIPTION
		Append given text to the logfile 

	.PARAMETER InputFile	
#>
[CmdletBinding(DefaultParameterSetName = "Help")]
Param(	
    [Parameter(Position = 0, ParameterSetName = "Help")]
    [switch]
    $Help,
	
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Open")]	
    [switch]
    $Open,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Note")]	
    [int]
    $Note,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Close")]	
    [int]
    $Close,

    # list all tickets
    [Parameter(Mandatory = $true, ParameterSetName = "list")]	
    [string]
    [ValidateSet("all", "open", "closed")]
    $List,

    # either the entry, or -open: ticket name or -close: ticket resolution or -note: note obvously.
	[Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Open")]
	[Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Note")]
    [Parameter(Mandatory = $true, Position = 1, ParameterSetName = "Close")]
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Log")]
    [string]
    $Message
)

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDirectory 'log.config.json'
$config = Get-Content $configFile | ConvertFrom-Json

$logfileName = $config.logfile

if (($PSCmdlet.ParameterSetName -eq 'Help')) {
    Get-Help $MyInvocation.MyCommand.Definition -Detailed
    Exit
}

if ($PSBoundParameters['Debug']) {
    $DebugPreference = 'Continue'
}

function GetTicketList($logfileName) {
    Get-Content $logfileName | Where-Object { $_.StartsWith('OPEN') -or $_.StartsWith('NOTE') -or $_.StartsWith('CLOSE') } | ForEach-Object { $_.SubString($_.IndexOf(' ') + 1) | ConvertFrom-Json } | ForEach-Object {
        $_.id = [int]$_.id
        if ($_.opened) { $_.opened = [datetime]::Parse($_.opened) }
        if ($_.closed) { $_.closed = [datetime]::Parse($_.closed) }
        $_
    }
}

function CollapseTickets($ticketList) {    
    $ticketList | Group-Object -Property id | ForEach-Object {
		Write-Debug "ticket $($_.name)"

        # list distinct 
        $propertynames = $_.group | ForEach-Object { $_ | Get-Member -MemberType NoteProperty } | ForEach-Object { $_.Name } | Sort-Object -Unique
		Write-Debug ($propertynames -join ',')

        # join all objects properties values
        $allproperties = @{ } 		
        $_.group | ForEach-Object { $item = $_; $propertynames | ForEach-Object { if($item.$_) { Write-Debug $item.$_;  $allproperties[$_] = $item.$_ } } } 

		Write-Debug (($allproperties.GetEnumerator() | %{ "$($_.key)=$($_.value)"}) -join ',')

        New-Object psobject -Property $allproperties		
    } 
}

$date = (Get-Date -f 'ddd, yyyy-MM-dd HH:mm:ss')
$ticketList = GetTicketList($logfileName)

Write-Debug "parameter set name: $($PSCmdlet.ParameterSetName)"
switch ($PSCmdlet.ParameterSetName) {
    'Open' {
        $nextTicketId = 1 
        if ($ticketList.length -ge 1) {
            $nextTicketId = ($ticketList | ForEach-Object { $_.id } | Sort-Object -Descending)[0] + 1
        }
        
        "OPEN { 'id':'$nextTicketId', 'opened':'$date', 'name':'$Message' }" >> $logfileName
    }

    'Note' {
        "NOTE { 'id':'$($Note)', 'note':'$Message' }" >> $logfileName
    }

    'Close' {
        "CLOSE { 'id':'$($Close)', 'closed':'$date', 'resolution':'$Message' }" >> $logfileName
    }

    'List' {
        switch ($List) {
            'all' {
                CollapseTickets $ticketList
            }

            'open' {
                CollapseTickets $ticketList | Where-Object { -not $_.closed }
            }

            'closed' {
                CollapseTickets $ticketList | Where-Object { $_.closed }
            }
			
            default { Write-Error "af1 not implemented: -List $($List)" }
        }
    }

    'Log' {
        "$($date): $Message" >> $logfileName
    }

    default { Write-Error "eea not implemented: $($PSCmdlet.ParameterSetName)" }
}
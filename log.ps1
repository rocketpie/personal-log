<#
	.SYNOPSIS
		Append to the logfile

	.DESCRIPTION    
        Append given text to the logfile 
        
    .EXAMPLE
        log 'adding some log message'

    .EXAMPLE
        log -open 'open a new ticket'

    .EXAMPLE 
        log -close 5 
        ----
        closes ticket 5

    .EXAMPLE 
        log -note 5 'add a note to a ticket'

#>
[CmdletBinding(DefaultParameterSetName = "View")]
Param(	
    [Parameter(Position = 0, ParameterSetName = "View")]
    [int]
    $View = 30,
	
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Open")]	
    [switch]
    $Open,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Note")]	
    [int]
    $Note,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Close")]	
    [int]
    $Close,

    # list tickets
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
        
        # join all objects properties values
        $allproperties = @{ } 		
        $_.group | ForEach-Object { $item = $_; $propertynames | ForEach-Object { if ($item.$_) { $allproperties[$_] = $item.$_ } } } 
        
        Write-Debug (($allproperties.GetEnumerator() | % { "$($_.key)=$($_.value)" }) -join ',')
        
        $result = New-Object psobject -Property $allproperties		
        if ($result.closed) {
            $open = $result.closed - $result.opened
            if ($open.TotalDays -lt 1) {
                $open = "$([int]$open.TotalHours)h" 
            }
            else {
                $open = "$([int]$open.TotalDays)d"
            }
            $result | Add-Member -MemberType NoteProperty -Name 'open' -Value $open
        }

        $result
    } 
}

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDirectory 'log.ps1.config'
$config = Get-Content $configFile | ConvertFrom-Json

$logfileName = $config.logfile
$date = (Get-Date -f 'ddd, yyyy-MM-dd HH:mm:ss')
$ticketList = GetTicketList($logfileName)

Write-Debug "parameter set name: $($PSCmdlet.ParameterSetName)"
switch ($PSCmdlet.ParameterSetName) {
    'View' {
        "log [-View] [20]                       | [this view]: help, log, tickets"
        "log -Open <Ticket Description>         | open a new ticket, providing a description"
        "log -Note|Close <Ticket Id> <Comment>  | add a note or close a ticket, providing a comment"         

        "`nlatest $View entries:"
        gc $logfileName -Tail $View
        "`nopen tickets:"
        CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', 'name', 'note', 'opened'
    }

    'Open' {
        $nextTicketId = 1 
        if ($ticketList.length -ge 1) {
            $nextTicketId = ($ticketList | ForEach-Object { $_.id } | Sort-Object -Descending)[0] + 1
        }
        
        "OPEN { 'id':'$nextTicketId', 'opened':'$date', 'name':'$Message', 'note':null, 'closed':null, 'resolution':null }" >> $logfileName
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
                CollapseTickets $ticketList | Format-Table -Property 'id', 'name', 'note', 'resolution', 'opened', 'closed', 'open'
            }

            'open' {
                CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', 'name', 'note', 'opened'
            }

            'closed' {
                CollapseTickets $ticketList | Where-Object { $_.closed } | Format-Table -Property 'id', 'name', 'note', 'resolution', 'opened', 'closed', 'open'
            }
			
            default { Write-Error "af1 not implemented: -List $($List)" }
        }
    }

    'Log' {
        "$($date): $Message" >> $logfileName
    }

    default { Write-Error "eea not implemented: $($PSCmdlet.ParameterSetName)" }
}
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
[CmdletBinding(DefaultParameterSetName = "Tail")]
Param(	
    [Parameter(Position = 0, ParameterSetName = "Tail")]
    [int]
    $Tail = 30,
	
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Open")]	
    [switch]
    $Open,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Note")]	
    [int]
    $Note,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "View")]	
    [int]
    $View,

    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Close")]	
    [int]
    $Close,

    # list tickets
    [Parameter(Mandatory = $true, ParameterSetName = "Filter")]	
    [string]
    [ValidateSet("all", "open", "closed")]
    $Filter,

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

function isTicket($line) {
    $line.StartsWith('OPEN') -or $line.StartsWith('NOTE') -or $line.StartsWith('CLOSE') 
}

# round and display appropriate representation
function PrintSpan($start, $end) {
    $timeSpan = $end - $start
    if ($timeSpan.TotalDays -lt 1) {
        "$([int]$timeSpan.TotalHours)h" 
    }
    else {
        "$([int]$timeSpan.TotalDays)d"
    }
}

function GetTicketList($logfileName) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew();
    
    $ticketList = Get-Content $logfileName | Where-Object { isTicket $_ } | ForEach-Object { $_.SubString($_.IndexOf(' ') + 1) | ConvertFrom-Json } | ForEach-Object {
        $_.id = [int]$_.id
        if ($_.opened) { $_.opened = [datetime]::Parse($_.opened) }
        if ($_.closed) { $_.closed = [datetime]::Parse($_.closed) }
        $_
    }
    
    $timer.Stop(); Write-Debug "GetTicketList: $($ticketList.length) tickets found in $($timer.ElapsedMilliSeconds)ms"
    $ticketList
}

function CollapseTickets($ticketList) {  
    $timer = [System.Diagnostics.Stopwatch]::StartNew();

    # list distinct properties
    $propertynames = $ticketList | ForEach-Object { $_ | Get-Member -MemberType NoteProperty } | ForEach-Object { $_.Name } | Sort-Object -Unique
    Write-Debug "property names: $($propertynames -join ',')"

    $tickets = $ticketList | Group-Object -Property id | ForEach-Object {
        
        # join all objects properties values
        $allproperties = @{ } 		
        #$_.group | ForEach-Object { $item = $_; $propertynames | ForEach-Object { if ($item.$_) { $allproperties[$_] = $item.$_ } } }         
        $_.group | ForEach-Object { $item = $_; $propertynames | ForEach-Object { if($item.$_) { $allproperties[$_] = $item.$_ } } }     
        $result = New-Object psobject -Property $allproperties		
        
        if ($result.closed) {
            $result | Add-Member -MemberType NoteProperty -Name 'open' -Value (PrintSpan $result.opened $result.closed)
        }

        if($result.note) {
            $result.title = "* $($result.title)"
        }

        $result
    }
    
    $timer.Stop(); Write-Debug "CollapseTickets: $($tickets.length) tickets merged in $($timer.ElapsedMilliSeconds)ms"
    $tickets
}

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$configFile = Join-Path $scriptDirectory 'log.ps1.config'
$config = Get-Content $configFile | ConvertFrom-Json

$logfileName = $config.logfile
$dateFormat = 'ddd, yyyy-MM-dd HH:mm:ss'
if($config.dateFormat) {
    $dateFormat = $config.dateFormat
}
$date = (Get-Date -f $dateFormat)

$ticketList = GetTicketList($logfileName)

Write-Debug "parameter set name: $($PSCmdlet.ParameterSetName)"
switch ($PSCmdlet.ParameterSetName) {
    'Tail' {
        #Clear-Host
        "log [-Tail <int>]                      | [this view]: help, log, tickets"
        "log -Open <Ticket Description>         | open a new ticket, providing a description"        
        "log -Note|Close <Ticket Id> <Comment>  | add a note or close a ticket, providing a comment"         
        "log -View <Ticket Id>                  | show ticket details"         
        "log -Filter all|open|closed            | show all/open/closed tickets"

        "`nlatest $Tail entries:"
        gc $logfileName -Tail $Tail | %{ if(isTicket $_) { Write-Host -ForegroundColor DarkGray $_ } else { $_ } }
        "`nopen tickets:"
        CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', 'title', 'opened'
    }

    'Open' {
        $nextTicketId = 1 
        if ($ticketList.length -ge 1) {
            $nextTicketId = ($ticketList | ForEach-Object { $_.id } | Sort-Object -Descending)[0] + 1
        }
        
        "OPEN { 'id':'$nextTicketId', 'opened':'$date', 'title':'$Message', 'note':null, 'closed':null, 'resolution':null }" >> $logfileName
    }

    'Note' {
        "NOTE { 'id':'$($Note)', 'udate':'$date', 'note':'$Message' }" >> $logfileName
    }

    'View' {
        $ticketItems = $ticketList | ?{ $_.id -eq $View } 
       
        $openTicket = $ticketItems | ?{ $_.opened }
        "opened   : $($openTicket.opened.ToString($dateFormat))"
        "title    : $($openTicket.title)"                    

        $ticketItems | ?{ $_.note } | Format-List -Property 'udate','note'

        $closeTicket = $ticketItems | ?{ $_.closed }
        if($closeTicket){
            $closeTicket.closed = "$($closeTicket.closed.ToString($dateFormat)) (open $(PrintSpan $openTicket.opened $closeTicket.closed))"
            "closed    : $($closeTicket.closed)"
            "resolution: $($closeTicket.resolution)"                    
        }
    }    
    

    'Close' {
        "CLOSE { 'id':'$($Close)', 'closed':'$date', 'resolution':'$Message' }" >> $logfileName
    }

    'Filter' {
        switch ($Filter) {
            'all' {
                CollapseTickets $ticketList | Format-Table -Property 'id', 'title', 'note', 'resolution', 'opened', 'closed', 'open'
            }

            'open' {
                CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', 'title', 'note', 'opened'
            }

            'closed' {
                CollapseTickets $ticketList | Where-Object { $_.closed } | Format-Table -Property 'id', 'title', 'note', 'resolution', 'opened', 'closed', 'open'
            }
			
            default { Write-Error "af1 not implemented: -Filter $($Filter)" }
        }
    }

    'Log' {
        "$($date): $Message" >> $logfileName
    }

    default { Write-Error "eea not implemented: $($PSCmdlet.ParameterSetName)" }
}
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
    
    [Parameter(Mandatory = $true, ParameterSetName = "Search")]	
    [string]
    $Search,

    [Parameter(Mandatory = $true, ParameterSetName = "Open")]	
    [switch]
    $Open,

    [Parameter(Mandatory = $true, ParameterSetName = "Note")]	
    [int]
    $Note,

    [Parameter(Mandatory = $true, ParameterSetName = "View")]	
    [int]
    $View,

    [Parameter(Mandatory = $true, ParameterSetName = "Close")]	
    [int]
    $Close,

    # list tickets
    [Parameter(Mandatory = $true, ParameterSetName = "Tickets")]	
    [string]
    [ValidateSet("all", "open", "closed")]
    $Tickets,

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
    if(-not $end) {
        $end = Get-date
    }

    $timeSpan = $end - $start
    if ($timeSpan.TotalDays -lt 1) {
        "$([int]$timeSpan.TotalHours)h" 
    }
    else {
        "$([int]$timeSpan.TotalDays)d"
    }
}

function GetTicketList($log) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew();
        
    $ticketList = $log | Where-Object { isTicket $_ } | ForEach-Object { $_.SubString($_.IndexOf(' ') + 1) | ConvertFrom-Json } | ForEach-Object {
        $_.id = [int]$_.id
        if ($_.opened) { $_.opened = [datetime]::Parse($_.opened) }
        if ($_.closed) { $_.closed = [datetime]::Parse($_.closed) }
        $_
    }
    
    $timer.Stop(); Write-Debug "GetTicketList: $($ticketList.length) tickets found in $($timer.ElapsedMilliSeconds)ms"
    $ticketList
}

function CollapseTickets($ticketList) {  
    if(-not $ticketList){
        Write-Debug "CollapseTickets: 0 tickets merged."
        return
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew();

    # list distinct properties
    $propertynames = $ticketList | ForEach-Object { $_ | Get-Member -MemberType NoteProperty } | ForEach-Object { $_.Name } | Sort-Object -Unique
    Write-Debug "property names: $($propertynames -join ',')"

    $tickets = $ticketList | Group-Object -Property id | ForEach-Object {
        
        # join all objects properties values
        $allproperties = @{ } 		
        $_.group | ForEach-Object { $item = $_; $propertynames | ForEach-Object { if ($item.$_) { $allproperties[$_] = $item.$_ } } }         
        
        $opened = $allproperties['opened']
        if(-not $opened) { $opened = Get-Date } # when -Search'ing, OPEN tikets can be filtered out, leaving $opened empty

        $allproperties['open'] = (PrintSpan $opened $allproperties['closed'])
        
        $allproperties['opened (open)'] = "$($opened.ToString($tableDateFormat)) ($($allproperties['open']))"
        
        if ($allproperties['note']) { $allproperties['n'] = '*' }

        $result = New-Object psobject -Property $allproperties		
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
if ($config.dateFormat) {
    $dateFormat = $config.dateFormat
}
$tableDateFormat = 'ddd, dd.MM.';
if ($config.tableDateFormat) {
    $tableDateFormat = $config.tableDateFormat
}

$date = (Get-Date -f $dateFormat)

$timer = [System.Diagnostics.Stopwatch]::StartNew();
$log = Get-Content $logfileName
$timer.Stop(); Write-Debug "Get-Content: $($log.length) entries read in $($timer.ElapsedMilliSeconds)ms"
if($Search) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew();
    $log = $log | ?{ $_ -match $Search }
    $timer.Stop(); Write-Debug "Search: $($log.length) entries found in $($timer.ElapsedMilliSeconds)ms"
}

$ticketList = GetTicketList($log)

Write-Debug "parameter set name: $($PSCmdlet.ParameterSetName)"
switch ($PSCmdlet.ParameterSetName) {
    { ($_ -eq 'Tail') -or ($_ -eq 'Search') } {
        Clear-Host
        "log [-Tail <int>]                      | [this view]: help, log, tickets"
        "log <logentry>                         | add an entry to the log"
        "log -Search <regex>                    | search log for <regex>"
        "log -Open <Ticket Description>         | open a new ticket, providing a description"        
        "log -Note|Close <Ticket Id> <Comment>  | add a note or close a ticket, providing a comment"         
        "log -View <Ticket Id>                  | show ticket details"         
        "log -Tickets all|open|closed           | show all/open/closed tickets"

        "`nlatest $Tail entries:"
        $log[[System.Math]::Max(0, ($log.Length - $Tail))..($log.Length - 1)] | % { if (isTicket $_) { Write-Host -ForegroundColor DarkGray $_ } else { $_ } }
        "`nopen tickets:"

        $data = CollapseTickets $ticketList | Where-Object { -not $_.closed };
        $timer = [System.Diagnostics.Stopwatch]::StartNew();
        $data | Format-Table -Property 'id', 'opened (open)', 'n', 'title'
        $timer.Stop(); Write-Debug "TableOutput: $($timer.ElapsedMilliSeconds)ms"
    }

    'Open' {
        $nextTicketId = 1 
        if ($ticketList.length -ge 1) {
            $nextTicketId = ($ticketList | ForEach-Object { $_.id } | Sort-Object -Descending)[0] + 1
        }
        
        "OPEN { 'id':'$nextTicketId', 'opened':'$date', 'title':'$Message' }" >> $logfileName
    }

    'Note' {
        "NOTE { 'id':'$($Note)', 'udate':'$date', 'note':'$Message' }" >> $logfileName
    }

    'View' {
        $ticketItems = $ticketList | ? { $_.id -eq $View } 
       
        $openTicket = $ticketItems | ? { $_.opened }
        "opened   : $($openTicket.opened.ToString($dateFormat))"
        "title    : $($openTicket.title)"                    

        $ticketItems | ? { $_.note } | Format-List -Property 'udate', 'note'

        $closeTicket = $ticketItems | ? { $_.closed }
        if ($closeTicket) {
            $closeTicket.closed = "$($closeTicket.closed.ToString($dateFormat)) (open $(PrintSpan $openTicket.opened $closeTicket.closed))"
            "closed    : $($closeTicket.closed)"
            "resolution: $($closeTicket.resolution)"                    
        }
    }    
    
    'Close' {
        "CLOSE { 'id':'$($Close)', 'closed':'$date', 'resolution':'$Message' }" >> $logfileName
    }

    'Tickets' {
        switch ($Tickets) {
            'all' {
                CollapseTickets $ticketList | Format-Table 'id', @{ Label = 'since'; Expression = { if ($_.closed) { $_.closed.ToString($tableDateFormat) } else { $_.opened.ToString($tableDateFormat) } } }, @{ Label = ''; Expression = { if ($_.closed) { '-' } } }, @{ Label = ''; Expression = { if ($_.note) { '*' } } }, 'title'
            }

            'open' {
                #CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', @{ Label = 'open'; Expression = { PrintSpan $_.opened (date) } }, @{ Label = ''; Expression = { if ($_.note) { '*' } } }, 'title'
                CollapseTickets $ticketList | Where-Object { -not $_.closed } | Format-Table -Property 'id', 'opened (open)', 'n', 'title'
            }

            'closed' {
                CollapseTickets $ticketList | Where-Object { $_.closed } | Format-Table -Property 'id', @{ Label = 'closed'; Expression = { $_.closed.ToString($tableDateFormat) } }, @{ Label = 'after'; Expression = { $_.open } }, @{ Label = ''; Expression = { if ($_.note) { '*' } } }, 'title'
            }
			
            default { Write-Error "af1 not implemented: -Tickets $($Tickets)" }
        }
    }

    'Log' {
        "$($date): $Message" >> $logfileName
    }

    default { Write-Error "eea not implemented: $($PSCmdlet.ParameterSetName)" }
}
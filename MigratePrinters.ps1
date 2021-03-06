<#
    .SYNOPSIS
        Logon Script to migrate printer mapping
    
    .DESCRIPTION
        Logon Script to migrate printer mappings
    
    .NOTES
        Based on http://learn-powershell.net/2012/11/15/use-powershell-logon-script-to-update-printer-mappings/
#>
Param (
    $PrinterQueues="\\path\to\PrinterQueues.csv",
    $ElasticSearch = "http://server:9200/myindex/",
    $PrinterLog="\\path\to\log\for\elasticsearch\errors"
)
<#
    #create the headers for elasticsearch errors
    "Date,Computer,User,URL,Document,Error"  | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
#>
function SendJSON($RemoteURL,$MessageHash){
    Try {
        if (!$http_request) {
            write-verbose("Creating Msxml2.XMLHTTP object") -verbose
            $http_request = New-Object -ComObject Msxml2.XMLHTTP
        }
        $props=@()
        $timestamp=get-date -format "yyy/MM/dd HH:mm:ss"
        $props+="""@timestamp"":""{0}""" -f $timestamp
        ForEach($key in $MessageHash.keys) {
            $value=$MessageHash[$key];
            if (!$value) {$value=""}
            $value=$value.ToString()
            $props+="""{0}"":""{1}""" -f $key,$value.replace("\","\\").replace("""","\""")
        }
        $doc="{{ {0} }}" -f ($props -join ",")
        write-verbose("sending doc $doc to $RemoteURL") -verbose
    <# #>
        $http_request.Open(‘POST’, $RemoteURL, $false)
        $http_request.SetRequestHeader(“Content-type”,“application/json”)
        $http_request.SetRequestHeader(“Content-length”, $doc.length)
        $http_request.SetRequestHeader(“Connection”,“close”)
        $http_request.Send($doc)
        write-verbose($http_request.responseText) -verbose
        
    } Catch {
        Write-Verbose ("logging error {0}" -f $_.Exception.Message) -verbose
        if (! $PrinterLog -eq "") {
            "{0},{1},{2},{3},""{4}"",{5}" -f (Get-Date),
                                         $Env:COMPUTERNAME,
                                         $env:USERNAME,
                                         $RemoteURL,
                                         $doc.Replace("""",""""""),
                                         $_.Exception.Message.replace("`n","").replace("`r","")  | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
        }
    }
    return
}
Try {
    Write-Verbose ("{0}: Getting list of print queues" -f $Env:USERNAME) -Verbose
    $printQueues=Import-Csv $PrinterQueues
    #Get default printer
    $defaultPrinter = gwmi win32_printer | where {$_.Default -eq $true}
    Write-Verbose ("{0}: Checking for printers mapped to old print server" -f $Env:USERNAME)
    $printers = @(Get-WmiObject -Class Win32_Printer -ErrorAction Stop)
    If ($printers.count -gt 0) {        
        ForEach ($printer in $printers) {
            Write-Verbose ("{0}: Checking list" -f $Printer.Name) -verbose
            $found=0;
            ForEach ($queue in $printQueues) {
                if ($printer.Name -eq $queue.OldPrinter -or $printer.SystemName+"\" + $printer.ShareName -eq $queue.OldPrinter ) {
                    $found=1
                    Write-Verbose ("{0}: Replacing with new print server name: {1}" -f $Printer.Name,$queue.NewPrinter) -Verbose
                    $returnValue = ([wmiclass]"Win32_Printer").AddPrinterConnection($queue.NewPrinter).ReturnValue
                    If ($returnValue -eq 0) {
                        $msg=@{
                            COMPUTERNAME=$Env:COMPUTERNAME;
                            USERNAME=$env:USERNAME;
                            PRINTERNAME=$queue.NewPrinter;
                            RETURNVALUE=$returnValue;
                            DATE=(get-date);
                            STATUS="Added Printer";
                        }
                        SendJSON "$ElasticSearch/event" $msg
                        if ($printer.Name -eq $defaultPrinter.Name) {
                            $newprinterlist=@(Get-WmiObject -Class Win32_Printer -ErrorAction Stop)
                            ForEach($np in $newprinterlist) {
                                if ($np.Name -eq $queue.NewPrinter) {
                                    $np.SetDefaultPrinter()
                                    $msg=@{
                                        COMPUTERNAME=$Env:COMPUTERNAME;
                                        USERNAME=$env:USERNAME;
                                        PRINTERNAME=$queue.NewPrinter;
                                        RETURNVALUE=$returnValue;
                                        DATE=(get-date);
                                        STATUS="Set printer as default";
                                    }
                                    SendJSON "$ElasticSearch/event" $msg
                                }
                            }
                        }
                        try {
                            Write-Verbose ("{0}: Removing" -f $printer.name)
                            $printer.Delete()
                            $msg=@{
                                COMPUTERNAME=$Env:COMPUTERNAME;
                                USERNAME=$env:USERNAME;
                                PRINTERNAME=$printer.Name;
                                RETURNVALUE=0;
                                DATE=(get-date);
                                STATUS="Removed Printer";
                            }
                            SendJSON "$ElasticSearch/event" $msg
                        } Catch {
                            $msg=@{
                                COMPUTERNAME=$Env:COMPUTERNAME;
                                USERNAME=$env:USERNAME;
                                PRINTERNAME=$printer.Name;
                                RETURNVALUE=$_.Exception.Message.replace("`n","").replace("`r","");
                                DATE=(get-date);
                                STATUS="Error Deleting Printer";
                            }
                            SendJSON "$ElasticSearch/event" $msg
                        }      
                    } Else {
                        Write-Verbose ("{0} returned error code: {1}" -f $queue.NewPrinter,$returnValue) -Verbose
                        $msg=@{
                            COMPUTERNAME=$Env:COMPUTERNAME;
                            USERNAME=$env:USERNAME;
                            PRINTERNAME=$queue.NewPrinter;
                            RETURNVALUE=$returnValue;
                            DATE=(get-date);
                            STATUS="Error Adding Printer";
                        }
                        SendJSON "$ElasticSearch/event" $msg
                    }
                    break
                }
                Elseif ($printer.Name -eq $queue.NewPrinter -or $printer.SystemName+"\" + $printer.ShareName -eq $queue.NewPrinter ) {
                    $found=1;
                    break
                }
            }
            if ($found -eq 0 -and $printer.SystemName -ne $Env:COMPUTERNAME ) {
                Write-Verbose ("Printer {0} not found" -f $printer.Name) -Verbose
                $msg=@{
                    COMPUTERNAME=$Env:COMPUTERNAME;
                    USERNAME=$env:USERNAME;
                    PRINTERNAME=$printer.Name;
                    DATE=(get-date);
                    STATUS="Printer not found";
                }
                SendJSON "$ElasticSearch/unlisted" $msg
            }
        }
    }
} Catch {
    Write-Verbose ("script error {0}" -f $_.Exception.Message) -verbose
    $msg=@{
        COMPUTERNAME=$Env:COMPUTERNAME;
        USERNAME=$env:USERNAME;
        RETURNVALUE=$_.Exception.Message.replace("`n","").replace("`r","");
        DATE=(get-date);
        STATUS="WMIERROR";
    }
    SendJSON "$ElasticSearch/wmierror" $msg
}

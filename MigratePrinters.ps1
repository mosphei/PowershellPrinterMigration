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
    $elasticsearch = "http://server:9200/"
)
<#
    #Header for CSV log file:
    "COMPUTERNAME,USERNAME,PRINTERNAME,RETURNCODE-ERRORMESSAGE,DATETIME,STATUS" | 
        Out-File -FilePath $PrinterLog -Encoding ASCII
    #Header for UnlistedLog printers:
    "COMPUTERNAME,USERNAME,PRINTERNAME,DATETIME,STATUS" | Out-File -FilePath $UnlistedLog -Encoding ASCII
#>
Try {
    Write-Verbose ("{0}: Getting list of print queues" -f $Env:USERNAME) -Verbose
    $printQueues=Import-Csv $PrinterQueues
    #Get default printer
    $defaultPrinter = gwmi win32_printer | where {$_.Default -eq $true}
    Write-Verbose ("{0}: Checking for printers mapped to old print server" -f $Env:USERNAME)
    $printers = @(Get-WmiObject -Class Win32_Printer -ErrorAction Stop)
    If ($printers.count -gt 0) {        
        ForEach ($printer in $printers) {
            Write-Verbose ("{0}: Checking list" -f $Printer.Name)
            $found=0;
            ForEach ($queue in $printQueues) {
                if ($printer.Name -eq $queue.OldPrinter -or $printer.SystemName+"\" + $printer.ShareName -eq $queue.OldPrinter ) {
                    $found=1
                    Write-Verbose ("{0}: Replacing with new print server name: {1}" -f $Printer.Name,$queue.NewPrinter) -Verbose
                    $returnValue = ([wmiclass]"Win32_Printer").AddPrinterConnection($queue.NewPrinter).ReturnValue
                    If ($returnValue -eq 0) {
                        "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                                     $env:USERNAME,
                                                     $queue.NewPrinter,
                                                     $returnValue,
                                                     (Get-Date),
                                                     "Added Printer" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
                        if ($printer.Name -eq $defaultPrinter.Name) {
                            $newprinterlist=@(Get-WmiObject -Class Win32_Printer -ErrorAction Stop)
                            ForEach($np in $newprinterlist) {
                                if ($np.Name -eq $queue.NewPrinter) {
                                    $np.SetDefaultPrinter()
                                    "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                                     $env:USERNAME,
                                                     $queue.NewPrinter,
                                                     $returnValue,
                                                     (Get-Date),
                                                     "Set printer as default" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
                                }
                            }
                        }
                        try {
                        Write-Verbose ("{0}: Removing" -f $printer.name)
                            $printer.Delete()
                            "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                                         $env:USERNAME,
                                                         $printer.Name,
                                                         $returnValue,
                                                         (Get-Date),
                                                         "Removed Printer" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
                        } Catch {
                            "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                                         $env:USERNAME,
                                                         $printer.Name,
                                                         $_.Exception.Message,
                                                         (Get-Date),
                                                         "Error Deleting Printer" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
                        }      
                    } Else {
                        Write-Verbose ("{0} returned error code: {1}" -f $queue.NewPrinter,$returnValue) -Verbose
                        "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                                     $env:USERNAME,
                                                     $queue.NewPrinter,
                                                     $returnValue,
                                                     (Get-Date),
                                                     "Error Adding Printer" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
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
                "{0},{1},{2},{3},{4}" -f $Env:COMPUTERNAME,
                                             $env:USERNAME,
                                             $printer.Name,
                                             (Get-Date),
                                             "Printer not found" | Out-File -FilePath $UnlistedLog -Append -Encoding ASCII
            }
        }
    }
} Catch {
    "{0},{1},{2},{3},{4},{5}" -f $Env:COMPUTERNAME,
                                 $env:USERNAME,
                                 "WMIERROR",
                                 $_.Exception.Message,
                                 (Get-Date),
                                 "Error Querying Printers" | Out-File -FilePath $PrinterLog -Append -Encoding ASCII
}
function SendJSON($URL,$MessageHash){
    Try {
        $props=@()
        $timestamp=get-date -format "yyy/MM/dd HH:mm:ss"
        $props+="""@timestamp"":""{0}""" -f $timestamp
        ForEach($key in $MessageHash.keys) {
            $props+="""{0}"":""{1}""" -f $key,$MessageHash[$key].replace("\","\\").replace("""","\""")
        }
        $doc="{{ {0} }}" -f ($props -join ",")
        write-verbose("sending doc $doc to $URL") -verbose
    <# #>
        $http_request.Open(‘POST’, $URL, $false)
        $http_request.SetRequestHeader(“Content-type”,“application/json”)
        $http_request.SetRequestHeader(“Content-length”, $doc.length)
        $http_request.SetRequestHeader(“Connection”,“close”)
        $http_request.Send($doc)
        write-verbose($http_request.responseText) -verbose
        
    } Catch {
    }
}
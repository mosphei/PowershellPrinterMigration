# PowershellPrinterMigration
Powershell Printer Migration
============================
powershell logon script to migrate print mappings from one server to another

Introduction
------------
This script is based on http://learn-powershell.net/2012/11/15/use-powershell-logon-script-to-update-printer-mappings/

When preparing to sunset a print server we wanted to migrate the printer mappings using a script by Boe Prox which simply replaces the old server name with the new name, adds the printer and then deletes the old mapping. We ran into a problem however, the old printer queue names were not standardised and so we wanted to rename some of the queues as well as move them to a new server.

Our solution was to use a csv file with a list of old queues and new queues. Each time a user logs in the script will check their printers and if the printer is mapped to an OldPrinter entry in the csv file it will add the corresponding new print queue and then delete the old one.

Instructions for use
--------------------

* Edit MigratePrinters.ps1 and specify the full path to PrinterQueues.csv. Add paths for $PrinterLog and $UnlistedLog as well.
* Edit PrinterQueues.csv and add a line for each old printer queue and corresponding new printer queue.
* Copy the MigratePrinters.ps1 and PrinterQueues.csv to a unc folder ideally in \\domain\netlogon
* Create a group policy object and specify MigratePrinters.ps1 path under logon scripts on the powershell tab. It is important to use the powershell tab.
* Create the log files and write the first line (headers)
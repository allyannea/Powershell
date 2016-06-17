param(
 [string]$emailto = 'YourEmail@domain.com',
 [string]$emailcc = $null
)

<# 
.SYNOPSIS 
    Script to check the GoldenGate replicat statuses. 
 
.DESCRIPTION 
    Takes the output from "status all" and parses into
 a hash table, then sends emails based on the following logic:
   - Excessive lag times
   - Any ABENDs
   - MANAGER stopped

.PARAMETER emailto
 Type: String
 Default value: YourEmail@domain.com
 The full address that should get all alerts.
 
.PARAMETER emailcc
 Type: String
 Default value: null
 The full address for ABEND and manager failures.
 
.NOTES 
 March 2013 : Allison Anderson  Original version
    02 May 2013: Allison Anderson  Added CC option
#> 

Push-Location
$ggdir = '\\' + $env:COMPUTERNAME + '\GoldenGate\112'
Set-Location $ggdir

#Set the variables
$msgbodyval = $null
$sendmail = $null
$i = $null
$j = $null
$k = $null
$lagval = $null
$chkptval = $null
$emailpriority = 'Normal'
$lag = @()
$chkpt = @()
$output = @()
$msgbody = @()
$statushash = @{}
$laghash = @{}
$chkpthash = @{}
$email = @{}

#Check the GoldenGate statuses.  This produces the same output as "info all" from ggsci.
$output = ./ggsci paramfile ./util_scripts/status_all.txt 

#Parse the output for just the manager and replicat info.
$startloc = $output | Select-String 'Program' 
$endloc = $output | Select-String 'GGSCI' |Select-Object -Last 1 
$startlocval = $startloc.LineNumber
$endlocval = $endloc.linenumber - 2
$output = $output | 
 Select-Object -Index ($startlocval..$endlocval) |
 where {$_ -ne ''} 

#Strip out the double-spaces for easy parsing later.
while ($output | Select-String '  ') {
 $output = $output -replace '  ', ' '
}

#Loop through the output and figure out if the manager is running.
foreach($i in $output){
 $i = $i.Split(' ') 

 if($i[0] -eq 'MANAGER'){
  if ($i[1] -ne 'RUNNING'){
   #We need to start the manager as a service, not through ggsci.
   Start-Service 'GGMGR112' | Out-Null
   
   $msgbody += 'Manager STOPPED, attempted to restart.' 
 
   $sendmail = $true
   $emailpriority = 'High'
   
  }
 } else {
  #For replicats, calculate the lag and checkpoint time in hours as a double (convert from hh:mm:ss).
 
  $lag = $i[3].Split(':')
  $lagval = $lag[0] -as [double] 
  $lagval += ($lag[1] -as [double])/60
  
  $chkpt = $i[4].Split(':')
  $chkptval = $chkpt[0] -as [double]
  $chkptval += ($chkpt[1] -as [double])/60

  $statushash.Add($i[2], $i[1])
  $laghash.Add($i[2], $lagval)
  $chkpthash.Add($i[2], $chkptval)
 }
} 

#Criteria for sending an alert.  Any abends will generate an email.
#For checkpoint, we want to know if a replicat has been STOPPED.
#We also want to know if any lag is over a half hour.

foreach ($j in $statushash.Keys){

 $chkptval = $chkpthash[$j] -as [double]
 
 if ($statushash[$j] -eq 'ABENDED'){
  $sendmail = $true
  $emailpriority = 'High'
  $msgbody += $j.tostring() + ' is ' + $statushash[$j] + ' with CHECKPOINT of ' + $chkptval.ToString('n1') + ' hours.'
 } elseif ($statushash[$j] -eq 'STOPPED') {
  if ($chkptval -gt 0){
   $sendmail = $true
   $msgbody += $j.tostring() + ' is ' + $statushash[$j] + ' with CHECKPOINT of ' + $chkptval.ToString("n1") + ' hours.'
   }
 }
}

foreach ($k in $laghash.keys) {
 $lagval = $laghash[$k] -as [double]
 if ($lagval -gt 0.5){   #<---- This is the value (in hours) to change if you want to increase/decrease monitored value for LAG.  
  $sendmail = $true
  $msgbody += $k.tostring() + ' has a LAG of ' + $lagval.tostring("n1") + ' hours.'
 }
}

#Sending the email in case the flag has been set.
if ($sendmail){
 $subj = $env:COMPUTERNAME + ' GoldenGate problems'
 $msgbodyval = $msgbody | Out-String
 
 $email = @{
  Subject = $subj 
  From  = 'no.reply@capella.edu'
  To = $emailto 
  Priority = $emailpriority 
  SmtpServer = 'smtp.capella.lan' 
  body = $msgbodyval 
 }
 
 if($emailcc){$email.CC = $emailcc}

 Send-MailMessage @email
}

Pop-Location

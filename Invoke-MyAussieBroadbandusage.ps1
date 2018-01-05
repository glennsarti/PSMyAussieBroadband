Param([String]$Username, [String]$Password, [Switch]$SaveCredentials)

Install-Module PSSecret -Scope CurrentUser

if ( ($Username -eq '') -and ($Password -eq '') ) {
  $cred = Get-CMSSecret -Name 'AussieBroadband' -Type HashTable -ValueOnly
  if ($cred -eq $null) { Throw "Please use -Username and -Password to specify credentials"; return}
} else {

  $cred = @{ 'username' = $Username; 'password' = $Password }
  if ($SaveCredentials) {
    Add-CMSSecret -Name 'AussieBroadband' -HashTable $cred
  }
}
& "$($PSScriptRoot)\Get-MyAussieBroadbandUsage.ps1" -Username $cred.Username -Password $cred.Password

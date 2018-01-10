param([String]$Username, [String]$Password)
$ErrorActionPreference = 'Stop'

$usageURI = 'https://my.aussiebroadband.com.au/usage.php'
$logoutURI = 'https://my.aussiebroadband.com.au/logout.php'

Import-Module (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath Graphical) -ChildPath Graphical.psd1)

# Initial Session Login
$mabbSession = $null

Function Convert-ToFloatGB($value) {
  Write-Output ([Float]($value.Replace('GB','')))
}

$body = @{
  'login_username' = $username
  'login_password' = $password
  'submit' = 'Login'
}

# Get a session token
$result = Invoke-WebRequest -Uri $usageURI -Method POST -Body $body -SessionVariable mabbSession -UseBasicParsing
# Now query for real...
$result = Invoke-WebRequest -Uri $usageURI -Method POST -Body $body -SessionVariable mabbSession

$parsedDoc = $result.ParsedHTML

$dataPoints = New-Object 'System.Collections.Generic.List[object]'
$TotalUp = -1
$TotalDown = -1
$TotalLeft = -1

# Workaround - https://www.sepago.com/blog/2016/05/03/powershell-exception-0x800a01b6-while-using-getelementsbytagname-getelementsbyname
$parsedDoc.IHTMLDocument3_getElementsByTagName('table') | % {
  $table = $_

  if ($table.thead.rows[0].childNodes[3].OuterText -eq 'Internet Data') {
    $table.rows | ? { $_.ChildNodes.length -gt 1 } | % {
      $thisRow = $_
      $label = $thisRow.ChildNodes[1].OuterText.Trim()

      switch -Wildcard ($label) {
        '' { break; }
        'Date' { break; }
        'Total Used' {
          $TotalUp = Convert-ToFloatGB($thisRow.ChildNodes[3].OuterText)
          $TotalDown = Convert-ToFloatGB($thisRow.ChildNodes[5].OuterText)
          break;
        }
        'Used Combined' { break; }
        'Data Left' {
          $TotalLeft = Convert-ToFloatGB($thisRow.ChildNodes[3].OuterText)
          break;
        }
        '??-??-????' {
          $up = Convert-ToFloatGB($thisRow.ChildNodes[3].OuterText)
          $down = Convert-ToFloatGB($thisRow.ChildNodes[5].OuterText)

          $dataPoints.Add( ($up + $down))
          break;
        }
        default { Write-Host "!! FOUND UNEXPECTED LABEL '${label}'" }
      }
    }
  }
}

$BillingPeriod = 'UNKNOWN'
$BillingStartDate = -1
$BillingEndDate = -1
$now = [DateTime]::Now
$parsedDoc.IHTMLDocument3_getElementsByTagName('select') | ? { $_.className -eq 'date select' } | % {
  $item = $_
  $BillingPeriod = ($item.options | ? { $_.selected } | Select -First 1).label
  $startDateText = $BillingPeriod.split('-')[0].Trim()
  $BillingStartDate = [DateTime]($startDateText + ' ' + $now.year.ToString())
  if ($BillingStartDate -gt $now) {
    # We hit a date period that spans years.  Go back one year
    $BillingStartDate = [DateTime]($startDateText + ' ' + ($now.year - 1).ToString())
  }
  $BillingEndDate = $BillingStartDate.AddMonths(1).AddMinutes(-1)
}

# Pad the datapoints
$index = $Now
While ($index -lt $BillingEndDate) {
  $dataPoints.Add(0)
  $index = $index.AddDays(1)
}

Show-Graph -Datapoints $dataPoints -XAxisTitle 'Date' -YAxisTitle 'Total' -YAxisStep 1
Write-Host ""
Write-Host "Billing          : $($BillingStartDate.ToString('d MMM yyyy')) - $($BillingEndDate.ToString('d MMM yyyy')) ($( ($BillingEndDate - $Now).Days + 1) days left)"
Write-Host "Total Data (U/D) : $( ($TotalUp + $TotalDown).ToString('0.00')) GB (${TotalUp}/${TotalDown})"
Write-Host "Total Data Left  : ${TotalLeft} GB"

if ( ($Now - $BillingStartDate).Days -gt 7) {
  # Calculate Future Usage
  $TotalBillingHours = ($BillingEndDate - $BillingStartDate).TotalHours

  $Projected = $TotalBillingHours / ($Now - $BillingStartDate).TotalHours * ($TotalUp + $TotalDown)
  $Projected = $Projected - $TotalUp - $TotalDown
  $color = 'Red'
  if ($Projected -le $TotalLeft) {
    $color = 'Green'
  }

  Write-Host -ForegroundColor $color "Data Needed      : $($Projected.ToString('0.00')) GB"
}
$result = Invoke-WebRequest -Uri $logoutURI -Method POST -Body $body -SessionVariable mabbSession -UseBasicParsing

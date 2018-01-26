param($app,$dir)

."$psscriptroot\..\lib\core.ps1"
."$psscriptroot\..\lib\manifest.ps1"
."$psscriptroot\..\lib\description.ps1"

if (!$dir) {
  $dir = "$psscriptroot\..\bucket"
}
$dir = Resolve-Path $dir

$search = "*"
if ($app) { $search = $app }

# get apps to check
$apps = @()
Get-ChildItem $dir "$search.json" | ForEach-Object {
  $json = parse_json "$dir\$_"
  $apps +=,@( ($_ -replace '\.json$',''),$json)
}

$apps | ForEach-Object {
  $app,$json = $_
  Write-Host "$app`: " -NoNewline

  if (!$json.homepage) {
    Write-Host "`nNo homepage set." -fore red
    return
  }
  # get description from homepage
  try {
    $home_html = (New-Object net.webclient).downloadstring($json.homepage)
  } catch {
    Write-Host "`n$($_.exception.message)" -fore red
    return
  }

  $description,$descr_method = find_description $json.homepage $home_html
  if (!$description) {
    Write-Host -fore red "`nDescription not found ($($json.homepage))"
    return
  }

  $description = clean_description $description

  Write-Host "(found by $descr_method)"
  Write-Host "  ""$description""" -fore green

}


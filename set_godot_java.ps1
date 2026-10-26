param([string]$Jdk)
# Points Godot's editor setting export/android/java_sdk_path at the given JDK (used by the Gradle export).
$j = $Jdk.TrimEnd('\').Replace('\', '/')
$line = 'export/android/java_sdk_path = "' + $j + '"'
Get-ChildItem (Join-Path $env:APPDATA 'Godot') -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue | ForEach-Object {
  $t = Get-Content $_.FullName -Raw
  if ($t -match 'export/android/java_sdk_path') {
    $t = [regex]::Replace($t, 'export/android/java_sdk_path = "[^"]*"', $line.Replace('$', '$$'))
  } else {
    $t = $t.TrimEnd() + "`r`n" + $line + "`r`n"
  }
  Set-Content -Path $_.FullName -Value $t -NoNewline
  Write-Host "Godot Java SDK path set in $($_.Name): $j"
}

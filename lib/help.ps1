function usage($text) {
    $text | Select-String '(?m)^# Usage: ([^\n]*)$' | ForEach-Object { "Usage: " + $_.matches[0].groups[1].value }
}

function summary($text) {
    $text | Select-String '(?m)^# Summary: ([^\n]*)$' | ForEach-Object { $_.matches[0].groups[1].value }
}

function scoop_help($text) {
    $help_lines = $text | Select-String '(?ms)^# Help:(.(?!^[^#]))*' | ForEach-Object { $_.matches[0].value; }
    $help_lines -replace '(?ms)^#\s?(Help: )?', ''
}

function my_usage { # gets usage for the calling script
    usage (Get-Content $myInvocation.PSCommandPath -raw)
}

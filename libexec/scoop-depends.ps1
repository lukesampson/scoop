# Usage: scoop depends <app>
# Summary: List dependencies for an app

reset_aliases

$opt, $apps, $err = getopt $args 'a:' 'arch='
$app = $apps[0]

if(!$app) { error '<app> missing'; my_usage; exit 1 }

$architecture = default_architecture
try {
    $architecture = ensure_architecture ($opt.a + $opt.arch)
} catch {
    abort "ERROR: $_"
}

$deps = @(deps $app $architecture)
if($deps) {
    $deps[($deps.length - 1)..0]
}

exit 0

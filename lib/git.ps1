function git_proxy_cmd {
    $proxy = get_config 'proxy'
    $cmd = "git $($args | ForEach-Object { "$_ " })"
    if($proxy -and $proxy -ne 'none') {
        $cmd = "SET HTTPS_PROXY=$proxy&&SET HTTP_PROXY=$proxy&&$cmd"
    }
    & "$env:COMSPEC" /c $cmd
}

function git_clone {
    git_proxy_cmd clone $args
}

function git_ls_remote {
    git_proxy_cmd ls-remote $args
}

function git_checkout {
    git_proxy_cmd checkout $args
}

function git_branch {
    git_proxy_cmd branch $args
}

function git_pull {
    git_proxy_cmd pull $args
}

function git_fetch {
    git_proxy_cmd fetch $args
}

function git_log {
    git_proxy_cmd --no-pager log $args
}

function git_checkout {
    git_proxy_cmd checkout $args
}

function git_branch {
    git_proxy_cmd branch $args
}

function git_config {
    git_proxy_cmd config $args
}

function git_reset {
    git_proxy_cmd reset $args
}

function git_status {
    git_proxy_cmd status $args
}

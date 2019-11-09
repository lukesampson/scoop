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

function git_pull {
    git_proxy_cmd pull $args
}

function git_fetch {
    git_proxy_cmd fetch $args
}

function git_checkout {
    git_proxy_cmd checkout $args
}

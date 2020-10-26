. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\unix.ps1"
. "$psscriptroot\Scoop-TestLib.ps1"

$isUnix = is_unix

describe "ensure_architecture" -Tag 'Scoop' {
    it "should keep correct architectures" {
        ensure_architecture "32bit" | should -be "32bit"
        ensure_architecture "32" | should -be "32bit"
        ensure_architecture "x86" | should -be "32bit"
        ensure_architecture "X86" | should -be "32bit"
        ensure_architecture "i386" | should -be "32bit"
        ensure_architecture "386" | should -be "32bit"
        ensure_architecture "i686" | should -be "32bit"

        ensure_architecture "64bit" | should -be "64bit"
        ensure_architecture "64" | should -be "64bit"
        ensure_architecture "x64" | should -be "64bit"
        ensure_architecture "X64" | should -be "64bit"
        ensure_architecture "amd64" | should -be "64bit"
        ensure_architecture "AMD64" | should -be "64bit"
        ensure_architecture "x86_64" | should -be "64bit"
        ensure_architecture "x86-64" | should -be "64bit"

        ensure_architecture "arm64" | should -be "arm64"
        ensure_architecture "armv8" | should -be "arm64"
        ensure_architecture "aarch64" | should -be "arm64"
    }

    it "should fallback to the default architecture on empty input" {
        ensure_architecture "" | should -be $(default_architecture)
        ensure_architecture $null | should -be $(default_architecture)
    }

    it "should show an error with an invalid architecture" {
        { ensure_architecture "PPC" } | Should -Throw
        { ensure_architecture "PPC" } | Should -Throw "Invalid architecture: 'ppc'"
    }
}

describe "appname_from_url" -Tag 'Scoop' {
    it "should extract the correct name" {
        appname_from_url "https://example.org/directory/foobar.json" | should -be "foobar"
    }
}

describe "url_filename" -Tag 'Scoop' {
    it "should extract the real filename from an url" {
        url_filename "http://example.org/foo.txt" | should -be "foo.txt"
        url_filename "http://example.org/foo.txt?var=123" | should -be "foo.txt"
    }

    it "can be tricked with a hash to override the real filename" {
        url_filename "http://example.org/foo-v2.zip#/foo.zip" | should -be "foo.zip"
    }
}

describe "url_remote_filename" -Tag 'Scoop' {
    it "should extract the real filename from an url" {
        url_remote_filename "http://example.org/foo.txt" | should -be "foo.txt"
        url_remote_filename "http://example.org/foo.txt?var=123" | should -be "foo.txt"
    }

    it "can not be tricked with a hash to override the real filename" {
        url_remote_filename "http://example.org/foo-v2.zip#/foo.zip" | should -be "foo-v2.zip"
    }
}

describe "is_in_dir" -Tag 'Scoop' {
    it "should work correctly" -skip:$isUnix {
        is_in_dir "C:\test" "C:\foo" | should -BeFalse
        is_in_dir "C:\test" "C:\test\foo\baz.zip" | should -betrue

        is_in_dir "test" "$psscriptroot" | should -betrue
        is_in_dir "$psscriptroot\..\" "$psscriptroot" | should -BeFalse
    }
}

describe "env add and remove path" -Tag 'Scoop' {
    # test data
    $manifest = @{
        "env_add_path" = @("foo", "bar")
    }
    $testdir = join-path $psscriptroot "path-test-directory"
    $global = $false

    # store the original path to prevent leakage of tests
    $origPath = $env:PATH

    it "should concat the correct path" -skip:$isUnix {
        mock add_first_in_path {}
        mock remove_from_path {}

        # adding
        env_add_path $manifest $testdir $global
        Assert-MockCalled add_first_in_path -Times 1 -ParameterFilter {$dir -like "$testdir\foo"}
        Assert-MockCalled add_first_in_path -Times 1 -ParameterFilter {$dir -like "$testdir\bar"}

        env_rm_path $manifest $testdir $global
        Assert-MockCalled remove_from_path -Times 1 -ParameterFilter {$dir -like "$testdir\foo"}
        Assert-MockCalled remove_from_path -Times 1 -ParameterFilter {$dir -like "$testdir\bar"}
    }
}

describe "shim_def" -Tag 'Scoop' {
    it "should use strings correctly" {
        $target, $name, $shimArgs = shim_def "command.exe"
        $target | should -be "command.exe"
        $name | should -be "command"
        $shimArgs | should -benullorempty
    }

    it "should expand the array correctly" {
        $target, $name, $shimArgs = shim_def @("foo.exe", "bar")
        $target | should -be "foo.exe"
        $name | should -be "bar"
        $shimArgs | should -benullorempty

        $target, $name, $shimArgs = shim_def @("foo.exe", "bar", "--test")
        $target | should -be "foo.exe"
        $name | should -be "bar"
        $shimArgs | should -be "--test"
    }
}

describe 'persist_def' -Tag 'Scoop' {
    it 'parses string correctly' {
        $source, $target = persist_def "test"
        $source | should -be "test"
        $target | should -be "test"
    }

    it 'should handle sub-folder' {
        $source, $target = persist_def "foo/bar"
        $source | should -be "foo/bar"
        $target | should -be "foo/bar"
    }

    it 'should handle arrays' {
        # both specified
        $source, $target = persist_def @("foo", "bar")
        $source | should -be "foo"
        $target | should -be "bar"

        # only first specified
        $source, $target = persist_def @("foo")
        $source | should -be "foo"
        $target | should -be "foo"

        # null value specified
        $source, $target = persist_def @("foo", $null)
        $source | should -be "foo"
        $target | should -be "foo"
    }
}

describe 'compute_hash' -Tag 'Scoop' {
    beforeall {
        $working_dir = setup_working "manifest"
    }

    it 'computes MD5 correctly' {
        compute_hash (join-path "$working_dir" "invalid_wget.json") 'md5' | should -be "cf229eecc201063e32b436e73b71deba"
        compute_hash (join-path "$working_dir" "wget.json") 'md5' | should -be "57c397fd5092cbd6a8b4df56be2551ab"
        compute_hash (join-path "$working_dir" "broken_schema.json") 'md5' | should -be "0427c7f4edc33d6d336db98fc160beb0"
        compute_hash (join-path "$working_dir" "broken_wget.json") 'md5' | should -be "30a7d4d3f64cb7a800d96c0f2ccec87f"
    }

    it 'computes SHA-1 correctly' {
        compute_hash (join-path "$working_dir" "invalid_wget.json") 'sha1' | should -be "33ae44df8feed86cdc8f544234029fb28280c3c5"
        compute_hash (join-path "$working_dir" "wget.json") 'sha1' | should -be "98bfacb887da8cd05d3a1162f89d90173294be55"
        compute_hash (join-path "$working_dir" "broken_schema.json") 'sha1' | should -be "6dcd64f8ce7a3ae6bbc3dc2288b7cb202dbfa3c8"
        compute_hash (join-path "$working_dir" "broken_wget.json") 'sha1' | should -be "60b5b1d5bcb4193d19aeab265eab0bb9b0c46c8f"
    }

    it 'computes SHA-256 correctly' {
        compute_hash (join-path "$working_dir" "invalid_wget.json") 'sha256' | should -be "1a92ef57c5f3cecba74015ae8e92fc3f2dbe141f9d171c3a06f98645a522d58c"
        compute_hash (join-path "$working_dir" "wget.json") 'sha256' | should -be "31d6d0953d4e95f0a42080acd61a8c2f92bc90cae324c0d6d2301a974c15f62f"
        compute_hash (join-path "$working_dir" "broken_schema.json") 'sha256' | should -be "f3e5082e366006c317d9426e590623254cb1ce23d4f70165afed340b03ce333b"
        compute_hash (join-path "$working_dir" "broken_wget.json") 'sha256' | should -be "da658987c3902658c6e754bfa6546dfd084aaa2c3ae25f1fd8aa4645bc9cae24"
    }

    it 'computes SHA-512 correctly' {
        compute_hash (join-path "$working_dir" "invalid_wget.json") 'sha512' | should -be "7a7b82ec17547f5ec13dc614a8cec919e897e6c344a6ce7d71205d6f1c3aed276c7b15cbc69acac8207f72417993299cef36884e1915d56758ea09efa2259870"
        compute_hash (join-path "$working_dir" "wget.json") 'sha512' | should -be "216ebf07bb77062b51420f0f5eb6b7a94d9623d1d41d36c833436058f41e39898f2aa48d7020711c0d8765d02b87ac2e6810f3f502636a6e6f47dc4b9aa02d17"
        compute_hash (join-path "$working_dir" "broken_schema.json") 'sha512' | should -be "8d3f5617517e61c33275eafea4b166f0a245ec229c40dea436173c354786bad72e4fd9d662f6ac2b9f3dd375c00815a07f10e12975eec1b12da7ba7db10f9c14"
        compute_hash (join-path "$working_dir" "broken_wget.json") 'sha512' | should -be "7b16a714491e91cc6daa5f90e700547fac4d62e1fcec8c4b78f5a2386e04e68a8ed68f27503ece9555904a047df8050b3f12b4f779c05b1e4d0156e6e2d8fdbb"
    }
}

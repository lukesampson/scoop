. "$psscriptroot\Scoop-TestLib.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\unix.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

$isUnix = is_unix

Describe 'Requirement function' -Tag 'Scoop' {
    It 'Test 7zip requirement' {
        Test-7zipRequirement @{ url = 'test.7z' } '64bit' | Should -BeTrue
        Test-7zipRequirement @{ installer = @{ type = 'nsis' } } '64bit' | Should -BeTrue
        Test-7zipRequirement @{ url = 'test.exe' } '64bit' | Should -BeFalse
        Test-7zipRequirement -File 'test.xz' | Should -BeTrue
        Test-7zipRequirement -File 'test.bin' | Should -BeFalse
    }
    It 'Test lessmsi requirement' {
        Mock get_config { $true }
        Test-LessmsiRequirement @{ url = 'test.msi'} '64bit' | Should -BeTrue
        Test-LessmsiRequirement @{ url = 'test.exe'} '64bit' | Should -BeFalse
    }
    It 'Test innounp requirement' {
        Test-InnounpRequirement @{ installer = @{ type = 'inno' } } '64bit' | Should -BeTrue
        Test-InnounpRequirement @{ } '64bit' | Should -BeFalse
    }
    It 'Test dark requirement' {
        Test-DarkRequirement @{ installer = @{ type = 'wix' } } '64bit' | Should -BeTrue
        Test-DarkRequirement @{ } '64bit' | Should -BeFalse
    }
}

Describe 'Decompression function' -Tag 'Scoop', 'Decompress' {
    BeforeAll {
        $working_dir = setup_working 'decompress'

        function test_extract($extract_fn, $from, $removal) {
            $to = (strip_ext $from) -replace '\.tar$', ''
            & $extract_fn ($from -replace '/', '\') ($to -replace '/', '\') -Removal:$removal
            return $to
        }

        It 'Decompression test cases should exist' {
            $testcases = "$working_dir\TestCases.zip"
            $testcases | Should -Exist
            compute_hash $testcases 'sha256' | Should -Be '695bb18cafda52644a19afd184b2545e9c48f1a191f7ff1efc26cb034587079c'
            if (!$isUnix) {
                Microsoft.Powershell.Archive\Expand-Archive $testcases $working_dir
            }
        }
    }

    Context '7zip extraction' {

        BeforeAll {
            if($env:CI) {
                mock Get-AppFilePath { (Get-Command 7z.exe).Path }
            } elseif(!(installed 7zip)) {
                scoop install 7zip
            }
            $test1 = "$working_dir\7ZipTest1.7z"
            $test2 = "$working_dir\7ZipTest2.tgz"
            $test3 = "$working_dir\7ZipTest3.tar.bz2"
            $test4 = "$working_dir\7ZipTest4.tar.gz"
        }

        It 'extract normal compressed file' -Skip:$isUnix {
            $to = test_extract 'Expand-7zipArchive' $test1
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1
        }

        It 'extract nested compressed file' -Skip:$isUnix {
            # file ext: tgz
            $to = test_extract 'Expand-7zipArchive' $test2
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1

            # file ext: tar.bz2
            $to = test_extract 'Expand-7zipArchive' $test3
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1
        }

        It 'extract nested compressed file with different inner name' -Skip:$isUnix {
            $to = test_extract 'Expand-7zipArchive' $test4
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1
        }

        It 'works with "-Removal" switch ($removal param)' -Skip:$isUnix {
            $test1 | Should -Exist
            test_extract 'Expand-7zipArchive' $test1 $true
            $test1 | Should -Not -Exist
        }
    }

    Context 'msi extraction' {

        BeforeAll {
            if($env:CI) {
                mock Get-AppFilePath { $env:lessmsi }
            } elseif(!(installed lessmsi)) {
                scoop install lessmsi
            }
            $test1 = "$working_dir\MSITest.msi"
            $test2 = "$working_dir\MSITestNull.msi"
        }

        It 'extract normal MSI file' -Skip:$isUnix {
            mock get_config { $false }
            $to = test_extract 'Expand-MsiArchive' $test1
            $to | Should -Exist
            "$to\MSITest\empty" | Should -Exist
            (Get-ChildItem "$to\MSITest").Count | Should -Be 1
        }

        It 'extract empty MSI file using lessmsi' -Skip:$isUnix {
            mock get_config { $true }
            $to = test_extract 'Expand-MsiArchive' $test2
            $to | Should -Exist
        }

        It 'works with "-Removal" switch ($removal param)' -Skip:$isUnix {
            mock get_config { $false }
            $test1 | Should -Exist
            test_extract 'Expand-MsiArchive' $test1 $true
            $test1 | Should -Not -Exist
        }
    }

    Context 'inno extraction' {

        BeforeAll {
            if($env:CI) {
                mock Get-AppFilePath { $env:innounp }
            } elseif(!(installed innounp)) {
                scoop install innounp
            }
            $test = "$working_dir\InnoTest.exe"
        }

        It 'extract Inno Setup file' -Skip:$isUnix {
            $to = test_extract 'Expand-InnoArchive' $test
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1
        }

        It 'works with "-Removal" switch ($removal param)' -Skip:$isUnix {
            $test | Should -Exist
            test_extract 'Expand-InnoArchive' $test $true
            $test | Should -Not -Exist
        }
    }

    Context 'zip extraction' {

        BeforeAll {
            $test = "$working_dir\ZipTest.zip"
        }

        It 'extract compressed file' -Skip:$isUnix {
            $to = test_extract 'Expand-ZipArchive' $test
            $to | Should -Exist
            "$to\empty" | Should -Exist
            (Get-ChildItem $to).Count | Should -Be 1
        }

        It 'works with "-Removal" switch ($removal param)' -Skip:$isUnix {
            $test | Should -Exist
            test_extract 'Expand-ZipArchive' $test $true
            $test | Should -Not -Exist
        }
    }
}

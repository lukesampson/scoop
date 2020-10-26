. "$psscriptroot\Scoop-TestLib.ps1"
. "$psscriptroot\..\lib\versions.ps1"

Describe 'versions comparison' -Tag 'Scoop' {
    Context 'semver compliant versions' {
        It 'handles major.minor.patch progressing' {
            Compare-Version '0.1.0' '0.1.1' | Should -Be 1
            Compare-Version '0.1.1' '0.2.0' | Should -Be 1
            Compare-Version '0.2.0' '1.0.0' | Should -Be 1
        }

        It 'handles pre-release versioning progression' {
            Compare-Version '0.4.0' '0.5.0-alpha.1' | Should -Be 1
            Compare-Version '0.5.0-alpha.1' '0.5.0-alpha.2' | Should -Be 1
            Compare-Version '0.5.0-alpha.2' '0.5.0-alpha.10' | Should -Be 1
            Compare-Version '0.5.0-alpha.10' '0.5.0-beta' | Should -Be 1
            Compare-Version '0.5.0-beta' '0.5.0-alpha.10' | Should -Be -1
            Compare-Version '0.5.0-beta' '0.5.0-beta.0' | Should -Be 1
        }

        It 'handles the pre-release tags in an alphabetic order' {
            Compare-Version '0.5.0-rc.1' '0.5.0-z' | Should -Be 1
            Compare-Version '0.5.0-rc.1' '0.5.0-howdy' | Should -Be -1
            Compare-Version '0.5.0-howdy' '0.5.0-rc.1' | Should -Be 1
        }
    }

    Context 'semver semi-compliant versions' {
        It 'handles Windows-styled major.minor.patch.build progression' {
            Compare-Version '0.0.0.0' '0.0.0.1' | Should -Be 1
            Compare-Version '0.0.0.1' '0.0.0.2' | Should -Be 1
            Compare-Version '0.0.0.2' '0.0.1.0' | Should -Be 1
            Compare-Version '0.0.1.0' '0.0.1.1' | Should -Be 1
            Compare-Version '0.0.1.1' '0.0.1.2' | Should -Be 1
            Compare-Version '0.0.1.2' '0.0.2.0' | Should -Be 1
            Compare-Version '0.0.2.0' '0.1.0.0' | Should -Be 1
            Compare-Version '0.1.0.0' '0.1.0.1' | Should -Be 1
            Compare-Version '0.1.0.1' '0.1.0.2' | Should -Be 1
            Compare-Version '0.1.0.2' '0.1.1.0' | Should -Be 1
            Compare-Version '0.1.1.0' '0.1.1.1' | Should -Be 1
            Compare-Version '0.1.1.1' '0.1.1.2' | Should -Be 1
            Compare-Version '0.1.1.2' '0.2.0.0' | Should -Be 1
            Compare-Version '0.2.0.0' '1.0.0.0' | Should -Be 1
        }

        It 'handles partial semver version differences' {
            Compare-Version '1' '1.1' | Should -Be 1
            Compare-Version '1' '1.0' | Should -Be 1
            Compare-Version '1.1.0.0' '1.1' | Should -Be -1
            Compare-Version '1.4' '1.3.0' | Should -Be -1
            Compare-Version '1.4' '1.3.255.255' | Should -Be -1
            Compare-Version '1.4' '1.4.4' | Should -Be 1
            Compare-Version '1.1.1_8' '1.1.1' | Should -Be -1
            Compare-Version '1.1.1b' '1.1.1a' | Should -Be -1
            Compare-Version '1.1.1a' '1.1.1b' | Should -Be 1
            Compare-Version '1.1a2' '1.1a3' | Should -Be 1
            Compare-Version '1.1.1a10' '1.1.1b1' | Should -Be 1
        }

        It 'handles dash-style versions' {
            Compare-Version '1.8.9' '1.8.5-1' | Should -Be -1
            Compare-Version '7.0.4-9' '7.0.4-10' | Should -Be 1
            Compare-Version '7.0.4-9' '7.0.4-8' | Should -Be -1
            Compare-Version '2019-01-01' '2019-01-02' | Should -Be 1
            Compare-Version '2019-01-02' '2019-01-01' | Should -Be -1
            Compare-Version '2018-01-01' '2019-01-01' | Should -Be 1
            Compare-Version '2019-01-01' '2018-01-01' | Should -Be -1
        }
        It 'handles post-release tagging ("+")' {
            Compare-Version '1' '1+hotfix.0' | Should -Be 1
            Compare-Version '1.0.0' '1.0.0+hotfix.0' | Should -Be 1
            Compare-Version '1.0.0+hotfix.0' '1.0.0+hotfix.1' | Should -Be 1
            Compare-Version '1.0.0+hotfix.1' '1.0.1' | Should -Be 1
            Compare-Version '1.0.0+1.1' '1.0.0+1' | Should -Be -1
        }
    }

    Context 'other misc versions' {
        It 'handles plain text string' {
            Compare-Version 'latest' '20150405' | Should -Be -1
            Compare-Version '0.5alpha' '0.5' | Should -Be 1
            Compare-Version '0.5' '0.5Beta' | Should -Be -1
            Compare-Version '0.4' '0.5Beta' | Should -Be 1
        }

        It 'handles empty string' {
            Compare-Version '7.0.4-9' '' | Should -Be -1
        }

        It 'handles equal versions' {
            Compare-Version '12.0' '12.0' | Should -Be 0
            Compare-Version '7.0.4-9' '7.0.4-9' | Should -Be 0
            Compare-Version 'nightly-20190801' 'nightly' | Should -Be 0
        }
    }
}

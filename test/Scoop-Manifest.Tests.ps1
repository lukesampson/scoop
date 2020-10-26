param($bucketdir = "$psscriptroot\..\bucket\")
. "$psscriptroot\Scoop-TestLib.ps1"
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

describe -Tag 'Manifests' "manifest-validation" {
    beforeall {
        $working_dir = setup_working "manifest"
        $schema = "$psscriptroot/../schema.json"
        Add-Type -Path "$psscriptroot\..\supporting\validator\bin\Newtonsoft.Json.dll"
        Add-Type -Path "$psscriptroot\..\supporting\validator\bin\Newtonsoft.Json.Schema.dll"
        Add-Type -Path "$psscriptroot\..\supporting\validator\bin\Scoop.Validator.dll"
    }

    it "Scoop.Validator is available" {
        ([System.Management.Automation.PSTypeName]'Scoop.Validator').Type | should -be 'Scoop.Validator'
    }

    context "parse_json function" {
        it "fails with invalid json" {
            { parse_json "$working_dir\broken_wget.json" } | should -throw
        }
    }

    context "schema validation" {
        it "fails with broken schema" {
            $validator = new-object Scoop.Validator("$working_dir/broken_schema.json", $true)
            $validator.Validate("$working_dir/wget.json") | should -BeFalse
            $validator.Errors.Count | should -be 1
            $validator.Errors | select-object -First 1 | should -match "broken_schema.*(line 6).*(position 4)"
        }
        it "fails with broken manifest" {
            $validator = new-object Scoop.Validator($schema, $true)
            $validator.Validate("$working_dir/broken_wget.json") | should -BeFalse
            $validator.Errors.Count | should -be 1
            $validator.Errors | select-object -First 1 | should -match "broken_wget.*(line 5).*(position 4)"
        }
        it "fails with invalid manifest" {
            $validator = new-object Scoop.Validator($schema, $true)
            $validator.Validate("$working_dir/invalid_wget.json") | should -BeFalse
            $validator.Errors.Count | should -be 16
            $validator.Errors | select-object -First 1 | should -match "Property 'randomproperty' has not been defined and the schema does not allow additional properties\."
            $validator.Errors | select-object -Last 1 | should -match "Required properties are missing from object: version\."
        }
    }

    context "manifest validates against the schema" {
        beforeall {
            if ($null -eq $bucketdir) {
                $bucketdir = "$psscriptroot\..\bucket\"
            }
            $changed_manifests = @()
            if($env:CI -eq $true) {
                $commit = if($env:APPVEYOR_PULL_REQUEST_HEAD_COMMIT) { $env:APPVEYOR_PULL_REQUEST_HEAD_COMMIT } else { $env:APPVEYOR_REPO_COMMIT }
                $changed_manifests = (Get-GitChangedFile -Include '*.json' -Commit $commit)
            }
            $manifest_files = Get-ChildItem $bucketdir *.json
            $validator = new-object Scoop.Validator($schema, $true)
        }

        $quota_exceeded = $false

        $manifest_files | ForEach-Object {
            $skip_manifest = ($changed_manifests -inotcontains $_.FullName)
            if($env:CI -ne $true -or $changed_manifests -imatch 'schema.json') {
                $skip_manifest = $false
            }
            it "$_" -skip:$skip_manifest {
                $file = $_ # exception handling may overwrite $_

                if(!($quota_exceeded)) {
                    try {
                        $validator.Validate($file.fullname)

                        if ($validator.Errors.Count -gt 0) {
                            write-host -f red "      [-] $_ has $($validator.Errors.Count) Error$(If($validator.Errors.Count -gt 1) { 's' })!"
                            write-host -f yellow $validator.ErrorsAsString
                        }
                        $validator.Errors.Count | should -be 0
                    } catch {
                        if($_.exception.message -like '*The free-quota limit of 1000 schema validations per hour has been reached.*') {
                            $quota_exceeded = $true
                            write-host -f darkyellow 'Schema validation limit exceeded. Will skip further validations.'
                        } else {
                            throw
                        }
                    }
                }

                $manifest = parse_json $file.fullname
                $url = arch_specific "url" $manifest "32bit"
                $url64 = arch_specific "url" $manifest "64bit"
                $urlarm64 = arch_specific "url" $manifest "arm64"
                if(!$url) {
                    $url = $urlarm64
                }

                if(!$url) {
                    $url = $url64
                }
                $url | should -not -benullorempty
            }
        }
    }
}

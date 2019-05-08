. "$psscriptroot\..\lib\core.ps1" | out-null
. "$psscriptroot\..\lib\help.ps1" | out-null
. "$psscriptroot\..\lib\config.ps1" | out-null
. "$psscriptroot\..\libexec\scoop-alias.ps1" | out-null

reset_aliases

describe "add_alias" -Tag 'Scoop' {
  mock shimdir { "TestDrive:\shim" }
  mock set_config { }
  mock get_config { @{} }

  $shimdir = shimdir
  mkdir $shimdir

  context "alias doesn't exist" {
    it "creates a new alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      $alias_file | should -not -exist

      add_alias "rm" '"hello, world!"'
      Invoke-Expression $alias_file | should -be "hello, world!"
    }
  }

  context "alias exists" {
    it "does not change existing alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      new-item $alias_file -type file
      $alias_file | should -exist

      add_alias "rm" "test"
      $alias_file | should -FileContentMatch ""
    }
  }
}

describe "rm_alias" {
  mock shimdir { "TestDrive:\shim" }
  mock set_config { }
  mock get_config { @{} }

  $shimdir = shimdir
  mkdir $shimdir

  context "alias exists" {
    it "removes an existing alias" {
      $alias_file = "$shimdir\scoop-rm.ps1"
      add_alias "rm" '"hello, world!"'

      $alias_file | should -exist
      mock get_config { @(@{"rm" = "scoop-rm"}) }

      rm_alias "rm"
      $alias_file | should -not -exist
    }
  }
}

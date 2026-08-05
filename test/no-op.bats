#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
}

@test "neither Gradle nor Maven build produces no artifacts and exits 0" {
  run "$SCRIPT"
  assert_success
  assert_no_file "$HOME/.gradle"
  assert_no_file pom.xml
}

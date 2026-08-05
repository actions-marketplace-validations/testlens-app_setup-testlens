#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
  GRADLE_HOME="$TEST_TMP/gradle-home"
  export GRADLE_USER_HOME="$GRADLE_HOME"
  GRADLE_ENV_PROPS="$GRADLE_HOME/init.d/testlens-env.properties"
  unset "${!GITHUB_@}" "${!RUNNER_@}"
}

@test "captures GITHUB_*, RUNNER_*, and JOB_CHECK_RUN_ID variables" {
  export GITHUB_REPOSITORY="octo/demo"
  export RUNNER_NAME="runner-7"
  export JOB_CHECK_RUN_ID="12345"
  run "$SCRIPT"
  assert_contains "$GRADLE_ENV_PROPS" "GITHUB_REPOSITORY=octo/demo"
  assert_contains "$GRADLE_ENV_PROPS" "RUNNER_NAME=runner-7"
  assert_contains "$GRADLE_ENV_PROPS" "JOB_CHECK_RUN_ID=12345"
}

@test "does not capture unrelated variables" {
  export SOME_OTHER_VAR="secret"
  run "$SCRIPT"
  assert_not_contains "$GRADLE_ENV_PROPS" "SOME_OTHER_VAR"
}

@test "backslashes in values are escaped" {
  export GITHUB_WORKSPACE='C:\work\repo'
  run "$SCRIPT"
  assert_contains "$GRADLE_ENV_PROPS" 'GITHUB_WORKSPACE=C:\\work\\repo'
}

@test "maven build also writes an env properties file with captured vars" {
  copy_fixture maven-single
  export GITHUB_REPOSITORY="octo/demo"
  run "$SCRIPT"
  assert_success
  local props
  props="$(grep -oE '<TESTLENS_ENV_PROPERTIES_FILE>[^<]+' pom.xml | head -1 | sed 's/.*>//')"
  assert_file "$props"
  assert_contains "$props" "GITHUB_REPOSITORY=octo/demo"
}

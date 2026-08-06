#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
  GRADLE_ENV_PROPS="$WORKDIR/.gradle/testlens-env.properties"
  MVN_ENV_PROPS="$WORKDIR/.mvn/testlens-env.properties"
  unset "${!GITHUB_@}" "${!RUNNER_@}"
}

@test "captures GITHUB_*, RUNNER_*, JOB_CHECK_RUN_ID, and TESTLENS_GITHUB_TOKEN variables" {
  echo "rootProject.name = 'demo'" > settings.gradle
  export GITHUB_REPOSITORY="octo/demo"
  export RUNNER_NAME="runner-7"
  export JOB_CHECK_RUN_ID="12345"
  export TESTLENS_GITHUB_TOKEN="some-token"
  run "$SCRIPT"
  assert_success
  assert_contains "$GRADLE_ENV_PROPS" "GITHUB_REPOSITORY=octo/demo"
  assert_contains "$GRADLE_ENV_PROPS" "RUNNER_NAME=runner-7"
  assert_contains "$GRADLE_ENV_PROPS" "JOB_CHECK_RUN_ID=12345"
  assert_contains "$GRADLE_ENV_PROPS" "TESTLENS_GITHUB_TOKEN=some-token"
}

@test "does not capture unrelated variables" {
  echo "rootProject.name = 'demo'" > settings.gradle
  export SOME_OTHER_VAR="secret"
  run "$SCRIPT"
  assert_not_contains "$GRADLE_ENV_PROPS" "SOME_OTHER_VAR"
}

@test "backslashes in values are escaped" {
  echo "rootProject.name = 'demo'" > settings.gradle
  export GITHUB_WORKSPACE='C:\work\repo'
  run "$SCRIPT"
  assert_contains "$GRADLE_ENV_PROPS" 'GITHUB_WORKSPACE=C:\\work\\repo'
}

@test "gradle init script resolves the env properties file at runtime, not a runner path" {
  echo "rootProject.name = 'demo'" > settings.gradle
  run "$SCRIPT"
  assert_success
  local init="$HOME/.gradle/init.d/testlens-init.gradle"
  assert_contains "$init" ".gradle/testlens-env.properties"
  # the runner-absolute path must not be baked in
  assert_not_contains "$init" "$WORKDIR/.gradle/testlens-env.properties"
}

@test "maven build writes the env properties file under .mvn and references it via a runtime property" {
  copy_fixture maven-single
  export GITHUB_REPOSITORY="octo/demo"
  run "$SCRIPT"
  assert_success
  assert_contains "$MVN_ENV_PROPS" "GITHUB_REPOSITORY=octo/demo"
  assert_contains pom.xml '<TESTLENS_ENV_PROPERTIES_FILE>${maven.multiModuleProjectDirectory}/.mvn/testlens-env.properties</TESTLENS_ENV_PROPERTIES_FILE>'
}

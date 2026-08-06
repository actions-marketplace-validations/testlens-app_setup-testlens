#!/usr/bin/env bats

load helpers
load node_modules/bats-support/load
load node_modules/bats-assert/load

setup() {
  _common_setup
  GRADLE_HOME="$TEST_TMP/gradle-home"
}

@test "detected via settings.gradle writes the init script" {
  echo "rootProject.name = 'demo'" > settings.gradle
  run "$SCRIPT"
  assert_success
  assert_file "$HOME/.gradle/init.d/testlens-init.gradle"
}

@test "detected via settings.gradle.kts writes the init script" {
  echo "rootProject.name = \"demo\"" > settings.gradle.kts
  run "$SCRIPT"
  assert_success
  assert_file "$HOME/.gradle/init.d/testlens-init.gradle"
}

@test "detected via GRADLE_USER_HOME with no settings script" {
  export GRADLE_USER_HOME="$GRADLE_HOME"
  run "$SCRIPT"
  assert_success
  assert_file "$GRADLE_HOME/init.d/testlens-init.gradle"
}

@test "not triggered when neither settings script nor GRADLE_USER_HOME is present" {
  run "$SCRIPT"
  assert_success
  assert_no_file "$HOME/.gradle/init.d/testlens-init.gradle"
}

@test "init script contains the requested instrumentation version" {
  export GRADLE_USER_HOME="$GRADLE_HOME"
  export INSTRUMENTATION_VERSION="9.9.9"
  run "$SCRIPT"
  assert_contains "$GRADLE_HOME/init.d/testlens-init.gradle" \
    "app.testlens:junit-platform-instrumentation:9.9.9"
}

@test "init script contains project id" {
  export TESTLENS_PROJECT_ID="octo/demo-repo"
  export GRADLE_USER_HOME="$GRADLE_HOME"
  run "$SCRIPT"
  local init="$GRADLE_HOME/init.d/testlens-init.gradle"
  assert_contains "$init" "'octo/demo-repo'"
}

@test "init script resolves the env properties file at runtime, not a runner-absolute path" {
  export GRADLE_USER_HOME="$GRADLE_HOME"
  run "$SCRIPT"
  local init="$GRADLE_HOME/init.d/testlens-init.gradle"
  assert_contains "$init" "new File(dir, '.gradle/testlens-env.properties')"
  assert_not_contains "$init" "$WORKDIR/.gradle/testlens-env.properties"
}

@test "token file contains the raw token" {
  export TESTLENS_GITHUB_TOKEN="some-token"
  export GRADLE_USER_HOME="$GRADLE_HOME"
  run "$SCRIPT"
  assert_file "$GRADLE_HOME/init.d/TESTLENS_GITHUB_TOKEN"
  assert_equal "$(cat "$GRADLE_HOME/init.d/TESTLENS_GITHUB_TOKEN")" "some-token"
}

@test "log-files switch is included in init script" {
  export GRADLE_USER_HOME="$GRADLE_HOME"
  export WRITE_LOG_FILES="true"
  run "$SCRIPT"
  assert_contains "$GRADLE_HOME/init.d/testlens-init.gradle" "equalsIgnoreCase('true')"
}

@test "session timeout is substituted into the init script when set" {
  export GRADLE_USER_HOME="$GRADLE_HOME"
  export SESSION_TIMEOUT_SECONDS="30"
  run "$SCRIPT"
  local init="$GRADLE_HOME/init.d/testlens-init.gradle"
  assert_contains "$init" "if (!'30'.empty)"
}

@test "windows backslash GRADLE_USER_HOME is converted to JVM style in the token path" {
  export RUNNER_OS="Windows"
  export GRADLE_USER_HOME='C:\gradle\home'
  run "$SCRIPT"
  assert_success
  assert_contains "C:/gradle/home/init.d/testlens-init.gradle" \
    "new File('C:/gradle/home/init.d/TESTLENS_GITHUB_TOKEN')"
}

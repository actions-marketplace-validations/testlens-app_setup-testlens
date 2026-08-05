#! /usr/bin/env bash
set -eo pipefail

escape_for_java_properties() {
  local value="$1"
  value=${value//\\/\\\\}
  printf '%s' "$value"
}

DETECTED=""

write_env_properties_file() {
  local properties_file="$1"
  mkdir -p "$(dirname "$properties_file")"
  {
    while IFS= read -r var_name; do
      printf '%s=%s\n' "$var_name" "$(escape_for_java_properties "${!var_name}")"
    done < <(printf '%s\n' "${!GITHUB_@}" "${!RUNNER_@}" "JOB_CHECK_RUN_ID" "TESTLENS_GITHUB_TOKEN" | sort -u)
  } > "$properties_file"
}

# Add Gradle init script
# Detect Gradle build based on env var, or presence the of settings script
if [[ -n "$GRADLE_USER_HOME" ]] || [[ -f settings.gradle ]] || [[ -f settings.gradle.kts ]]; then
  echo "Detected Gradle build; setting up TestLens Gradle init script"
  DETECTED="gradle"

  # set Gradle home to the default location if it was not set before, e.g. we detected the build
  # because of a settings script
  if [[ -z "$GRADLE_USER_HOME" ]]; then
    GRADLE_USER_HOME="$HOME/.gradle"
  fi

  # normalize file paths on windows
  if [[ "$RUNNER_OS" == "Windows" ]]; then
    # shellcheck disable=SC2001
    # SC2001: sed is intentionally used here over bash parameter expansion for readability,
    # as the bash equivalent `${VAR//\\//}` is visually ambiguous for backslash-to-slash substitution.
    GRADLE_USER_HOME=$(echo "$GRADLE_USER_HOME" | sed 's|\\|/|g')
  fi

  # write files required by TestLens
  write_env_properties_file "$PWD/.gradle/testlens-env.properties"
  mkdir -p "$GRADLE_USER_HOME/init.d"
  cat << EOF > "$GRADLE_USER_HOME"/init.d/testlens-init.gradle
gradle.beforeProject { project ->
  // Locate the env properties file relative to the build root as seen at runtime
  // so it resolves whether the build runs on the runner or in a container/VM.
  def rootDir = project.rootDir
  def envPropertiesFile = null
  for (def dir = rootDir; dir != null; dir = dir.parentFile) {
    def candidate = new File(dir, '.gradle/testlens-env.properties')
    if (candidate.isFile()) { envPropertiesFile = candidate; break }
  }
  if (envPropertiesFile != null) {
    def relativeBuildPath = envPropertiesFile.parentFile.parentFile.relativePath(rootDir)
    TestLensSetup.configure(project, relativeBuildPath, envPropertiesFile)
  }
}
final class TestLensSetup {
  static def configure(Project project, String relativeBuildPath, File envPropertiesFile) {
    project.plugins.withId('java') {
      project.testing.suites.configureEach {
        dependencies { runtimeOnly('app.testlens:junit-platform-instrumentation:$INSTRUMENTATION_VERSION') }
      }
    }
    project.tasks.withType(Test).configureEach { task ->
      def muteMarker = new File(task.temporaryDir, 'testlens-mute.marker')
      def logsDir = new File(task.temporaryDir, 'testlens-logs')
      def workUnitPath = task.path + (relativeBuildPath.isEmpty() ? '' : ' [' + relativeBuildPath + ']')
      task.environment('TESTLENS_PROJECT_ID', '$TESTLENS_PROJECT_ID')
      task.environment('TESTLENS_WORK_UNIT_PATH', workUnitPath)
      task.environment('TESTLENS_MUTE_MARKER_FILE', muteMarker.absolutePath)
      task.environment('TESTLENS_ENV_PROPERTIES_FILE', envPropertiesFile.absolutePath)
      if ('true'.equalsIgnoreCase('$WRITE_LOG_FILES')) {
        task.environment('TESTLENS_LOGS_DIR', logsDir.absolutePath)
      }
      if (!'$SESSION_TIMEOUT_SECONDS'.empty) {
        task.environment('TESTLENS_SESSION_TIMEOUT_SECONDS', '$SESSION_TIMEOUT_SECONDS')
      }
      task.filter.failOnNoMatchingTests = false
      if (task.hasProperty('failOnNoDiscoveredTests')) task.failOnNoDiscoveredTests = false
      task.addTestListener(new TestListener() {
        void beforeTest(TestDescriptor __) {}
        void afterTest(TestDescriptor __, TestResult ___) {}
        void beforeSuite(TestDescriptor __) {}
        void afterSuite(TestDescriptor __, TestResult ___) {
          if (muteMarker.isFile()) {
            task.outputs.doNotStoreInCache()
            muteMarker.delete()
          }
        }
      })
    }
  }
}
EOF
fi

# Patch Maven Parent POM
if [[ -f "pom.xml" ]]; then
  echo "Detected Maven build; patching pom.xml with TestLens profile"
  DETECTED="${DETECTED:+$DETECTED }maven"
  POM_FILE="pom.xml"
  # Writing into .mvn also pins ${maven.multiModuleProjectDirectory} to this directory,
  # even when Maven is invoked from a subdirectory.
  write_env_properties_file "$PWD/.mvn/testlens-env.properties"
  # shellcheck disable=SC2016
  # SC2016: Single-quoted `${project.build.directory}` is a Maven expression, not a shell variable - it must not be expanded.
  PROFILE_CONTENT="    <profile>
      <id>testlens</id>
      <activation>
        <!-- workaround for MNG-4917 -->
        <file><exists>.</exists></file>
      </activation>
      <dependencies>
        <dependency>
          <groupId>app.testlens</groupId>
          <artifactId>junit-platform-instrumentation</artifactId>
          <version>$INSTRUMENTATION_VERSION</version>
          <scope>test</scope>
        </dependency>
      </dependencies>
      <build>
        <plugins>
          <plugin>
            <artifactId>maven-surefire-plugin</artifactId>
            <configuration>
              <environmentVariables>
                <TESTLENS_PROJECT_ID>$TESTLENS_PROJECT_ID</TESTLENS_PROJECT_ID>
                <TESTLENS_WORK_UNIT_PATH>\${project.name}</TESTLENS_WORK_UNIT_PATH>
                <TESTLENS_ENV_PROPERTIES_FILE>\${maven.multiModuleProjectDirectory}/.mvn/testlens-env.properties</TESTLENS_ENV_PROPERTIES_FILE>
                <TESTLENS_LOGS_DIR>$(if [[ $WRITE_LOG_FILES = "true" ]]; then echo '${project.build.directory}/testlens-logs'; fi)</TESTLENS_LOGS_DIR>
                $(if [[ -n "$SESSION_TIMEOUT_SECONDS" ]]; then echo "<TESTLENS_SESSION_TIMEOUT_SECONDS>$SESSION_TIMEOUT_SECONDS</TESTLENS_SESSION_TIMEOUT_SECONDS>"; fi)
              </environmentVariables>
            </configuration>
          </plugin>
          <plugin>
            <artifactId>maven-failsafe-plugin</artifactId>
            <configuration>
              <environmentVariables>
                <TESTLENS_PROJECT_ID>$TESTLENS_PROJECT_ID</TESTLENS_PROJECT_ID>
                <TESTLENS_WORK_UNIT_PATH>\${project.name}</TESTLENS_WORK_UNIT_PATH>
                <TESTLENS_ENV_PROPERTIES_FILE>\${maven.multiModuleProjectDirectory}/.mvn/testlens-env.properties</TESTLENS_ENV_PROPERTIES_FILE>
                <TESTLENS_LOGS_DIR>$(if [[ $WRITE_LOG_FILES = "true" ]]; then echo '${project.build.directory}/testlens-logs'; fi)</TESTLENS_LOGS_DIR>
                $(if [[ -n "$SESSION_TIMEOUT_SECONDS" ]]; then echo "<TESTLENS_SESSION_TIMEOUT_SECONDS>$SESSION_TIMEOUT_SECONDS</TESTLENS_SESSION_TIMEOUT_SECONDS>"; fi)
              </environmentVariables>
            </configuration>
          </plugin>
        </plugins>
      </build>
    </profile>"
  CLOSING_PROFILES_TAG_LINE=$({ grep -n "</profiles>" "$POM_FILE" || true; } | tail -1 | cut -d: -f1)
  CLOSING_PROJECT_TAG_LINE=$({ grep -n "</project>" "$POM_FILE" || true; } | tail -1 | cut -d: -f1)
  if [ -n "$CLOSING_PROFILES_TAG_LINE" ]; then
    {
      head -n $((CLOSING_PROFILES_TAG_LINE - 1)) "$POM_FILE"
      echo "$PROFILE_CONTENT"
      tail -n +"$CLOSING_PROFILES_TAG_LINE" "$POM_FILE"
    } > "${POM_FILE}.tmp"
    mv "${POM_FILE}.tmp" "$POM_FILE"
  elif [ -n "$CLOSING_PROJECT_TAG_LINE" ]; then
    {
      head -n $((CLOSING_PROJECT_TAG_LINE - 1)) "$POM_FILE"
      echo ""
      echo "  <profiles>"
      echo "$PROFILE_CONTENT"
      echo "  </profiles>"
      tail -n +"$CLOSING_PROJECT_TAG_LINE" "$POM_FILE"
    } > "${POM_FILE}.tmp"
    mv "${POM_FILE}.tmp" "$POM_FILE"
  fi
fi

if [[ -z "$DETECTED" ]]; then
  echo "No Gradle or Maven build detected; TestLens setup skipped"
fi

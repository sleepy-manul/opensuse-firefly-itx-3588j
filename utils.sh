#!/usr/bin/env bash

# Logs a message to STDOUT or STDERR.
# Parameters:
# $1: log level (5 characters max), e.g. INFO, DEBUG, FATAL, ERROR, WARN, ...
# $2..$n : The message to log (will be concatenated)
function log() {
  local level
  level="$1"
  shift

  local text
  text="$*"

  output=$(printf "$(date --iso-8601=seconds) %7s $0: %s" "[${level}]" "${text}")
  echo "${output}"
}

# If the environment variable DEBUG is set to "1",
# log a debugging message.
function logDebug() {
  if [[ -v DEBUG && "$DEBUG" == 1 ]]; then
    log DEBUG "$*"
  fi
}

# log a regular message
function logInfo() {
  log INFO "$*"
}

# log a warning (to STDERR)
function logWarn() {
  log WARN "$*" > /dev/stderr
}

# logs a non-fatal error (to STDERR)
function logError() {
  log ERROR "$*" > /dev/stderr
}

# logs a fatal error (to STDERR). Does NOT automatically abort the program (use die() for that purpose)
function logFatal() {
  log FATAL "$*" > /dev/stderr
}

# Aborts the script if an error occurs from which we cannot recover
function die() {
  local message
  message=$1

  echo "[FATAL] $message"
  exit 1
}

# Compares to version numbers and evaluates ok (exit code 0) if the first is less-than or equal
# to the second.
function version_lte() {
    printf '%s\n' "$1" "$2" | sort -C -V
}

# Compares to version numbers and evaluates ok (exit code 0) if the first is less or equal
# to the second.
function version_lt() {
    version_lte "$1" "$2" && [[ "$1" != "$2" ]]
}
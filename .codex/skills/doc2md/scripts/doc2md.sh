#!/usr/bin/env bash
# CONVERT DOCUMENT TO MARKDOWN

set -o errexit  # ABORT ON NON-ZERO EXIT STATUS
set -o nounset  # TREAT UNSET VARIABLES AS AN ERROR AND EXIT
set -o pipefail # DON'T HIDE ERRORS WITHIN PIPES

readonly MARKITDOWN_VERSION="0.1.9" # https://github.com/microsoft/markitdown/releases

usage() {
  cat << EOF
Usage: $(basename "$0") INPUT_FILE [OUTPUT_FILE]

Convert a PDF, DOCX, XLSX, or XLS file to Markdown.
By default, replace the input extension with .md in the same directory.
Parent directories for an explicit output path are created as needed.
An existing output file is overwritten after a successful, non-empty conversion.

Examples:
  $(basename "$0") "Quarterly report.pdf"
  $(basename "$0") budget.xlsx summaries/budget.md
EOF
}

main() {
  handleOptions "$@"
  validateArguments "$@"
  convertDocument "$@"
}

handleOptions() {
  case "${1-}" in
    -h|--help) usage; exit 0 ;;
    *) ;;
  esac
}

validateArguments() {
  if (( $# < 1 || $# > 2 )) || [[ -z "${1}" ]]; then
    error "Invalid arguments. Provide an input file and optionally an output file"
    printf '\n' >&2
    usage >&2
    exit 2
  fi
}

convertDocument() (
  local inputFile="${1}"
  local outputFile="${2:-${inputFile%.*}.md}"

  validateDocument "${inputFile}"
  validateOutputPath "${inputFile}" "${outputFile}"

  local outputDirectory="."
  if [[ "${outputFile}" == */* ]]; then
    outputDirectory="${outputFile%/*}"
    outputDirectory="${outputDirectory:-/}"
  fi
  if [[ -n "${2-}" ]]; then
    mkdir -p -- "${outputDirectory}"
  fi

  local temporaryOutputFile
  temporaryOutputFile="$(mktemp -- "${outputDirectory}/.doc2md.XXXXXXXX")"
  local progressPid=""
  trap 'stopBackgroundJob "${progressPid}"; rm -f -- "${temporaryOutputFile}"' EXIT

  if [[ "${inputFile}" == -* ]]; then
    inputFile="./${inputFile}"
  fi

  local startTime="${SECONDS}"
  printf 'Converting %s…\n' "${inputFile}"
  reportProgress "${startTime}" &
  progressPid="$!"

  uvx --system-certs --from "markitdown[pdf,docx,xlsx,xls]==${MARKITDOWN_VERSION}" \
    markitdown "${inputFile}" -o "${temporaryOutputFile}" || {
    local conversionStatus="$?"
    error "Failed to convert '${inputFile}'"
    exit "${conversionStatus}"
  }

  stopBackgroundJob "${progressPid}"
  progressPid=""

  if [[ ! -s "${temporaryOutputFile}" ]]; then
    error "Conversion produced empty Markdown for '${inputFile}'"
    exit 1
  fi

  validateOutputPath "${inputFile}" "${outputFile}"
  mv -f -- "${temporaryOutputFile}" "${outputFile}"
  printf 'Saved %s (%ss)\n' "${outputFile}" "$((SECONDS - startTime))"
)

validateDocument() {
  local inputFile="${1}"

  if [[ ! -f "${inputFile}" || ! -r "${inputFile}" ]]; then
    error "Cannot read input file '${inputFile}'. Check the path and read permissions"
    exit 2
  fi

  case "${inputFile,,}" in *.pdf|*.docx|*.xlsx|*.xls) ;;
    *) error "Unsupported file extension for '${inputFile}'. Use a PDF, DOCX, XLSX, or XLS file"; exit 2 ;;
  esac

  if [[ ! -s "${inputFile}" ]]; then
    error "Input file '${inputFile}' is empty. Provide a file with content"
    exit 2
  fi

  if ! command -v uvx &>/dev/null; then
    error "Cannot find 'uvx' on PATH. Install uv from https://github.com/astral-sh/uv/releases and ensure 'uvx' is on PATH"
    exit 127
  fi
}

validateOutputPath() {
  local inputFile="${1}"
  local outputFile="${2}"

  if [[ -d "${outputFile}" || "${outputFile}" == */ ]]; then
    error "Output path '${outputFile}' points to a directory. Specify an output file path"
    exit 2
  fi

  if [[ "${outputFile}" -ef "${inputFile}" ]]; then
    error "Output path '${outputFile}' refers to the input file. Choose a different output path"
    exit 2
  fi
}

error() {
  local errorLabel="ERROR"
  if [[ -t 1 ]]; then
    errorLabel=$'\e[1;31m'"${errorLabel}"$'\e[0m'
  fi
  printf '[%s] %s\n' "${errorLabel}" "${1}" >&2
}

reportProgress() {
  local startTime="${1}"
  local timerPid=""
  trap 'exit 0' TERM
  trap 'stopBackgroundJob "${timerPid}"' EXIT

  while true; do
    sleep 10 &
    timerPid="$!"
    wait "${timerPid}"
    timerPid=""
    printf 'Still converting (%ss elapsed)…\n' "$((SECONDS - startTime))"
  done
}

stopBackgroundJob() {
  local pid="${1}"
  if [[ -n "${pid}" ]]; then
    kill "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi
}

main "$@"

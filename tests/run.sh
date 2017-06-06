#!/bin/bash

set -euo pipefail

readonly testdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
outfile=""
pid=-1

while getopts vo: opt; do
  case "$opt" in
    v) set -x ;;
    o) outfile="$OPTARG" ;;
  esac
done

outfile=${outfile:-$(mktemp /tmp/traceleft-test-cli-out-XXXXXX)}
declare -r outfile
readonly stampfile="$(mktemp /tmp/traceleft-test-cli-stamp-XXXXXX)"

function shutdown() {
  if [[ "${pid}" -ne -1 ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null || true
  fi
  rm -f "${outfile}"
  rm -f "${stampfile}"
}

trap shutdown EXIT

printf "Using outfile %s\n" "${outfile}"

# Make sure credentials are cached
sudo -l >/dev/null

for dir in "${testdir}"/*; do
    testname=$(basename "${dir}")
    testsource="${testdir}/${testname}/${testname}.c"
    testscript="${testdir}/${testname}/${testname}.script"
    testbinary="${testdir}/${testname}/${testname}"

    # Only directories starting with test_ contain our tests
    if [[ "${testname}" != test_* ]]; then
        continue
    fi

    # Try building tests if they don't exists
    if [[ ! -f "${testbinary}" ]]; then
        echo -e "\e[33m${testname} : Compiling tests..\e[39m"
        gcc -o "${testbinary}" "${testsource}"
    fi

    "${testdir}/${testname}/${testname}" "${stampfile}" &
    pid=$!
    disown

    status_line="Running ${testname} with PID: ${pid} "
    echo -n "${status_line}"

    testcommands="$(sed -e "s|%PID%|$pid|g" -e "s|%BASEDIR%|${testdir}/../|g" "${testscript}")"

    until [[ -f "${stampfile}" ]]; do sleep 1; done
    rm -f "${stampfile}"

    echo "${testcommands}" | sudo -E go run "${testdir}/cli.go" --quiet --outfile "${outfile}"

    kill -9 "${pid}" 2>/dev/null || true

    expected_output="$(sed -e "s|%PID%|$pid|g" "${testdir}/${testname}/expect.log")"

    if diff  --ignore-all-space <(printf "%s" "${expected_output}") "${outfile}"; then
        echo -e "\r${status_line}\t \t \e[32m[PASSED]\e[39m"
    else
        echo -e "\r${status_line}\t \t \e[31m[FAILED]\e[39m"
    fi
done

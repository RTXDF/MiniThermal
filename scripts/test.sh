#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p build
zsh scripts/test-instance-lock.sh
xcrun clang -Wall -Wextra -Werror -O1 -g -DMT_TESTING Sources/ThermalSMC.c Tests/test_smc.c -framework IOKit -framework CoreFoundation -o build/test-smc
build/test-smc

#!/bin/zsh
set -eu
project_dir="${0:A:h:h}"
cd "$project_dir"
mkdir -p build
xcrun swiftc -swift-version 5 -parse-as-library Sources/InstanceLock.swift Tests/test_instance_lock.swift -o build/test-instance-lock
build/test-instance-lock

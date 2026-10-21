#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -module-cache-path "$PWD/.build/modules" native/Git.swift tests/GitTests.swift -o .build/git-tests
.build/git-tests

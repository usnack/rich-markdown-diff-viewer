#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -module-cache-path "$PWD/.build/modules" native/Git.swift native/Comments.swift tests/CommentTests.swift -o .build/comment-tests
.build/comment-tests

#!/bin/sh
# Builds ./infonotch (needs Xcode or Command Line Tools: xcode-select --install)
set -e
cd "$(dirname "$0")"
swiftc -O main.swift -o infonotch -framework AppKit -framework IOKit
echo "Built ./infonotch  ->  run with: ./infonotch &"

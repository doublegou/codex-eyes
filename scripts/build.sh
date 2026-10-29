#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --configuration release --disable-sandbox

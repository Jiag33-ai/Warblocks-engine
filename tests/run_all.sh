#!/bin/sh
# Runs the engine-agnostic test suites under Lua 5.4 (code is kept Luau-compatible).
set -e
cd "$(dirname "$0")/.."
lua5.4 tests/test_core.lua
lua5.4 tests/test_world.lua

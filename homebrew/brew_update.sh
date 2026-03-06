#!/usr/bin/env bash
# Path to brew can vary depending on install
BREW_PATH=$(which brew)

$BREW_PATH update
$BREW_PATH upgrade
$BREW_PATH cleanup

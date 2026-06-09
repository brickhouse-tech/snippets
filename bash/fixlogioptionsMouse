#!/usr/bin/env bash

procs=(MacOS/logioptionsplus_agent MacOS/logioptionsplus$)

for proc in "${procs[@]}"; do
  pids=$(ps aux | grep "$proc" | grep -v grep | awk '{print $2}')
  if [[ -n "$pids" ]]; then
    kill -9 $pids
  fi
done

open -a "/Applications/logioptionsplus.app"

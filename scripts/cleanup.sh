#!/usr/bin/env bash

# kill our testrpc process running in the background
kill -9 $(lsof -n -i :8545)

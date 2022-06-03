#!/usr/bin/env bash

nix-shell --run 'dune build @doc'
echo "file://$(pwd)/_build/default/_doc/_html/tenderbatter/index.html"

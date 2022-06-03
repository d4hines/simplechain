#!/usr/bin/env bash

rm -f result
nix-shell --run 'dune build @fmt --auto-promote || true'

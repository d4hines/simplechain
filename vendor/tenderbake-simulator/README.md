# Tenderbake simulator

![Pipeline status](https://gitlab.com/nomadic-labs/tenderbake-simulator/badges/master/pipeline.svg)

This project implements a simulator to help write and test blockchain consensus algorithms
(without the details of actual blockchain systems) and the chief target is to help
with the development and testing of Tenderbake, described
in the paper [*Tenderbake—A Solution to Dynamic Repeated Consensus for Blockchains*][paper].

## Building \& Testing Consensus Algorithms

 * Please see the [User Guide][user-guide]! to write and test consensus algorithms
 * There is also a friendly tutorial in `/src/leader_election`

## Build With Opam

Install opam 2.0+ and then off you go:

```console
$ opam switch create 4.10.0
$ eval $(opam env)
$ opam install . --deps-only
$ eval $(opam env)
$ dune build ./src/bin/main.exe
$ dune exec ./src/bin/main.exe
$ # Or ... load interactively
$ cd src/emmy_plus ; dune utop
```

## Build With Nix

To build locally first install [Nix][nix]. Then execute from the root of the
repository:

```console
$ nix-build
```

This will automatically build all dependencies and the project. The command
also runs the tests.

## Development

It is recommended to install [direnv][direnv].

### Interactive development with OCaml LSP

* Emacs: use [`direnv-mode`][emacs-direnv] and [`lsp-mode`][lsp-mode]. With
  both modes enabled you will have an IDE experience in Emacs.

### Utop

Here is how to run `utop` (a REPL) for the project:

```console
$ nix-shell --run 'dune utop'
```

Or if you have enabled `direnv`:

```console
$ dune utop
```

### Documentation

To generate and view the documentation locally, run:

```console
$ ./docs.sh
```

OCaml's documentation syntax is described [here][ocaml-docs].

### Formatting

Formatting of many types of files is imposed by the CI. It is possible to
format everything by running the following command from the root of the
repository:

```console
$ ./format.sh
```

[paper]: https://arxiv.org/pdf/2001.11965.pdf
[nix]: https://nixos.org/
[direnv]: https://github.com/direnv/direnv
[emacs-direnv]: https://github.com/wbolster/emacs-direnv
[lsp-mode]: https://github.com/emacs-lsp/lsp-mode
[ocaml-docs]: http://caml.inria.fr/pub/docs/manual-ocaml/ocamldoc.html#s:ocamldoc-comments
[user-guide]: ./GUIDE.md

## License

The source code is distributed under the [MIT Open Source
License](https://opensource.org/licenses/MIT).

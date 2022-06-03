# User Guide

This user guide explains how to

1. write a consensus algorithm in the framework provided
2. run a simulation for various purposes (e.g., stress-testing properties like
   safety, running scenarios, reading logs, and so on)

# Preliminary Logistics: Building and running

The code that's actually run is in `./src/bin/main.ml` so calls to run simulations
should be in there.

The recommended way to build and run is to get [Nix][nix] and do this:

```console
$ nix-build
$ # Now to run:
$ ./result/bin/tenderbatter
```

To stick with dune (and still use nix) at the root of the repository do the following:

```console
$ nix-shell
$ dune build ./src/bin/main.exe
$ dune exec ./src/bin/main.exe
```

If you use [direnv][direnv] upon entering the root of the project, your
path will be already modified so there's no need to do `nix-shell`.

# Writing down a consensus algorithm

## Concise explanation of the framework

The system consists of a set of **node**s each with a unique **Node.Id.t**.
Each node has a **node_state** and there is a specific ADT for the messages that can be
sent between nodes, with the type named **message**.

From the perspective of a node, it sits around until it receives an **event**,
at a specific (float) **Time.t**, then processes the event to update its state, and produces
a new state and a list of **effects**. An event is either a wake up call for a
certain time (from the simulator or from the node to itself) or a message that is
received. An effect is either a "self wake-up" call for some future global time
**Time.t**, a message that is broadcast _to every node except itself_, or a
"shut down" message. It's important to note that the only communication
primitive is "broadcast to all other nodes but not myself".

All of the logic of a node is handled by an **event_handler**. We say
an **iteration** is each time a node handles an event.

The system is started by each node receiving a magical "wake up" event at time 0.
The system progresses by **iteration**s. Each iteration runs an event on a node, collects
the effects and converts them to events (adding network delays to messages) and inserts them
into a priority queue based on time of event. Events happen in order of a global time.

The network itself is modeled by a delay function which calculates the delay for a message
to be sent at some time from one node to another. It returns an `option` to represent
a failed delivery. The _default network model_ is _synchronous_ with a minimum delay of 0.1
seconds "added" to a normal distribution centered at 0.5 with standard deviation 0.15.

## Coding up a consensus algorithm

This section describes how to code up a consensus algorithm.
Basically, one should write a module perhaps at `./src/lib/my_consensus.ml`
which does these things:

1. Build a module named `Algorithm` of signature `Algorithm` as defined in `simulator.mli`
2. Include the instantiated functor `Make` by writing `include Simulator.Make (Algorithm)`
3. Write a function of type `My_consensus.event_handler`

```ocaml
(* Step 1 *)
module Algorithm = struct
 (* ... *)
end

(* Step 2 *)
include Simulator.Make (Algorithm)

(* Step 3 *)
let good_node : event_handler = (* ... *)
```

### How do I write the `Algorithm` module?

This module defines all the parameters/types for a certain consensus algorithm
(_though the algorithm itself is really just the event handler_).

The interface is defined in `simulator.mli` as

```ocaml
module type Algorithm = sig
  type message
  (** The type of messages that are exchanged over the network. *)

  val message_encoding : message Data_encoding.t
  (** [message] JSON encoding. *)

  type node_state
  (** Node state. *)

  type params
  (** Algorithm parameters. *)

  val params_encoding : params Data_encoding.t
  (** Algorithm parameters. *)

  val init_node_state : params -> Node.Id.t -> node_state
  (** The state in which every node starts in. *)

  val node_state_encoding : node_state Data_encoding.t
  (** [node_state] JSON encoding. *)
end
```

Remarks:

  * To log, hash, or digitally sign things we need a way to serialize values
  of the data type we work with. We accomplish that by using the
  well-documented json library (written by Nomadic Labs) called
  [`data-encoding`][data-encoding]. Hence, the `message` type, `node_state`
  and `params` have an encoding. (Internally, to sign we actually only need
  a binary serialization, but we're able to achieve this with a json
  encoding and the API in `data-encoding`.)
  * The `init_node_state` function provides `params` and a `Node.Id.t` which has
  the interface from `node.mli`.
  * Currently, to define a node state you need to define your own blockchain type.
  To help with doing this, you will probably need hashing and digital signatures
  for which we have an API (and descriptive comments) in `hash.mli`, `signature.mli`
  and `signed.mli`.

Example: in `ouroboros.ml`, we have

```ocaml
  type message = New_chain of Blockchain.t
  type node_state = { id : Node.Id.t; slot : int; chain : Blockchain.t }
  let init_node_state _ node_id = { id = node_id; slot = 0; chain = [] }
  type params = { total_nodes : int; slot_duration : float }
```

and the `Blockchain` is basically

```ocaml
  type transaction = int
  type block = { slot : int; transactions : transaction list }
```

### How do I write an `event_handler`?

After you write an `Algorithm` module, you call

```ocaml
include Simulator.Make (MyAlg)
```

and then you have the type `Simulator.event_handler` where the types basically
say everything:

```ocaml
module Make (A : Algorithm) : sig
  module Event : sig
    type t = Wake_up | Message_received of A.message
  end

  module Effect : sig
    type t = Set_wake_up_time of Time.t | Send_message of A.message | Shut_down
  end

  module Log :
    Logging.Log
      with type params = A.params
       and type event = Event.t
       and type state = A.node_state
       and type effect = Effect.t

  type event_handler =
    A.params ->                          (** Parameters to the algorithm *)
    Time.t ->                            (** Time an event occurs *)
    Event.t ->                           (** Event that occurs *)
    Signature.private_key ->             (** Private key of a node *)
    A.node_state ->                      (** Current node state *)
    Effect.t list * A.node_state         (** Pair of effects and updated state *)

  val run_simulation : (* ... *)
end
```

Note: For implementation reasons no node can get a private key itself, and the simulator
interface provides one. (Each public key is deterministic from the node's id.)

### Example: Ouroboros

A clean example is shown in `./src/lib/ouroboros.ml`.

# Running a simulation for stress-testing, scenarios, etc.

As of now, our current features are simply running a simulation, pretty printing the
events and examining the log.

## How to run a simulation

**Warning:** There are a few critical notes that could mess up a
simulation listed after the **"Critically,"**

Once instantiated the `Make` function in `simualtor.ml` provides

```ocaml
  type predicate =
    Time.t -> int -> (Node.Id.t * A.node_state) option array -> bool
  (** Given the current time, iteration that just occurred, and the state
     of the nodes, return a [bool]. *)

  val run_simulation :
    ?formatter:Format.formatter ->
    ?message_delay:Network.Delay.t ->
    ?seed:int ->
    ?predicates:(string * predicate) list ->
    params:A.params ->
    iterations:int ->
    nodes:(int * string * event_handler) list ->
    Log.t * system_state * (string * int option) list
```

where it is given

  * the formatter as a way for printing each iteration
  * a optional delay function that models the network conditions
    (defaulting to `Network.Delay.default`)
  * an integer seed for a pseudo random number generator
  * an association list of labeled predicates that must hold each iteration
  * the parameters to the consensus algorithm
  * the number of iterations to run
  * a list of triples each of which represent a group of nodes that all behave
    the same way with the same event handler (and have a string label)

and produces a tuple of

  * a log which represents a record of everything that happened,
  (again, parameterized by the `Algorithm`) which has an interface defined in
  `logging.mli`,
  * the final state of the system
  * and an association list of each predicate label with the least iteration on which it
  first failed (where `None` represents that it held for all iterations)

**Critically,**

  * The nodes are given int ids in a simple way. Given a list like
    `[(3, "a", h1); (2, "b", h2); (4, "c", h3)]` the nodes in the first
    group would have ids 0, 1, 2 ; in the second 3, 4; and in the third
    5,6,7,8,9;.
  * If the `Network.Delay.t` function is build from the API in `Network.Delay`, the user
    should avoid using the `Owl_base.Stats` module; without this, the network delays
    and hence simulations will not be deterministic.
  * A user-built `Network.Delay.t` should depend only on the state of the
    internal `Random.State.t` in the `Random` module for runs to be deterministic.
  * The predicates should not modify the array they are given or this will
    break the simulation.
  * The number of iterations defines the number of times the simulation calls
    some `event_handler`.

### Modeling A Network

To model a network, you create a `Network.delay_fn`.  This is documented in
`src/lib/network.mli`. See the above for how `int` ids are assigned to nodes
deterministically.

### Logging

The important parts of the logging interface are

```ocaml
  val pp : Format.formatter -> t -> unit
  (** Pretty print a log in human-friendly form. *)

  val save_to_file : t -> string -> unit
  (** Save a log to file. *)

  val load_from_file : string -> t
  (** Load a log from file. *)
```

### Example

If we called `include Simulator.Make (MyAlg)` in say `./src/lib/my_alg.ml`, then
we can write the simulation in `./src/bin/main.ml` thusly

```ocaml
open Tenderbatter
let good_node_group = (30, "good_node", My_alg.my_event_handler)
let byzantine_nodes = (10, "bad_node", Byzantine.my_alg_bad_event_handler)
let () =
  let log =
    My_alg.run_simulation ~formatter:Format.std_formatter
    ~iterations:10000 ~nodes:[good_node_group; byzantine_nodes]
  in
  My_alg.Log.save_to_file log "logfile.json"
```

## How to read the output or JSON log

The log is an object that has the parameters of the simulation, and then
entries which are a list of iterations in time order and execution order. Each
entry is an object that lists the `time`, the `event` occurring at a node, the
`init_state` of the node, and after the call the `new_state` of the node and
the `effects` it's event handler produces.

Here is a snippet of a log from running `ouroboros`:

```json
{
  "params": {
    "total_nodes": 4,
    "slot_duration": 1
  },
  "entries": [
    {
      "time": 0,
      "event": {
        "tag": "wake_up"
      },
      "init_state": {
        "id": {
          "i": 3,
          "label": "good_node"
        },
        "slot": 0,
        "chain": []
      },
      "new_state": {
        "id": {
          "i": 3,
          "label": "good_node"
        },
        "slot": 0,
        "chain": []
      },
      "effects": [
        {
          "tag": "wake_me_up_at",
          "time": 1
        }
      ]
    },
    {
      "time": 0,
      "event": {
        "tag": "wake_up"
      },
      "init_state": {
        "id": {
          "i": 2,
          "label": "good_node"
        },
        "slot": 0,
        "chain": []
      },
      "new_state": {
        "id": {
          "i": 2,
          "label": "good_node"
        },
        "slot": 0,
        "chain": []
      }
    }
  ]
}
```

The printed output is good for skimming:

```console
$ ./result/bin/tenderbatter
time: 0
event:
  tag: "wake_up"
init_state:
  id:
    i: 3
    label: "good_node"
  slot: 0
  chain: <empty list>
new_state:
  id:
    i: 3
    label: "good_node"
  slot: 0
  chain: <empty list>
effects:
  - tag: "wake_me_up_at"
    time: 1

time: 0
event:
  tag: "wake_up"
init_state:
  id:
    i: 2
    label: "good_node"
  slot: 0
  chain: <empty list>
new_state:
  id:
    i: 2
    label: "good_node"
  slot: 0
  chain: <empty list>
effects:
  - tag: "wake_me_up_at"
    time: 1
```

[data-encoding]: https://gitlab.com/nomadic-labs/data-encoding
[direnv]: https://github.com/direnv/direnv
[nix]: https://nixos.org/download.html

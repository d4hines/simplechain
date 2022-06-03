# Tenderbake

This guide aims to break down the Tenderbake consensus algorithm assuming no
prerequisites other than a basic knowledge of distributed systems. It is
intentionally verbose to serve as a useful TLDR for someone onboarding to
working on testing or tweaking Tenderbake.

## What is a blockchain consensus algorithm?

### A model of a distributed system

A distributed system is a set of processes/nodes that change over time. Each
process has a state and can send messages to other processes. The state of
the entire system is the state of each process and the set of all messages
in transit. Processes change state upon receiving a message or upon reaching
a certain time where some time-dependent condition is met.

The conditions that hold at all times are called safety conditions and the
conditions that hold at some future time are called liveness conditions.
Liveness conditions usually depend on messages arriving within a certain
delay. When we have a period of time with a predictable delay, this is
called a period of **synchrony**. When we have a time with unbounded delays,
these are **asynchronous** periods.

The specific model used here is defined in the [User guide].

### The General Problem Definition

Each node stores a list of transactions. Transactions are broken up into
chunks. These chunks are stored in a data structure called **block**, which
in addition to storing transactions, stores data specific to the consensus
algorithm. A node stores a list of blocks called **blockchain**. The index
of a block in the blockchain is its **level**.

Based on the particular algorithm, there are:

 * definition of a block type and blockchain
 * definition of node state type that holds a blockchain
   - initial state of each node
 * definition of a message sum type
   - this specifies all the messages that the nodes can exchange
 * blockchain definitions
   - some notion of when a block is valid and when a chain is valid
   - a function to check if a transaction is compatible with a list of other
     transactions, possibly stored in a blockchain

The blockchain consensus problem can be formulated like this:

 * There is a set of `n` nodes of which most behave according to an
   algorithm `P`, as **honest** nodes, and the rest deviate arbitrarily,
   i.e., are **byzantine** nodes
 * The algorithm `P` can be abstracted to be an event handler that
   - given `time`, a `message` or `wake_up`, the current `node_state`
   - produces a new `node_state` and a list of `message`s to broadcast to all
     other nodes except itself and possibly a self `wake_up_at_time t` or self
     `shut_down` call
 * If we run the system by giving each node a wake up call at time 0 and
   assume partial synchrony, i.e., alternating periods of asynchrony with
   synchrony, the algorithm `P` is correct iff it achieves the following
   - safety:
     * any two honest nodes have chains that "agree", either with **deterministic
       finality** where for some set prefix (e.g., dropping the first two blocks),
       one chain is a prefix of the other, or with **probabilistic finality**
       where there is some favorable probability that each chain minus, say,
       three of the top blocks, must have one be a prefix of the other
     * any honest (non-byzantine) node has a valid blockchain
     * any valid transaction obtained from an honest node "eventually"
       becomes part of the decided chain of that node
   - liveness:
     * in periods of synchrony, based on the number of nodes, each node's
       chain grows linearly with time, after some initial recovery period if
       this period of synchrony follows a period of asynchrony
     * in periods of synchrony, a valid transaction that appears to any node
       eventually becomes part of the chain of all nodes within some bound that
       is linear in the number of nodes

## The Tenderbake Algorithm

### Overview

There is a very nice overview of the algorithm in this [blog post]. To avoid
repeating that, we state just the main ideas here:

 * The algorithm proceeds by a subset of all nodes determining a block for each
   level, and this subset is called the **committee** per level. For each
   level, time is divided into a series of rounds and these continue until a
   node has decided on a block. For a given level, a node can be in one of
   three phases: propose, preendorse or endorse (and morally there is a fourth
   phase: decided). If all goes well, a node progresses through the propose to
   preendorse to endorse (to decided) phase.

   It is useful to think that each phase is indexed by a level and round. A
   node preendorsing at level 3 and round 2 is not in the same phase as a
   node preendorsing at level 4, round 3.

   From the perspective of a single node, it is at a certain level and
   round. It sends messages indexed by its level and round. It receives
   messages indexed by the sender's level and round. If it finds out that it
   is behind some better chain at a later level or round, it jumps forward.
   If it finds out some node is behind it, it helps that node catch up.

 * Nodes exchange 4 types of messages: **proposal** of a block, sending a
   **preendorsement** or **endorsement** for a block, or sending a
   **preendorsements** message that contains an observed PQC (see below).
   - A single node called the proposer proposes a block. However, in this
     model a node proposes an entire chain (to keep the messages simpler).
   - Other nodes see the propose message and send a preendorse message. When
     a node sees "enough" preendorse messages, it moves to collecting
     endorsements and calls this set a preendorsement quorum certificate or
     PQC and sends out an endorse message.
   - When a node sees "enough" endorsement messages, it calls this a EQC and
     decides on that block.
   - If the time elapses for a round in which EQC is not achieved, in the
     next round there is a new proposal (which if a PQC was seen for a
     block, is that same block) and nodes try in the following rounds to
     achieve a PQC and EQC.
   - Note: the "enough" above is `2f+1` if we have `3f+1` nodes total. Up to
     `f` nodes can exhibit byzantine behavior. We say the **quorum size** is
     the amount of votes we need to have a PQC or EQC.

 * Nodes keep track of “locked” and “endorsable” values. Nodes set the
   endorsable value when they observe a PQC themselves or get a valid
   preendorsements message with a PQC for some block. When a node observes a
   quorum of preendorsements, it endorses that block and sets it as the
   locked value. Locked and endorsable values are reset when the chain grows
   (with or without that block).

 * Nodes sync with each other by jumping forward or helping other nodes jump
   forward. Nodes jump forward by using a better proposed chain, or accepting
   a PQC in a preendorsements message (under certain conditions). Conversely,
   nodes help other nodes catch up by sending out a better proposed chain, or
   by sending out a PQC in a preendorsements message.

### The Key Types

Here are the key types gathered together for reference and heavily
commented:

```ocaml
  (* NODE STATE *)
  (**************)

  type node_state = {
    id : Node.Id.t;  (** The node's id. *)
    chain : block list;  (** The blockchain. *)
    proposal_state : proposal_state;  (** State of the current round. *)
    endorsable :
      (int * block_contents * preendorsement list) option;
        (** Endorsable round, block contents, preendorsement quorum certificate. *)
    locked :
      (int * block_contents * preendorsement list) option;
        (** Locked round, block content, preendorsement quorum certificate. *)
  }
  and proposal_state =
    | No_proposal  (** No proposal received in this round. *)
    | Collecting_preendorsements of { acc : preendorsement list }
        (** A proposal has been received. The node is collecting
       preendorsements. *)
    | Collecting_endorsements of {
        pqc : preendorsement list;
        acc : endorsement list;
      }

  (* MESSAGES *)
  (************)

  type message = unsigned_message Signed.t
  and unsigned_message = {
    level : int;
    round : int;
    previous_block_hash : Blockchain.block Hash.t option;
    payload : payload;
  }
  and payload =
    | Propose of Blockchain.t
    | Preendorse of Blockchain.preendorsement
    | Endorse of (Blockchain.endorsement * Blockchain.preendorsement list)
    | Preendorsements of (Blockchain.block * Blockchain.preendorsement list)

  (* BLOCKCHAIN *)
  (**************)

  type t = block list (* Block chain *)
  type block = {
    contents : block_contents;  (** Block payload *)
    round : int;  (** The round at which the block was created *)
    timestamp : Time.t;  (** Time when the block was created *)
    predecessor_eqc : endorsement list;
        (** Endorsement quorum certificate of the predecessor block. *)
    previously_proposed : (int * preendorsement list) option;
        (** Whether this block has been previously proposed. *)
  }
  and block_contents = {
    transactions : Transaction.t list;  (** Transactions in the block *)
    level : int;  (** The block's level *)
    predecessor_hash : block Hash.t option;  (** Predecessor block hash *)
  }
  and endorsement = Endorsement of block_contents Hash.t Signed.t
  and preendorsement = Preendorsement of block_contents Hash.t Signed.t
```

### The Algorithm

The algorithm progresses by each node starting in an initial state, being
given a wake up call at time 0 and then following the event handler
described below.

#### The Initial State

```ocaml
  let init_node_state _ node_id =
    {
      id = node_id;
      chain = [];
      proposal_state = No_proposal;
      endorsable = None;
      locked = None;
    }
```

#### Exposition of the event handler

Recall the structure of the event handler: it is given the current time, an
event (either a self wake-up or message) and its current state. It produces
a new state and a list of effects (which are messages to send or a new self
wake-up time).

Below we give a high level and intuitive view of the event handler.

 * Given a message
   - Proposal:
     * If the proposed chain and message is valid, and the chain is
       "better", we do the following (otherwise, do nothing and just keep
       the same state).
       * Update the state with the new chain
       * Change the next wake up to be in sync with the level and round of the
         new chain's head
       * Forget our previous endorsable and locked blocks if the chain grew in size
         (i.e., if this node was behind)
       * If we are not locked, change the proposal state to be collecting
         preendorsements for the current head, add a self-preendorsement
         (and an endorsement if 1 is the quorum size; in this case, change
         the proposal state to be endorsable) (**)
       * If we are locked on the head of the new chain, do as in (**)
       * If we are locked on a different block from the new head: if the
         proposed new head block was not previously proposed at this level,
         tell other nodes we have a pqc that we locked on for the head of
         the chain via a "preendorsements" message; if this new head was
         previously proposed, and it became endorsable after we locked, then
         just do as in (**), and if it was previously proposed but was
         endorsable at or before we locked, then send out "preendorsements".
   - Preendorse:
     * Check the message and preendorsement is valid, and matches the current chain.
     * If we are collecting preendorsements, add this one (otherwise, do nothing)
     * Check if we have a PQC, and if so
       * set the proposal state to be collecting endorsements
       * lock on and set the current head as endorsable
       * send an endorsement message and store a self-endorsement
   - Endorse:
     * Check if the endorsement and message is valid, and matches our chain. If
       not, do nothing. If everything checks out, add the endorsement to our
       collection (unless it is already there or we have a EQC).
   - Preendorsements:
     * Check the message and preendorsements are valid and match our chain's
       head
     * Set the state to be endorsable on the current head since a PQC has been
       observed (unless there is already an endorsable value of a later or same
       round)
 * Given a self "wake up"
   - If we are collecting endorsements, have an EQC, and are the proposer
     for the next level, make a new block and propose the new head.
   - Otherwise, just increment the round; note: in this case, the chain
     advances from eventually receiving a better chain from the proposer.

[User guide]: ../../GUIDE.md
[blog post]: https://blog.nomadic-labs.com/a-look-ahead-to-tenderbake.html

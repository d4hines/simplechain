# Emmy +

This README reviews the emmy + consensus algorithm and describes the outline
of how it is implemented in the present framework.

## Basic idea

The basic idea of emmy+ is to have each node bake after a certain delay and to
skew the delays according to the priority and number of endorsements a node has.
Namely, the higher a nodes priority and the higher it's number of endorsements, the
sooner it gets to bake.

## The Present Implementation

The given implementation essentially follows this design:

A block essentially has

 * `transactions : transaction list`
 * `priority : int` (priority at a certain level)
 * `endorsements : endorsement set` (endorsement for parent block)
 * `timestamp : float` (the float is wrapped in `Time.t`)
 * `level : int` (index in blockchain)

An endorsement has

 * `block : block Hash.t`
 * `level : int`

A party has

 * `id : int` (the `int` is wrapped in `Node.Id.t`)
 * `priority : int` (priority for the current level: the level of the chain head)
 * `endorsements : endorsement set`
 * `chain : (block Signed.t) list`

Each node responds to 3 events:

 1. Given a new signed endorsement (`x : endorsement Signed.t`)
   - If it's already stored, ignore it
   - Otherwise, check that it is a valid endorsement (i.e., that the signer
     is an endorser for the level of the current head block, and that it is
     signed correctly, and that it has a hash of the current head block) and
     store it
 2. Given a new chain
   - Check the chain is valid and longer. If so,
      - replace the current chain with it
      - set the priority with the level of the current head
      - set the endorsements to be empty
      - if the node is an endorser at this level, send an endorsement
       (and store its own endorsement)
 3. Given a wake up call
   - Set the next wake up call after `refresh_time` (passed as a parameter in
     `algo_params`). From the initial wake up at 0, each node checks if it should
     bake each `refresh_time` seconds.
   - Check if it is time to bake
      - if the chain is empty, check if we are past the delay from time 0
      - if the chain is not-empty, check if we are past the delay from the
       timestamp of the head
   - If it is time to bake, make a block with the current priority,
     endorsements, next level from current one and the current time
      - If the current node is an endorser at the level of the new chain,
        save its own endorsement

The cases above correspond directly to the code.

## Key notes

 * All nodes are considered endorsers
 * The `priority_fn`, `owner_fn` and `endorser_fn` determine what priority
   a node has at some level and whether it is an owner or endorser at a level
   given a priority.
   * The bakers are chosen as follows. At level l, the first in line is `l mod n`
     where `n` is the total number of nodes. The second in line is `(l+1) mod n`, and
     the third in line is `(l+2) mod n`, all the way to `(l+(n-1)) mod n`.
 * The `delay_fn` determines the delay for a given priority and endorsement count


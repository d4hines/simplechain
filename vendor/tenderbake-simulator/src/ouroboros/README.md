# Ouroboros

This README reviews the ouroboros consensus algorithm and describes the outline
of how it is implemented in the present framework.

## The Algorithm

The transition system breaks up time into slots and in each slot
one party is the owner who creates and distributes a block.

A block has
 * `slot : int`
 * `transactions : transaction list`

A party has
 * `id : int` (with the `int` wrapped in `Node.Id.t`)
 * `slot : int`
 * `chain : (block Signed.t) list`

Each node responds to two events:

 1. A new chain is received
   - check the chain is valid (i.e., each block is signed by the owner
     of the slot it has, the slots increase in time, and the head slot
     is at most the current slot)
   - if it is longer, replace the node's current chain
 2. A new time slot occurs
   - update the current slot
   - if this node is the owner of that time slot, bake a block, update its
     own chain and broadcast the new chain

## The Present Implementation

The node state, blockchain are as defined above. The `params` type holds
two parameters to the algorithm: the total number of nodes and the
duration of a slot (which must be larger than the max message delay).

The algorithm is translated into the given framework as follows
 * There is only one type of message: a new chain. Thus the only events are wake up
   events and slot increases.
 * Assuming a synchronous network with delay at most `d` seconds, and synchronized
   clocks, we have each `d` seconds be a time slot.
   This is the `params.slot_duration` type.
 * Nodes respond to two events:
   1. The new chain message
    - As stated before, we check the chain is valid and longer, and if so, update
       the current chain
   2. The wake up message.
    - Set the current time slot
    - Send another wake up message at `d` times the current slot plus one
    - This, according to the framework, is always given at time 0 to each node.
    - If we are the baker (selected round robin from node ids across slots via 
      modulo operations):
      * create a block
      * replace our chain with a new chain with it at the head
      * broadcast the new chain


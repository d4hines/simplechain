# Tutorial: leader election algorithm

This tutorial walks through how to use the framework with a very simple
consensus algorithm, namely, a simple leader election algorithm.

In a leader election algorithm, a collection of nodes aims to reach a state
where they are "decided" on the id of some fixed node called the leader.

## The Algorithm Presented

There are copious comments in `leader_election.ml` that walk through this algorithm:

 * Each node is in one of two states, "alive" or "decided". Each node knows the
   total number of nodes.
 * At the start, all nodes are "alive" and they each broadcast their id
 * When a node receives all the ids, it picks the largest one and goes into
   a decided state with the largest id.

## Safety

To demonstrate the use of predicates, we check a simple safety property:
all decided nodes have decided on the same value.


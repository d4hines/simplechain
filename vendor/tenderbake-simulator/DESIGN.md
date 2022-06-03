# Tenderbake simulator

## The initial version

The simulator will feature a flexible programming framework that will allow
us to model and observe evolution of a system that is made up from a
collection of nodes that exchange messages. The nodes are assumed to be
connected in some way so that in general every message from one node reaches
every node in the system unless the user specifies otherwise. We abstract
from network topology in the sense that there is no concrete graph of nodes
maintained in the system. However, for a particular pair of nodes there may
be information about the typical delay, and/or probability of a message
being lost, etc. provided by the user.

The system is initialized by a list of tuples that represent groups of
nodes. Each tuples contains: 1) number of replicas 2) **node label**
specific to the group 3) node **event handler**—a function that accepts a
message as an argument, possibly together with some metadata such as current
time. A **node** consists of some metadata which includes at least node's ID
and its event handler.

In the initial version of the simulator the **scheduler** will be
implemented manually. This is to be able to control it finely and instrument
it in order to force or replay a particular scenario. Roughly, the scheduler
maintains a **pool of messages** and is responsible for assigning network
delays per message-node pair. We call the action of a node receiving a
message and processing it an **event**. A single step of execution is then
consists of 1) finding the next event to execute, i.e. the closest event in
time 2) passing the message to the event handler of the node that receives
the message 3) injecting the messages that the event handler may have
produced in the pool of messages.

Every simulation is **deterministic** and can be reproduced. Every
simulation run is initialized with a random seed that will be fed to random
number generator and is used to make the system deterministic.

The simulator will include at least two modules that model consensus
algorithms: **Emmy+** and **Tenderbake**. Modules modeling other consensus
algorithms may be added in the future.

## Cryptography

Instead of real cryptographic functions we will use abstract modules for
hashing and public key cryptography. These modules will provide trivial
implementations that will model perfect cryptographic functions.

## Logging and tracing

The framework will feature a flexible logger that will register every event
in the system and can be used to analyze and replay scenarios of interest.

## Instrumentation of the scheduler

At a later stage we plan to add a way to give a set of rules that will skew
the scheduler in order to force a particular scenario and a family of
scenarios.

## Properties of the system

At a later stage we plan to add a language for formulating properties of the
system that should hold during executions. This will allow us to check,
among others, **safety** and **liveness**.

## Multi-threaded backend and future work

At a later stage we may implement a different backend that will use
**multi-threaded execution** instead of a manually written scheduler.

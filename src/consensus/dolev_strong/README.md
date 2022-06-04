# Dolev Strong Protocol

A synchronous protocol for authenticated byzantine broadcast. You can read about
it here: https://decentralizedthoughts.github.io/2019-12-22-dolev-strong/.

Note this paper uses "signature chains", but I based my implementation off the
[lectures by Tim Roughgarden](https://www.youtube.com/watch?v=QoUXml1NY7I&list=PLEGCF-WLh2RLOHv_xUGLqRts_9JxrckiA&index=9),
and, as best I can tell, his description doesn't use signature chains, just
sets.

The protocol is implemented in the module `Singleshot`. As Tim explains in
[lecture 2.2](https://www.youtube.com/watch?v=fJ5gCVWfCiQ&list=PLEGCF-WLh2RLOHv_xUGLqRts_9JxrckiA&index=7),
you can lift any byzantine broadcast algorithm into a state machine replication
algorithm (that could be used for e.g. a blockchain).

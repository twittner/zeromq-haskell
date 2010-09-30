This library provides Haskell bindings to zeromq (http://zeromq.org).

Current status
--------------

Version 0.4.1 - This software currently has *beta* status, i.e. it had
seen limited testing. Changes to its API may still happen.

This software was developed and tested on Linux 2.6.35 with GHC-6.12.3
using zeromq-2.0.9.

Installation
------------

As usual for Haskell packages this software is installed best via Cabal
(http://www.haskell.org/cabal). In addition to GHC it depends on 0MQ of course.

Usage
-----

The API mostly follows 0MQ's. Public functions are:

- `init`
- `term`
- `socket`
- `close`
- `setOption`
- `getOption`
- `subscribe`
- `unsubscribe`
- `bind`
- `connect`
- `send`
- `send'`
- `receive`
- `moreToReceive`
- `poll`

One difference to 0MQ's API is that sockets are parameterized types, i.e. there
is not one socket type but when creating a socket the desired socket type has
to be specified, e.g. `Pair` and the resulting socket is of type `Socket Pair`.
This additional type information is used to ensure that only options applicable
to the socket type can be set, hence `ZMQ_SUBSCRIBE` and `ZMQ_UNSUBSCRIBE` which 
only apply to `ZMQ_SUB` sockets have their own functions (`subscribe` and
`unsubscribe`) which can only be used with sockets of type `Socket Sub`.

Other differences are mostly for convenience. Also one does not deal directly
with 0MQ messages, instead these are created internally as needed.

Examples
--------

The test folder contains some simple tests mostly mimicking the ones that come
with 0MQ.


Bugs
----

If you find any bugs or other shortcomings I would greatly appreciate a bug
report, preferably via http://github.com/twittner/zeromq-haskell/issues or e-mail
to toralf.wittner@gmail.com


This library provides Haskell bindings to zeromq (http://zeromq.org).

Current status
--------------

This software currently has *beta* status, i.e. it had seen limited testing.

Version 0.8.3 - Derive Read in SocketOption and PollEvent.

Version 0.8.2 - Revert changes to support 0MQ 2.x as well as 3.x in a single
package. Instead git branches will be used to track the various 0MQ versions
and a separate zeromq-haskell-3 library will be released to hackage.
Also this releases handles EINTR properly in socket option setting/getting.

Version 0.8.1 - zmqVersion has been renamed to version and reports the
runtime version of 0MQ, instead of the compile time version macros.

Version 0.8.0 - zeromq-haskell can now be compiled either against 0MQ 2.x
(default) or 0MQ 3.x.

Version 0.7.1 - Removes unix dependency

Verison 0.7.0 - Changes semantics of poll to return a list of the same
length as it's parameter to allow identification of Sockets by index.
PollEvent gets another constructor None to denote the absence of polling
events.

Version 0.6.0 - This version renames "with" to "withContext" and
introduces a new "withSocket" resource wrapper. The API is otherwise
identical to 0.5.0

This software requires zeromq version 2.1.x.

Installation
------------

As usual for Haskell packages this software is installed best via Cabal
(http://www.haskell.org/cabal). In addition to GHC it depends on 0MQ of course.

Notes
-----

zeromq-haskell mostly follows 0MQ's API. One difference though is that sockets
are parameterized types, i.e. there is not one socket type but when creating a
socket the desired socket type has to be specified, e.g. `Pair` and the
resulting socket is of type `Socket Pair`.
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
report, preferably via http://github.com/twittner/zeromq-haskell/issues or
e-mail to toralf.wittner@gmail.com


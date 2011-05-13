{-# LANGUAGE ExistentialQuantification #-}
-- |
-- Module      : System.ZMQ
-- Copyright   : (c) 2010 Toralf Wittner
-- License     : MIT
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
--
-- 0MQ haskell binding. The API closely follows the C-API of 0MQ with
-- the main difference that sockets are typed.
-- The documentation of the individual socket types and socket options
-- is copied from 0MQ's man pages authored by Martin Sustrik.

module System.ZMQ (

    Size,
    Context,
    Socket,
    Flag(..),
    SocketOption(..),
    Poll(..),
    Timeout,
    PollEvent(..),
    Device(..),

    SType,
    SubsType,
    Pair(..),
    Pub(..),
    Sub(..),
    Req(..),
    Rep(..),
    XReq(..),
    XRep(..),
    Pull(..),
    Push(..),
    Up(..),
    Down(..),

    withContext,
    withSocket,
    setOption,
    getOption,
    System.ZMQ.subscribe,
    System.ZMQ.unsubscribe,
    bind,
    connect,
    send,
    send',
    receive,
    moreToReceive,
    poll,
    device,

    -- * Low-level functions
    init,
    term,
    socket,
    close,

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Control.Monad (unless, when)
import Data.IORef (atomicModifyIORef)
import Data.Int
import Data.Maybe
import System.ZMQ.Base
import qualified System.ZMQ.Base as B
import System.ZMQ.Internal
import Foreign hiding (with)
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import System.Mem.Weak (addFinalizer)
import System.Posix.Types (Fd(..))

import GHC.Conc (threadWaitRead, threadWaitWrite)

-- Socket types:

class SType a where
    zmqSocketType :: a -> ZMQSocketType

-- | Socket to communicate with a single peer. Allows for only a
-- single connect or a single bind. There's no message routing
-- or message filtering involved. /Compatible peer sockets/: 'Pair'.
data Pair = Pair
instance SType Pair where
    zmqSocketType = const pair

-- | Socket to distribute data. 'receive' function is not
-- implemented for this socket type. Messages are distributed in
-- fanout fashion to all the peers. /Compatible peer sockets/: 'Sub'.
data Pub = Pub
instance SType Pub where
    zmqSocketType = const pub

-- | Socket to subscribe for data. Send function is not implemented
-- for this socket type. Initially, socket is subscribed for no
-- messages. Use 'subscribe' to specify which messages to subscribe for.
-- /Compatible peer sockets/: 'Pub'.
data Sub = Sub
instance SType Sub where
    zmqSocketType = const sub

-- | Socket to send requests and receive replies. Requests are
-- load-balanced among all the peers. This socket type allows only an
-- alternated sequence of send's and recv's.
-- /Compatible peer sockets/: 'Rep', 'Xrep'.
data Req = Req
instance SType Req where
    zmqSocketType = const request

-- | Socket to receive requests and send replies. This socket type
-- allows only an alternated sequence of receive's and send's. Each
-- send is routed to the peer that issued the last received request.
-- /Compatible peer sockets/: 'Req', 'XReq'.
data Rep = Rep
instance SType Rep where
    zmqSocketType = const response

-- | Special socket type to be used in request/reply middleboxes
-- such as zmq_queue(7).  Requests forwarded using this socket type
-- should be tagged by a proper prefix identifying the original requester.
-- Replies received by this socket are tagged with a proper postfix
-- that can be use to route the reply back to the original requester.
-- /Compatible peer sockets/: 'Rep', 'Xrep'.
data XReq = Xreq
instance SType XReq where
    zmqSocketType = const xrequest

-- | Special socket type to be used in request/reply middleboxes
-- such as zmq_queue(7).  Requests received using this socket are already
-- properly tagged with prefix identifying the original requester. When
-- sending a reply via XREP socket the message should be tagged with a
-- prefix from a corresponding request.
-- /Compatible peer sockets/: 'Req', 'Xreq'.
data XRep = Xrep
instance SType XRep where
    zmqSocketType = const xresponse

-- | A socket of type ZMQ_PULL is used by a pipeline node to receive
-- messages from upstream pipeline nodes. Messages are fair-queued from
-- among all connected upstream nodes. The zmq_send() function is not
-- implemented for this socket type.
data Pull = Pull
instance SType Pull where
    zmqSocketType = const pull

-- | A socket of type ZMQ_PUSH is used by a pipeline node to send messages
-- to downstream pipeline nodes. Messages are load-balanced to all connected
-- downstream nodes. The zmq_recv() function is not implemented for this
-- socket type.
--
-- When a ZMQ_PUSH socket enters an exceptional state due to having reached
-- the high water mark for all downstream nodes, or if there are no
-- downstream nodes at all, then any zmq_send(3) operations on the socket
-- shall block until the exceptional state ends or at least one downstream
-- node becomes available for sending; messages are not discarded.
data Push = Push
instance SType Push where
    zmqSocketType = const push

{-# DEPRECATED Up "Use Pull instead." #-}
-- | Socket to receive messages from up the stream. Messages are
-- fair-queued from among all the connected peers. Send function is not
-- implemented for this socket type. /Compatible peer sockets/: 'Down'.
data Up = Up
instance SType Up where
    zmqSocketType = const upstream

{-# DEPRECATED Down "Use Push instead." #-}
-- | Socket to send messages down stream. Messages are load-balanced
-- among all the connected peers. Send function is not implemented for
-- this socket type. /Compatible peer sockets/: 'Up'.
data Down = Down
instance SType Down where
    zmqSocketType = const downstream

-- Subscribable:

class SubsType a
instance SubsType Sub

-- | The option to set on 0MQ sockets (descriptions reproduced here from
-- zmq_setsockopt(3) (cf. man zmq_setsockopt for further details)).
--
--     [@HighWM@] High watermark for the message pipes associated with the
--     socket. The water mark cannot be exceeded. If the messages
--     don't fit into the pipe emergency mechanisms of the
--     particular socket type are used (block, drop etc.)
--     If HWM is set to zero, there are no limits for the content
--     of the pipe.
--     /Default/: 0
--
--     [@Swap@] Swap allows the pipe to exceed high watermark. However,
--     the data are written to the disk rather than held in the memory.
--     Until high watermark is exceeded there is no disk activity involved
--     though. The value of the option defines maximal size of the swap file.
--     /Default/: 0
--
--     [@Affinity@] Affinity defines which threads in the thread pool will
--     be used to handle newly created sockets. This way you can dedicate
--     some of the threads (CPUs) to a specific work. Value of 0 means no
--     affinity. Work is distributed fairly among the threads in the
--     thread pool. For non-zero values, the lowest bit corresponds to the
--     thread 1, second lowest bit to the thread 2 etc.  Thus, value of 3
--     means that from now on newly created sockets will handle I/O activity
--     exclusively using threads no. 1 and 2.
--     /Default/: 0
--
--     [@Identity@] Identity of the socket. Identity is important when
--     restarting applications. If the socket has no identity, each run of
--     the application is completely separated from other runs. However,
--     with identity application reconnects to existing infrastructure
--     left by the previous run. Thus it may receive messages that were
--     sent in the meantime, it shares pipe limits with the previous run etc.
--     /Default/: NULL
--
--     [@Rate@] This option applies only to sending side of multicast
--     transports (pgm & udp).  It specifies maximal outgoing data rate that
--     an individual sender socket can send.
--     /Default/: 100
--
--     [@RecoveryIVL@] This option applies only to multicast transports
--     (pgm & udp). It specifies how long can the receiver socket survive
--     when the sender is inaccessible.  Keep in mind that large recovery
--     intervals at high data rates result in very large  recovery  buffers,
--     meaning that you can easily overload your box by setting say 1 minute
--     recovery interval at 1Gb/s rate (requires 7GB in-memory buffer).
--     /Default/: 10
--
--     [@McastLoop@] This  option  applies only to multicast transports
--     (pgm & udp). Value of 1 means that the mutlicast packets can be
--     received on the box they were sent from. Setting the value to 0
--     disables the loopback functionality which can have negative impact on
--     the performance. If possible, disable the loopback in production
--     environments.
--     /Default/: 1
--
--     [@SendBuf@] Sets the underlying kernel transmit buffer size to the
--     specified size. See SO_SNDBUF POSIX socket option. Value of zero
--     means leaving the OS default unchanged.
--     /Default/: 0
--
--     [@ReceiveBuf@] Sets the underlying kernel receive buffer size to
--     the specified size. See SO_RCVBUF POSIX socket option. Value of
--     zero means leaving the OS default unchanged.
--     /Default/: 0
--
data SocketOption =
    HighWM          Word64 -- ^ ZMQ_HWM
  | Swap            Int64  -- ^ ZMQ_SWAP
  | Affinity        Word64 -- ^ ZMQ_AFFINITY
  | Identity        String -- ^ ZMQ_IDENTITY
  | Rate            Int64  -- ^ ZMQ_RATE
  | RecoveryIVL     Int64  -- ^ ZMQ_RECOVERY_IVL
  | RecoveryIVLMsec Int64  -- ^ ZMQ_RECOVERY_IVL_MSEC
  | McastLoop       Int64  -- ^ ZMQ_MCAST_LOOP
  | SendBuf         Word64 -- ^ ZMQ_SNDBUF
  | ReceiveBuf      Word64 -- ^ ZMQ_RCVBUF
  | FD              CInt   -- ^ ZMQ_FD
  | Events          Word32 -- ^ ZMQ_EVENTS
  | Linger          CInt   -- ^ ZMQ_LINGER
  | ReconnectIVL    CInt   -- ^ ZMQ_RECONNECT_IVL
  | Backlog         CInt   -- ^ ZMQ_BACKLOG
  deriving (Eq, Ord, Show)

-- | The events to wait for in poll (cf. man zmq_poll)
data PollEvent =
    In     -- ^ ZMQ_POLLIN (incoming messages)
  | Out    -- ^ ZMQ_POLLOUT (outgoing messages, i.e. at least 1 byte can be written)
  | InOut  -- ^ ZMQ_POLLIN | ZMQ_POLLOUT
  | Native -- ^ ZMQ_POLLERR
  deriving (Eq, Ord, Show)

-- | Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event to wait for.
data Poll =
    forall a. S (Socket a) PollEvent
  | F Fd PollEvent

-- | Type representing ZeroMQ devices, as used with zmq_device
data Device =
    Streamer  -- ^ ZMQ_STREAMER
  | Forwarder -- ^ ZMQ_FORWARDER
  | Queue     -- ^ ZMQ_QUEUE
  deriving (Eq, Ord, Show)

-- | Initialize a 0MQ context (cf. zmq_init for details).  You should
-- normally prefer to use 'with' instead.
init :: Size -> IO Context
init ioThreads = do
    c <- throwErrnoIfNull "init" $ c_zmq_init (fromIntegral ioThreads)
    return (Context c)

-- | Terminate a 0MQ context (cf. zmq_term).  You should normally
-- prefer to use 'with' instead.
term :: Context -> IO ()
term = throwErrnoIfMinus1_ "term" . c_zmq_term . ctx

-- | Run an action with a 0MQ context.  The 'Context' supplied to your
-- action will /not/ be valid after the action either returns or
-- throws an exception.
withContext :: Size -> (Context -> IO a) -> IO a
withContext ioThreads act =
  bracket (throwErrnoIfNull "c_zmq_init" $ c_zmq_init (fromIntegral ioThreads))
          (throwErrnoIfMinus1_ "c_zmq_term" . c_zmq_term)
          (act . Context)

-- | Run an action with a 0MQ socket. The socket will be closed after running
-- the supplied action even if an error occurs. The socket supplied to your
-- action will /not/ be valid after the action terminates.
withSocket :: SType a => Context -> a -> (Socket a -> IO b) -> IO b
withSocket c t = bracket (socket c t) close

-- | Create a new 0MQ socket within the given context. 'withSocket' provides
-- automatic socket closing and may be safer to use.
socket :: SType a => Context -> a -> IO (Socket a)
socket (Context c) t = do
  let zt = typeVal . zmqSocketType $ t
  s <- throwErrnoIfNull "socket" (c_zmq_socket c zt)
  sock@(Socket _ status) <- mkSocket s
  addFinalizer sock $ do
    alive <- atomicModifyIORef status (\b -> (False, b))
    when alive $ c_zmq_close s >> return () -- socket has not been closed yet
  return sock

-- | Close a 0MQ socket. 'withSocket' provides automatic socket closing and may
-- be safer to use.
close :: Socket a -> IO ()
close sock@(Socket _ status) = onSocket "close" sock $ \s -> do
  alive <- atomicModifyIORef status (\b -> (False, b))
  when alive $ throwErrnoIfMinus1_ "close" . c_zmq_close $ s

-- | Set the given option on the socket. Please note that there are
-- certain combatibility constraints w.r.t the socket type (cf. man
-- zmq_setsockopt).
--
-- Please note that subscribe/unsubscribe is handled with separate
-- functions.
setOption :: Socket a -> SocketOption -> IO ()
setOption s (HighWM o)          = setIntOpt s highWM o
setOption s (Swap o)            = setIntOpt s swap o
setOption s (Affinity o)        = setIntOpt s affinity o
setOption s (Identity o)        = setStrOpt s identity o
setOption s (Rate o)            = setIntOpt s rate o
setOption s (RecoveryIVL o)     = setIntOpt s recoveryIVL o
setOption s (RecoveryIVLMsec o) = setIntOpt s recoveryIVLMsec o
setOption s (McastLoop o)       = setIntOpt s mcastLoop o
setOption s (SendBuf o)         = setIntOpt s sendBuf o
setOption s (ReceiveBuf o)      = setIntOpt s receiveBuf o
setOption s (FD o)              = setIntOpt s filedesc o
setOption s (Events o)          = setIntOpt s events o
setOption s (Linger o)          = setIntOpt s linger o
setOption s (ReconnectIVL o)    = setIntOpt s reconnectIVL o
setOption s (Backlog o)         = setIntOpt s backlog o

-- | Get the given socket option by passing in some dummy value of
-- that option. The actual value will be returned. Please note that
-- there are certain combatibility constraints w.r.t the socket
-- type (cf. man zmq_setsockopt).
getOption :: Socket a -> SocketOption -> IO SocketOption
getOption s (HighWM _)          = HighWM <$> getIntOpt s highWM
getOption s (Swap _)            = Swap <$> getIntOpt s swap
getOption s (Affinity _)        = Affinity <$> getIntOpt s affinity
getOption s (Identity _)        = Identity <$> getStrOpt s identity
getOption s (Rate _)            = Rate <$> getIntOpt s rate
getOption s (RecoveryIVL _)     = RecoveryIVL <$> getIntOpt s recoveryIVL
getOption s (RecoveryIVLMsec _) = RecoveryIVLMsec <$> getIntOpt s recoveryIVLMsec
getOption s (McastLoop _)       = McastLoop <$> getIntOpt s mcastLoop
getOption s (SendBuf _)         = SendBuf <$> getIntOpt s sendBuf
getOption s (ReceiveBuf _)      = ReceiveBuf <$> getIntOpt s receiveBuf
getOption s (FD _)              = FD <$> getIntOpt s filedesc
getOption s (Events _)          = Events <$> getIntOpt s events
getOption s (Linger _)          = Linger <$> getIntOpt s linger
getOption s (ReconnectIVL _)    = ReconnectIVL <$> getIntOpt s reconnectIVL
getOption s (Backlog _)         = Backlog <$> getIntOpt s backlog

-- | Subscribe Socket to given subscription.
subscribe :: SubsType a => Socket a -> String -> IO ()
subscribe s = setStrOpt s B.subscribe

-- | Unsubscribe Socket from given subscription.
unsubscribe :: SubsType a => Socket a -> String -> IO ()
unsubscribe s = setStrOpt s B.unsubscribe

-- | Equivalent of ZMQ_RCVMORE, i.e. returns True if a multi-part
-- message currently being read has more parts to follow, otherwise
-- False.
moreToReceive :: Socket a -> IO Bool
moreToReceive s = getBoolOpt s receiveMore

-- | Bind the socket to the given address (zmq_bind)
bind :: Socket a -> String -> IO ()
bind sock str = onSocket "bind" sock $
    throwErrnoIfMinus1_ "bind" . withCString str . c_zmq_bind

-- | Connect the socket to the given address (zmq_connect).
connect :: Socket a -> String -> IO ()
connect sock str = onSocket "connect" sock $
    throwErrnoIfMinus1_ "connect" . withCString str . c_zmq_connect

-- | Send the given 'SB.ByteString' over the socket (zmq_send).
send :: Socket a -> SB.ByteString -> [Flag] -> IO ()
send sock val fls = bracket (messageOf val) messageClose $ \m ->
  onSocket "send" sock $ \s ->
    retry "send" (waitWrite sock) $
          c_zmq_send s (msgPtr m) (combine (NoBlock : fls))

-- | Send the given 'LB.ByteString' over the socket (zmq_send).
--   This is operationally identical to @send socket (Strict.concat
--   (Lazy.toChunks lbs)) flags@ but may be more efficient.
send' :: Socket a -> LB.ByteString -> [Flag] -> IO ()
send' sock val fls = bracket (messageOfLazy val) messageClose $ \m ->
  onSocket "send'" sock $ \s ->
    retry "send'" (waitWrite sock) $
          c_zmq_send s (msgPtr m) (combine (NoBlock : fls))

-- | Receive a 'ByteString' from socket (zmq_recv).
receive :: Socket a -> [Flag] -> IO (SB.ByteString)
receive sock fls = bracket messageInit messageClose $ \m ->
  onSocket "receive" sock $ \s -> do
    retry "receive" (waitRead sock) $
          c_zmq_recv_unsafe s (msgPtr m) (combine (NoBlock : fls))
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    SB.packCStringLen (data_ptr, fromIntegral size)

-- | Polls for events on the given 'Poll' descriptors. The input is a
-- pair of (`Poll`, token) pairs. Returns the list of tokens for which
-- an event occured (cf. zmq_poll).
poll :: [(Poll, a)] -> Timeout -> IO [(Poll, a)]
poll polls to = do
    let len = length polls
        zpolls  = map (createZMQPoll . fst) polls
    withArray zpolls $ \ptr -> do
        throwErrnoIfMinus1Retry_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        zpolls' <- peekArray len ptr        
        return $ map snd $ filter (isJust . toEvent . pRevents . fst) $ zip zpolls' polls
 where
    createZMQPoll :: Poll -> ZMQPoll
    createZMQPoll (S (Socket s _) e) =
        ZMQPoll s 0 (fromEvent e) 0
    createZMQPoll (F (Fd s) e) =
        ZMQPoll nullPtr (fromIntegral s) (fromEvent e) 0

    fromEvent :: PollEvent -> CShort
    fromEvent In     = fromIntegral . pollVal $ pollIn
    fromEvent Out    = fromIntegral . pollVal $ pollOut
    fromEvent InOut  = fromIntegral . pollVal $ pollInOut
    fromEvent Native = fromIntegral . pollVal $ pollerr

    toEvent :: CShort -> Maybe PollEvent
    toEvent e | e == (fromIntegral . pollVal $ pollIn)    = Just In
              | e == (fromIntegral . pollVal $ pollOut)   = Just Out
              | e == (fromIntegral . pollVal $ pollInOut) = Just InOut
              | e == (fromIntegral . pollVal $ pollerr)   = Just Native
              | otherwise                                 = Nothing

retry :: String -> IO () -> IO CInt -> IO ()
retry msg wait act = throwErrnoIfMinus1RetryMayBlock_ msg act wait

wait' :: (Fd -> IO ()) -> ZMQPollEvent -> Socket a -> IO ()
wait' w f s = do (FD fd) <- getOption s (FD undefined)
                 w (Fd fd)
                 (Events evs) <- getOption s (Events undefined)
                 unless (testev evs) $ wait' w f s
    where testev e = e .&. fromIntegral (pollVal f) /= 0

waitRead, waitWrite :: Socket a -> IO ()
waitRead = wait' threadWaitRead pollIn
waitWrite = wait' threadWaitWrite pollOut

-- | Launch a ZeroMQ device (zmq_device).
--
-- Please note that this call never returns.
device :: Device -> Socket a -> Socket b -> IO ()
device device' insock outsock =
  onSocket "device" insock $ \insocket ->
  onSocket "device" outsock $ \outsocket ->
    throwErrnoIfMinus1Retry_ "device" $
        c_zmq_device (fromDevice device') insocket outsocket
 where
    fromDevice :: Device -> CInt
    fromDevice Streamer  = fromIntegral . deviceType $ deviceStreamer
    fromDevice Forwarder = fromIntegral . deviceType $ deviceForwarder
    fromDevice Queue     = fromIntegral . deviceType $ deviceQueue


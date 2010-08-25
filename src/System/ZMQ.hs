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
    Up(..),
    Down(..),

    init,
    term,

    socket,
    close,
    setOption,
    System.ZMQ.subscribe,
    System.ZMQ.unsubscribe,
    bind,
    connect,
    send,
    send',
    receive,

    poll,

    device

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Monad (foldM_)
import Control.Exception
import Data.Int
import Data.Maybe
import System.ZMQ.Base
import qualified System.ZMQ.Base as B
import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB
import System.Posix.Types (Fd(..))

-- | A 0MQ context representation.
newtype Context = Context { ctx :: ZMQCtx }

-- | A 0MQ Socket.
newtype Socket a = Socket { sock :: ZMQSocket }

-- A 0MQ Message representation.
newtype Message = Message { msgPtr :: ZMQMsgPtr }

type Timeout = Int64
type Size    = Word

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

-- | Socket to receive messages from up the stream. Messages are
-- fair-queued from among all the connected peers. Send function is not
-- implemented for this socket type. /Compatible peer sockets/: 'Down'.
data Up = Up
instance SType Up where
    zmqSocketType = const upstream

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
    HighWM      Int64  -- ^ ZMQ_HWM
  | Swap        Int64  -- ^ ZMQ_SWAP
  | Affinity    Int64  -- ^ ZMQ_AFFINITY
  | Identity    String -- ^ ZMQ_IDENTITY
  | Rate        Word64 -- ^ ZMQ_RATE
  | RecoveryIVL Word64 -- ^ ZMQ_RECOVERY_IVL
  | McastLoop   Word64 -- ^ ZMQ_MCAST_LOOP
  | SendBuf     Word64 -- ^ ZMQ_SNDBUF
  | ReceiveBuf  Word64 -- ^ ZMQ_RCVBUF
  deriving (Eq, Ord, Show)

-- | Flags to apply on send operations (cf. man zmq_send)
--
-- [@NoBlock@] Send operation should be performed in non-blocking mode.
-- If it cannot be performed immediatley an error will be thrown (errno
-- is set to EAGAIN).
data Flag = NoBlock -- ^ ZMQ_NOBLOCK
          | SndMore -- ^ ZMQ_SNDMORE
  deriving (Eq, Ord, Show)

-- | The events to wait for in poll (cf. man zmq_poll)
data PollEvent =
    In    -- ^ ZMQ_POLLIN (incoming messages)
  | Out   -- ^ ZMQ_POLLOUT (outgoing messages, i.e. at least 1 byte can be written)
  | InOut -- ^ ZMQ_POLLIN | ZMQ_POLLOUT
  deriving (Eq, Ord, Show)

-- | Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event of wait for.
data Poll =
    forall a. S (Socket a) PollEvent
  | F Fd PollEvent

-- | Type representing ZeroMQ devices, as used with zmq_device
data Device =
    Streamer  -- ^ ZMQ_STREAMER
  | Forwarder -- ^ ZMQ_FORWARDER
  | Queue     -- ^ ZMQ_QUEUE
  deriving (Eq, Ord, Show)

-- | Initialize a 0MQ context (cf. zmq_init for details).
init :: Size -> IO Context
init ioThreads = do
    c <- throwErrnoIfNull "init" $ c_zmq_init (fromIntegral ioThreads)
    return (Context c)

-- | Terminate 0MQ context (cf. zmq_term).
term :: Context -> IO ()
term = throwErrnoIfMinus1_ "term" . c_zmq_term . ctx

-- | Create a new 0MQ socket within the given context.
socket :: SType a => Context -> a -> IO (Socket a)
socket (Context c) t =
    let zt = typeVal . zmqSocketType $ t
    in  Socket <$> throwErrnoIfNull "socket" (c_zmq_socket c zt)

-- | Close a 0MQ socket.
close :: Socket a -> IO ()
close = throwErrnoIfMinus1_ "close" . c_zmq_close . sock

-- | Set the given option on the socket. Please note that there are
-- certain combatibility constraints w.r.t the socket type (cf. man
-- zmq_setsockopt).
--
-- Please note that subscribe/unsubscribe is handled with separate
-- functions.
setOption :: Socket a -> SocketOption -> IO ()
setOption s (HighWM o)      = setIntOpt s highWM o
setOption s (Swap o)        = setIntOpt s swap o
setOption s (Affinity o)    = setIntOpt s affinity o
setOption s (Identity o)    = setStrOpt s identity o
setOption s (Rate o)        = setIntOpt s rate o
setOption s (RecoveryIVL o) = setIntOpt s recoveryIVL o
setOption s (McastLoop o)   = setIntOpt s mcastLoop o
setOption s (SendBuf o)     = setIntOpt s sendBuf o
setOption s (ReceiveBuf o)  = setIntOpt s receiveBuf o

-- | Subscribe Socket to given subscription.
subscribe :: SubsType a => Socket a -> String -> IO ()
subscribe s = setStrOpt s B.subscribe

-- | Unsubscribe Socket from given subscription.
unsubscribe :: SubsType a => Socket a -> String -> IO ()
unsubscribe s = setStrOpt s B.unsubscribe

-- | Bind the socket to the given address (zmq_bind)
bind :: Socket a -> String -> IO ()
bind (Socket s) str = throwErrnoIfMinus1_ "bind" $
    withCString str (c_zmq_bind s)

-- | Connect the socket to the given address (zmq_connect).
connect :: Socket a -> String -> IO ()
connect (Socket s) str = throwErrnoIfMinus1_ "connect" $
    withCString str (c_zmq_connect s)

-- | Send the given 'SB.ByteString' over the socket (zmq_send).
send :: Socket a -> SB.ByteString -> [Flag] -> IO ()
send (Socket s) val fls = bracket (messageOf val) messageClose $ \m ->
    throwErrnoIfMinus1_ "send" $ c_zmq_send s (msgPtr m) (combine fls)

-- | Send the given 'LB.ByteString' over the socket (zmq_send).
--   This is operationally identical to @send socket (Strict.concat
--   (Lazy.toChunks lbs)) flags@ but may be more efficient.
send' :: Socket a -> LB.ByteString -> [Flag] -> IO ()
send' (Socket s) val fls = bracket (messageOfLazy val) messageClose $ \m ->
    throwErrnoIfMinus1_ "send'" $ c_zmq_send s (msgPtr m) (combine fls)

-- | Receive a 'ByteString' from socket (zmq_recv).
receive :: Socket a -> [Flag] -> IO (SB.ByteString)
receive (Socket s) fls = bracket messageInit messageClose $ \m -> do
    throwErrnoIfMinus1Retry_ "receive" $ c_zmq_recv s (msgPtr m) (combine fls)
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    SB.packCStringLen (data_ptr, fromIntegral size)

-- | Polls for events on the given 'Poll' descriptors. Returns the
-- list of 'Poll' descriptors for which an event occured (cf. zmq_poll).
poll :: [Poll] -> Timeout -> IO [Poll]
poll fds to = do
    let len = length fds
        ps  = map createZMQPoll fds
    withArray ps $ \ptr -> do
        throwErrnoIfMinus1Retry_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        ps' <- peekArray len ptr
        createPoll ps' []
 where
    createZMQPoll :: Poll -> ZMQPoll
    createZMQPoll (S (Socket s) e) =
        ZMQPoll s 0 (fromEvent e) 0
    createZMQPoll (F (Fd s) e) =
        ZMQPoll nullPtr (fromIntegral s) (fromEvent e) 0

    createPoll :: [ZMQPoll] -> [Poll] -> IO [Poll]
    createPoll []     fd = return fd
    createPoll (p:pp) fd = do
        let s = pSocket p;
            f = pFd p;
            r = toEvent $ pRevents p
        if isJust r
            then createPoll pp (newPoll s f r:fd)
            else createPoll pp fd

    newPoll :: ZMQSocket -> CInt -> Maybe PollEvent -> Poll
    newPoll s 0 r = S (Socket s) (fromJust r)
    newPoll _ f r = F (Fd f) (fromJust r)

    fromEvent :: PollEvent -> CShort
    fromEvent In    = fromIntegral . pollVal $ pollIn
    fromEvent Out   = fromIntegral . pollVal $ pollOut
    fromEvent InOut = fromIntegral . pollVal $ pollInOut

    toEvent :: CShort -> Maybe PollEvent
    toEvent e | e == (fromIntegral . pollVal $ pollIn)    = Just In
              | e == (fromIntegral . pollVal $ pollOut)   = Just Out
              | e == (fromIntegral . pollVal $ pollInOut) = Just InOut
              | otherwise                                 = Nothing

-- | Launch a ZeroMQ device (zmq_device).
--
-- Please note that this call never returns.
device :: Device -> Socket a -> Socket b -> IO ()
device device' (Socket insocket) (Socket outsocket) =
    throwErrnoIfMinus1_ "device" $
        c_zmq_device (fromDevice device') insocket outsocket
 where
    fromDevice :: Device -> CInt
    fromDevice Streamer  = fromIntegral . deviceType $ deviceStreamer
    fromDevice Forwarder = fromIntegral . deviceType $ deviceForwarder
    fromDevice Queue     = fromIntegral . deviceType $ deviceQueue


-- internal helpers:

messageOf :: SB.ByteString -> IO Message
messageOf b = UB.unsafeUseAsCStringLen b $ \(cstr, len) -> do
    msg <- messageInitSize (fromIntegral len)
    data_ptr <- c_zmq_msg_data (msgPtr msg)
    copyBytes data_ptr cstr len
    return msg

messageOfLazy :: LB.ByteString -> IO Message
messageOfLazy lbs = do
    msg <- messageInitSize (fromIntegral len)
    data_ptr <- c_zmq_msg_data (msgPtr msg)
    let fn offset bs = UB.unsafeUseAsCStringLen bs $ \(cstr, str_len) -> do
        copyBytes (data_ptr `plusPtr` offset) cstr str_len
        return (offset + str_len)
    foldM_ fn 0 (LB.toChunks lbs)
    return msg
 where
    len = LB.length lbs

messageClose :: Message -> IO ()
messageClose (Message ptr) = do
    throwErrnoIfMinus1_ "messageClose" $ c_zmq_msg_close ptr
    free ptr

messageInit :: IO Message
messageInit = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInit" $ c_zmq_msg_init ptr
    return (Message ptr)

messageInitSize :: Size -> IO Message
messageInitSize s = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInitSize" $
        c_zmq_msg_init_size ptr (fromIntegral s)
    return (Message ptr)

setIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> b -> IO ()
setIntOpt (Socket s) (ZMQOption o) i = throwErrnoIfMinus1_ "setIntOpt" $
    bracket (newStablePtr i) freeStablePtr $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castStablePtrToPtr ptr)
                           (fromIntegral . sizeOf $ i)

setStrOpt :: Socket a -> ZMQOption -> String -> IO ()
setStrOpt (Socket s) (ZMQOption o) str = throwErrnoIfMinus1_ "setStrOpt" $
    withCStringLen str $ \(cstr, len) ->
        c_zmq_setsockopt s (fromIntegral o) (castPtr cstr) (fromIntegral len)

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag NoBlock = noBlock
toZMQFlag SndMore = sndMore

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . toZMQFlag) 0


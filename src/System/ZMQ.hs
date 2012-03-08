{-# LANGUAGE ExistentialQuantification #-}
-- |
-- Module      : System.ZMQ
-- Copyright   : (c) 2010-2011 Toralf Wittner
-- License     : MIT
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
--
-- 0MQ haskell binding. The API closely follows the C-API of 0MQ with
-- the main difference that sockets are typed.
-- The documentation of the individual socket types is copied from
-- 0MQ's man pages authored by Martin Sustrik. For details please
-- refer to http://api.zeromq.org

module System.ZMQ (

    Size
  , Context
  , Socket
  , Flag(..)
  , SocketOption(..)
  , Poll(..)
  , Timeout
  , PollEvent(..)

  , SType
  , SubsType
  , Pair(..)
  , Pub(..)
  , Sub(..)
  , Req(..)
  , Rep(..)
  , XReq(..)
  , XRep(..)
  , Dealer(..)
  , Router(..)
  , Pull(..)
  , Push(..)
  , Up(..)
  , Down(..)

  , withContext
  , withSocket
  , setOption
  , getOption
  , System.ZMQ.subscribe
  , System.ZMQ.unsubscribe
  , bind
  , connect
  , send
  , send'
  , receive
  , moreToReceive
  , poll
  , version

    -- * Low-level functions
  , init
  , term
  , socket
  , close

  , Device(..)
  , device

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Control.Monad (unless, when)
import Data.IORef (atomicModifyIORef)
import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import System.Posix.Types (Fd(..))
import System.ZMQ.Base
import qualified System.ZMQ.Base as B
import System.ZMQ.Internal

import GHC.Conc (threadWaitRead, threadWaitWrite)

-- | Socket types.
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
data XReq = XReq
instance SType XReq where
    zmqSocketType = const xrequest

data Dealer = Dealer
instance SType Dealer where
    zmqSocketType = const dealer

-- | Special socket type to be used in request/reply middleboxes
-- such as zmq_queue(7).  Requests received using this socket are already
-- properly tagged with prefix identifying the original requester. When
-- sending a reply via XREP socket the message should be tagged with a
-- prefix from a corresponding request.
-- /Compatible peer sockets/: 'Req', 'Xreq'.
data XRep = XRep
instance SType XRep where
    zmqSocketType = const xresponse

data Router = Router
instance SType Router where
    zmqSocketType = const router

-- | A socket of type Pull is used by a pipeline node to receive
-- messages from upstream pipeline nodes. Messages are fair-queued from
-- among all connected upstream nodes. The zmq_send() function is not
-- implemented for this socket type.
data Pull = Pull
instance SType Pull where
    zmqSocketType = const pull

-- | A socket of type Push is used by a pipeline node to send messages
-- to downstream pipeline nodes. Messages are load-balanced to all connected
-- downstream nodes. The zmq_recv() function is not implemented for this
-- socket type.
--
-- When a Push socket enters an exceptional state due to having reached
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

-- | Subscribable.
class SubsType a

instance SubsType Sub

-- | The option to set on 0MQ sockets (cf. zmq_setsockopt and zmq_getsockopt
-- manpages for details).
data SocketOption =
    Affinity        Word64    -- ^ ZMQ_AFFINITY
  | Backlog         CInt      -- ^ ZMQ_BACKLOG
  | Events          PollEvent -- ^ ZMQ_EVENTS
  | FD              CInt      -- ^ ZMQ_FD
  | Identity        String    -- ^ ZMQ_IDENTITY
  | Linger          CInt      -- ^ ZMQ_LINGER
  | Rate            Int64     -- ^ ZMQ_RATE
  | ReceiveBuf      Word64    -- ^ ZMQ_RCVBUF
  | ReceiveMore     Bool      -- ^ ZMQ_RCVMORE
  | ReconnectIVL    CInt      -- ^ ZMQ_RECONNECT_IVL
  | ReconnectIVLMax CInt      -- ^ ZMQ_RECONNECT_IVL_MAX
  | RecoveryIVL     Int64     -- ^ ZMQ_RECOVERY_IVL
  | SendBuf         Word64    -- ^ ZMQ_SNDBUF
  | HighWM          Word64    -- ^ ZMQ_HWM
  | McastLoop       Bool      -- ^ ZMQ_MCAST_LOOP
  | RecoveryIVLMsec Int64     -- ^ ZMQ_RECOVERY_IVL_MSEC
  | Swap            Int64     -- ^ ZMQ_SWAP
  deriving (Eq, Ord, Show, Read)

-- | The events to wait for in poll (cf. man zmq_poll)
data PollEvent =
    In     -- ^ ZMQ_POLLIN (incoming messages)
  | Out    -- ^ ZMQ_POLLOUT (outgoing messages, i.e. at least 1 byte can be written)
  | InOut  -- ^ ZMQ_POLLIN | ZMQ_POLLOUT
  | Native -- ^ ZMQ_POLLERR
  | None
  deriving (Eq, Ord, Show, Read)

-- | Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event to wait for.
data Poll =
    forall a. S (Socket a) PollEvent
  | F Fd PollEvent

-- | Set the given option on the socket. Please note that there are
-- certain combatibility constraints w.r.t the socket type (cf. man
-- zmq_setsockopt).
--
-- Please note that subscribe/unsubscribe is handled with separate
-- functions.
setOption :: Socket a -> SocketOption -> IO ()
setOption s (Affinity o)        = setIntOpt s affinity o
setOption s (Backlog o)         = setIntOpt s backlog o
setOption _ (Events _)          = return () -- NOP
setOption _ (FD _)              = return () -- NOP
setOption s (Identity o)        = setStrOpt s identity o
setOption s (Linger o)          = setIntOpt s linger o
setOption s (Rate o)            = setIntOpt s rate o
setOption s (ReceiveBuf o)      = setIntOpt s receiveBuf o
setOption _ (ReceiveMore _)     = return () -- NOP
setOption s (ReconnectIVL o)    = setIntOpt s reconnectIVL o
setOption s (ReconnectIVLMax o) = setIntOpt s reconnectIVLMax o
setOption s (RecoveryIVL o)     = setIntOpt s recoveryIVL o
setOption s (SendBuf o)         = setIntOpt s sendBuf o
setOption s (HighWM o)          = setIntOpt s highWM o
setOption s (McastLoop o)       = setBoolOpt s mcastLoop o
setOption s (RecoveryIVLMsec o) = setIntOpt s recoveryIVLMsec o
setOption s (Swap o)            = setIntOpt s swap o

-- | Get the given socket option by passing in some dummy value of
-- that option. The actual value will be returned. Please note that
-- there are certain combatibility constraints w.r.t the socket
-- type (cf. man zmq_setsockopt).
getOption :: Socket a -> SocketOption -> IO SocketOption
getOption s (Affinity _)        = Affinity <$> getIntOpt s affinity
getOption s (Backlog _)         = Backlog <$> getIntOpt s backlog
getOption s (Events _)          = Events . toEvent <$> getIntOpt s events
getOption s (FD _)              = FD <$> getIntOpt s filedesc
getOption s (Identity _)        = Identity <$> getStrOpt s identity
getOption s (Linger _)          = Linger <$> getIntOpt s linger
getOption s (Rate _)            = Rate <$> getIntOpt s rate
getOption s (ReceiveBuf _)      = ReceiveBuf <$> getIntOpt s receiveBuf
getOption s (ReceiveMore _)     = ReceiveMore <$> getBoolOpt s receiveMore
getOption s (ReconnectIVL _)    = ReconnectIVL <$> getIntOpt s reconnectIVL
getOption s (ReconnectIVLMax _) = ReconnectIVLMax <$> getIntOpt s reconnectIVLMax
getOption s (RecoveryIVL _)     = RecoveryIVL <$> getIntOpt s recoveryIVL
getOption s (SendBuf _)         = SendBuf <$> getIntOpt s sendBuf
getOption s (HighWM _)          = HighWM <$> getIntOpt s highWM
getOption s (McastLoop _)       = McastLoop <$> getBoolOpt s mcastLoop
getOption s (RecoveryIVLMsec _) = RecoveryIVLMsec <$> getIntOpt s recoveryIVLMsec
getOption s (Swap _)            = Swap <$> getIntOpt s swap

version :: IO (Int, Int, Int)
version =
    with 0 $ \major_ptr ->
    with 0 $ \minor_ptr ->
    with 0 $ \patch_ptr ->
        c_zmq_version major_ptr minor_ptr patch_ptr >>
        tupleUp <$> peek major_ptr <*> peek minor_ptr <*> peek patch_ptr
  where
    tupleUp a b c = (fromIntegral a, fromIntegral b, fromIntegral c)

-- | Initialize a 0MQ context (cf. zmq_init for details).  You should
-- normally prefer to use 'with' instead.
init :: Size -> IO Context
init ioThreads = do
    c <- throwErrnoIfNull "init" $ c_zmq_init (fromIntegral ioThreads)
    return (Context c)

-- | Terminate a 0MQ context (cf. zmq_term).  You should normally
-- prefer to use 'with' instead.
term :: Context -> IO ()
term = throwErrnoIfMinus1Retry_ "term" . c_zmq_term . ctx

-- | Run an action with a 0MQ context.  The 'Context' supplied to your
-- action will /not/ be valid after the action either returns or
-- throws an exception.
withContext :: Size -> (Context -> IO a) -> IO a
withContext ioThreads act =
  bracket (throwErrnoIfNull "c_zmq_init" $ c_zmq_init (fromIntegral ioThreads))
          (throwErrnoIfMinus1Retry_ "c_zmq_term" . c_zmq_term)
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
    throwErrnoIfNull "socket" (c_zmq_socket c zt) >>= mkSocket

-- | Close a 0MQ socket. 'withSocket' provides automatic socket closing and may
-- be safer to use.
close :: Socket a -> IO ()
close sock@(Socket _ status) = onSocket "close" sock $ \s -> do
  alive <- atomicModifyIORef status (\b -> (False, b))
  when alive $ throwErrnoIfMinus1_ "close" . c_zmq_close $ s

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
          c_zmq_recv s (msgPtr m) (combine (NoBlock : fls))
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    SB.packCStringLen (data_ptr, fromIntegral size)

-- | Polls for events on the given 'Poll' descriptors. Returns the
-- same list of 'Poll' descriptors with an "updated" 'PollEvent' field
-- (cf. zmq_poll). Sockets which have seen no activity have 'None' in
-- their 'PollEvent' field.
poll :: [Poll] -> Timeout -> IO [Poll]
poll fds to = do
    let len = length fds
        ps  = map createZMQPoll fds
    withArray ps $ \ptr -> do
        throwErrnoIfMinus1Retry_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        ps' <- peekArray len ptr
        return $ map createPoll (zip ps' fds)
 where
    createZMQPoll :: Poll -> ZMQPoll
    createZMQPoll (S (Socket s _) e) =
        ZMQPoll s 0 (fromEvent e) 0
    createZMQPoll (F (Fd s) e) =
        ZMQPoll nullPtr (fromIntegral s) (fromEvent e) 0

    createPoll :: (ZMQPoll, Poll) -> Poll
    createPoll (zp, S (Socket s t) _) =
        S (Socket s t) (toEvent . fromIntegral . pRevents $ zp)
    createPoll (zp, F fd _) =
        F fd (toEvent . fromIntegral . pRevents $ zp)

    fromEvent :: PollEvent -> CShort
    fromEvent In     = fromIntegral . pollVal $ pollIn
    fromEvent Out    = fromIntegral . pollVal $ pollOut
    fromEvent InOut  = fromIntegral . pollVal $ pollInOut
    fromEvent Native = fromIntegral . pollVal $ pollerr
    fromEvent None   = 0

toEvent :: Word32 -> PollEvent
toEvent e | e == (fromIntegral . pollVal $ pollIn)    = In
          | e == (fromIntegral . pollVal $ pollOut)   = Out
          | e == (fromIntegral . pollVal $ pollInOut) = InOut
          | e == (fromIntegral . pollVal $ pollerr)   = Native
          | otherwise                                 = None

retry :: String -> IO () -> IO CInt -> IO ()
retry msg wait act = throwErrnoIfMinus1RetryMayBlock_ msg act wait

wait' :: (Fd -> IO ()) -> ZMQPollEvent -> Socket a -> IO ()
wait' w f s = do
    fd <- getIntOpt s filedesc
    w (Fd fd)
    evs <- getIntOpt s events :: IO Word32
    unless (testev evs) $
        wait' w f s
  where
    testev e = e .&. fromIntegral (pollVal f) /= 0

waitRead, waitWrite :: Socket a -> IO ()
waitRead = wait' threadWaitRead pollIn
waitWrite = wait' threadWaitWrite pollOut

-- | Type representing ZeroMQ devices, as used with zmq_device
data Device =
    Streamer  -- ^ ZMQ_STREAMER
  | Forwarder -- ^ ZMQ_FORWARDER
  | Queue     -- ^ ZMQ_QUEUE
  deriving (Eq, Ord, Show)

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


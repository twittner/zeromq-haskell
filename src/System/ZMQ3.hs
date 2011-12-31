{-# LANGUAGE ExistentialQuantification #-}
-- |
-- Module      : System.ZMQ3
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

module System.ZMQ3 (

    Size
  , Context
  , Socket
  , Flag(..)
  , Poll(..)
  , Timeout
  , PollEvent(..)

  , SType
  , SubsType
  , Pair(..)
  , Pub(..)
  , Sub(..)
  , XPub(..)
  , XSub(..)
  , Req(..)
  , Rep(..)
  , XReq(..)
  , XRep(..)
  , Pull(..)
  , Push(..)

  , withContext
  , withSocket

  , System.ZMQ3.subscribe
  , System.ZMQ3.unsubscribe

  , System.ZMQ3.affinity
  , System.ZMQ3.backlog
  , System.ZMQ3.events
  , System.ZMQ3.fileDescriptor
  , System.ZMQ3.identity
  , System.ZMQ3.ipv4Only
  , System.ZMQ3.linger
  , System.ZMQ3.maxMessageSize
  , System.ZMQ3.mcastHops
  , System.ZMQ3.moreToReceive
  , System.ZMQ3.rate
  , System.ZMQ3.receiveBuffer
  , System.ZMQ3.receiveHighWM
  , System.ZMQ3.receiveTimeout
  , System.ZMQ3.reconnectInterval
  , System.ZMQ3.reconnectIntervalMax
  , System.ZMQ3.recoveryInterval
  , System.ZMQ3.sendBuffer
  , System.ZMQ3.sendHighWM
  , System.ZMQ3.sendTimeout

  , setAffinity
  , setBacklog
  , setIdentity
  , setLinger
  , setRate
  , setReceiveBuffer
  , setReconnectInterval
  , setReconnectIntervalMax
  , setRecoveryInterval
  , setSendBuffer
  , setIpv4Only
  , setMcastHops
  , setReceiveHighWM
  , setReceiveTimeout
  , setSendHighWM
  , setSendTimeout
  , setMaxMessageSize

  , bind
  , connect
  , send
  , send'
  , receive
  , poll
  , version

  , Data.Restricted.restrict
  , Data.Restricted.toRestricted

    -- * Low-level functions
  , init
  , term
  , socket
  , close

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Control.Monad (unless, when)
import Data.Restricted
import Data.IORef (atomicModifyIORef)
import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import System.Mem.Weak (addFinalizer)
import System.Posix.Types (Fd(..))
import System.ZMQ3.Base
import qualified System.ZMQ3.Base as B
import System.ZMQ3.Internal

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

-- | Same as 'Pub' except that you can receive subscriptions from the
-- peers in form of incoming messages. Subscription message is a byte 1
-- (for subscriptions) or byte 0 (for unsubscriptions) followed by the
-- subscription body.
-- /Compatible peer sockets/: 'Sub', 'XSub'.
data XPub = XPub
instance SType XPub where
    zmqSocketType = const xpub

-- | Same as 'Sub' except that you subscribe by sending subscription
-- messages to the socket. Subscription message is a byte 1 (for subscriptions)
-- or byte 0 (for unsubscriptions) followed by the subscription body.
-- /Compatible peer sockets/: 'Pub', 'XPub'.
data XSub = XSub
instance SType XSub where
    zmqSocketType = const xsub

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

-- | Special socket type to be used in request/reply middleboxes
-- such as zmq_queue(7).  Requests received using this socket are already
-- properly tagged with prefix identifying the original requester. When
-- sending a reply via XREP socket the message should be tagged with a
-- prefix from a corresponding request.
-- /Compatible peer sockets/: 'Req', 'Xreq'.
data XRep = XRep
instance SType XRep where
    zmqSocketType = const xresponse

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

-- | Subscribable.
class SubsType a

instance SubsType Sub

-- | The events to wait for in poll (cf. man zmq_poll)
data PollEvent =
    In     -- ^ ZMQ_POLLIN (incoming messages)
  | Out    -- ^ ZMQ_POLLOUT (outgoing messages, i.e. at least 1 byte can be written)
  | InOut  -- ^ ZMQ_POLLIN | ZMQ_POLLOUT
  | Native -- ^ ZMQ_POLLERR
  | None
  deriving (Eq, Ord, Show)

-- | Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event to wait for.
data Poll =
    forall a. S (Socket a) PollEvent
  | F Fd PollEvent

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

-- | Subscribe Socket to given subscription.
subscribe :: SubsType a => Socket a -> String -> IO ()
subscribe s = setStrOpt s B.subscribe

-- | Unsubscribe Socket from given subscription.
unsubscribe :: SubsType a => Socket a -> String -> IO ()
unsubscribe s = setStrOpt s B.unsubscribe

-- Read Only

-- | Cf. @zmq_getsockopt ZMQ_EVENTS@
events :: Socket a -> IO PollEvent
events s = toEvent <$> getIntOpt s B.events 0

-- | Cf. @zmq_getsockopt ZMQ_FD@
fileDescriptor :: Socket a -> IO Fd
fileDescriptor s = Fd . fromIntegral <$> getInt32Option B.filedesc s

-- | Cf. @zmq_getsockopt ZMQ_RCVMORE@
moreToReceive :: Socket a -> IO Bool
moreToReceive s = (== 1) <$> getInt32Option B.receiveMore s

-- Read

-- | Cf. @zmq_getsockopt ZMQ_IDENTITY@
identity :: Socket a -> IO String
identity s = getStrOpt s B.identity

-- | Cf. @zmq_getsockopt ZMQ_AFFINITY@
affinity :: Socket a -> IO Word64
affinity s = getIntOpt s B.affinity 0

-- | Cf. @zmq_getsockopt ZMQ_MAXMSGSIZE@
maxMessageSize :: Socket a -> IO Int64
maxMessageSize s = getIntOpt s B.maxMessageSize 0

-- | Cf. @zmq_getsockopt ZMQ_IPV4ONLY@
ipv4Only :: Socket a -> IO Bool
ipv4Only s = (== 1) <$> getInt32Option B.ipv4Only s

-- | Cf. @zmq_getsockopt ZMQ_BACKLOG@
backlog :: Socket a -> IO Int
backlog = getInt32Option B.backlog

-- | Cf. @zmq_getsockopt ZMQ_LINGER@
linger :: Socket a -> IO Int
linger = getInt32Option B.linger

-- | Cf. @zmq_getsockopt ZMQ_RATE@
rate :: Socket a -> IO Int
rate = getInt32Option B.rate

-- | Cf. @zmq_getsockopt ZMQ_RCVBUF@
receiveBuffer :: Socket a -> IO Int
receiveBuffer = getInt32Option B.receiveBuf

-- | Cf. @zmq_getsockopt ZMQ_RECONNECT_IVL@
reconnectInterval :: Socket a -> IO Int
reconnectInterval = getInt32Option B.reconnectIVL

-- | Cf. @zmq_getsockopt ZMQ_RECONNECT_IVL_MAX@
reconnectIntervalMax :: Socket a -> IO Int
reconnectIntervalMax = getInt32Option B.reconnectIVLMax

-- | Cf. @zmq_getsockopt ZMQ_RECOVERY_IVL@
recoveryInterval :: Socket a -> IO Int
recoveryInterval = getInt32Option B.recoveryIVL

-- | Cf. @zmq_getsockopt ZMQ_SNDBUF@
sendBuffer :: Socket a -> IO Int
sendBuffer = getInt32Option B.sendBuf

-- | Cf. @zmq_getsockopt ZMQ_MULTICAST_HOPS@
mcastHops :: Socket a -> IO Int
mcastHops = getInt32Option B.mcastHops

-- | Cf. @zmq_getsockopt ZMQ_RCVHWM@
receiveHighWM :: Socket a -> IO Int
receiveHighWM = getInt32Option B.receiveHighWM

-- | Cf. @zmq_getsockopt ZMQ_RCVTIMEO@
receiveTimeout :: Socket a -> IO Int
receiveTimeout = getInt32Option B.receiveTimeout

-- | Cf. @zmq_getsockopt ZMQ_SNDTIMEO@
sendTimeout :: Socket a -> IO Int
sendTimeout = getInt32Option B.sendTimeout

-- | Cf. @zmq_getsockopt ZMQ_SNDHWM@
sendHighWM :: Socket a -> IO Int
sendHighWM = getInt32Option B.sendHighWM

-- Write

-- | Cf. @zmq_setsockopt ZMQ_IDENTITY@
setIdentity :: Restricted N1 N254 String -> Socket a -> IO ()
setIdentity x s = setStrOpt s B.identity (rvalue x)

-- | Cf. @zmq_setsockopt ZMQ_AFFINITY@
setAffinity :: Word64 -> Socket a -> IO ()
setAffinity x s = setIntOpt s B.affinity x

-- | Cf. @zmq_setsockopt ZMQ_MAXMSGSIZE@
setMaxMessageSize :: Integral i => Restricted Nneg1 Int64 i -> Socket a -> IO ()
setMaxMessageSize x s = setIntOpt s B.maxMessageSize ((fromIntegral . rvalue $ x) :: Int64)

-- | Cf. @zmq_setsockopt ZMQ_IPV4ONLY@
setIpv4Only :: Bool -> Socket a -> IO ()
setIpv4Only True s  = setIntOpt s B.ipv4Only (1 :: CInt)
setIpv4Only False s = setIntOpt s B.ipv4Only (0 :: CInt)

-- | Cf. @zmq_setsockopt ZMQ_LINGER@
setLinger :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setLinger = setInt32OptFromRestricted B.linger

-- | Cf. @zmq_setsockopt ZMQ_RCVTIMEO@
setReceiveTimeout :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setReceiveTimeout = setInt32OptFromRestricted B.receiveTimeout

-- | Cf. @zmq_setsockopt ZMQ_SNDTIMEO@
setSendTimeout :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setSendTimeout = setInt32OptFromRestricted B.sendTimeout

-- | Cf. @zmq_setsockopt ZMQ_RATE@
setRate :: Integral i => Restricted N1 Int32 i -> Socket a -> IO ()
setRate = setInt32OptFromRestricted B.rate

-- | Cf. @zmq_setsockopt ZMQ_MULTICAST_HOPS@
setMcastHops :: Integral i => Restricted N1 Int32 i -> Socket a -> IO ()
setMcastHops = setInt32OptFromRestricted B.mcastHops

-- | Cf. @zmq_setsockopt ZMQ_BACKLOG@
setBacklog :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setBacklog = setInt32OptFromRestricted B.backlog

-- | Cf. @zmq_setsockopt ZMQ_RCVBUF@
setReceiveBuffer :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setReceiveBuffer = setInt32OptFromRestricted B.receiveBuf

-- | Cf. @zmq_setsockopt ZMQ_RECONNECT_IVL@
setReconnectInterval :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setReconnectInterval = setInt32OptFromRestricted B.reconnectIVL

-- | Cf. @zmq_setsockopt ZMQ_RECONNECT_IVL_MAX@
setReconnectIntervalMax :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setReconnectIntervalMax = setInt32OptFromRestricted B.reconnectIVLMax

-- | Cf. @zmq_setsockopt ZMQ_SNDBUF@
setSendBuffer :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setSendBuffer = setInt32OptFromRestricted B.sendBuf

-- | Cf. @zmq_setsockopt ZMQ_RECOVERY_IVL@
setRecoveryInterval :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setRecoveryInterval = setInt32OptFromRestricted B.recoveryIVL

-- | Cf. @zmq_setsockopt ZMQ_RCVHWM@
setReceiveHighWM :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setReceiveHighWM = setInt32OptFromRestricted B.receiveHighWM

-- | Cf. @zmq_setsockopt ZMQ_SNDHWM@
setSendHighWM :: Integral i => Restricted N0 Int32 i -> Socket a -> IO ()
setSendHighWM = setInt32OptFromRestricted B.sendHighWM

-- | Bind the socket to the given address (zmq_bind)
bind :: Socket a -> String -> IO ()
bind sock str = onSocket "bind" sock $
    throwErrnoIfMinus1_ "bind" . withCString str . c_zmq_bind

-- | Connect the socket to the given address (zmq_connect).
connect :: Socket a -> String -> IO ()
connect sock str = onSocket "connect" sock $
    throwErrnoIfMinus1_ "connect" . withCString str . c_zmq_connect

-- | Send the given 'SB.ByteString' over the socket (zmq_sendmsg).
send :: Socket a -> [Flag] -> SB.ByteString -> IO ()
send sock fls val = bracket (messageOf val) messageClose $ \m ->
  onSocket "send" sock $ \s ->
    retry "send" (waitWrite sock) $
          c_zmq_sendmsg s (msgPtr m) (combine (DontWait : fls))

-- | Send the given 'LB.ByteString' over the socket (zmq_sendmsg).
-- This is operationally identical to @send socket (Strict.concat
-- (Lazy.toChunks lbs)) flags@ but may be more efficient.
send' :: Socket a -> [Flag] -> LB.ByteString -> IO ()
send' sock fls val = bracket (messageOfLazy val) messageClose $ \m ->
  onSocket "send'" sock $ \s ->
    retry "send'" (waitWrite sock) $
          c_zmq_sendmsg s (msgPtr m) (combine (DontWait : fls))

-- | Receive a 'ByteString' from socket (zmq_recvmsg).
--
-- /Note/: This function always calls @zmq_recvmsg@ in a non-blocking way,
-- i.e. there is no need to provide the @ZMQ_DONTWAIT@ flag as this is used
-- by default. Still 'receive' is blocking the thread as long as no data
-- is available using GHC's 'threadWaitRead'.
receive :: Socket a -> IO (SB.ByteString)
receive sock = bracket messageInit messageClose $ \m ->
  onSocket "receive" sock $ \s -> do
    retry "receive" (waitRead sock) $
          c_zmq_recvmsg s (msgPtr m) (flagVal dontWait)
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
    fd <- getIntOpt s B.filedesc 0
    w (Fd fd)
    evs <- getInt32Option B.events s
    unless (testev evs) $
        wait' w f s
  where
    testev e = e .&. fromIntegral (pollVal f) /= 0

waitRead, waitWrite :: Socket a -> IO ()
waitRead = wait' threadWaitRead pollIn
waitWrite = wait' threadWaitWrite pollOut


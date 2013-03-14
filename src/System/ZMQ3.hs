{-# LANGUAGE GADTs #-}
-- |
-- Module      : System.ZMQ3
-- Copyright   : (c) 2010-2012 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable
--
-- 0MQ haskell binding. The API closely follows the C-API of 0MQ with
-- the main difference that sockets are typed.
-- The documentation of the individual socket types is copied from
-- 0MQ's man pages authored by Martin Sustrik. For details please
-- refer to <http://api.zeromq.org>
--
-- Differences to zeromq-haskell 2.x
--
-- /Socket Types/
--
-- * 'System.ZMQ.Up' and 'System.ZMQ.Down' no longer exist.
--
-- * 'XReq' is renamed to 'Dealer' and 'XRep' is renamed to 'Router'
-- (in accordance with libzmq). 'XReq' and 'XRep' are available as
-- deprecated aliases.
--
-- * Renamed type-classes:
-- @'SType' -\> 'SocketType'@, @'SubsType' -\> 'Subscriber'@.
--
-- * New type-classes:
-- 'Sender', 'Receiver'
--
-- /Socket Options/
--
-- Instead of a single 'SocketOption' data-type, getter and setter
-- functions are provided, e.g. one would write: @'affinity' sock@ instead of
-- @getOption sock (Affinity 0)@
--
-- /Restrictions/
--
-- Many option setters use a 'Restriction' to further constrain the
-- range of possible values of their integral types. For example
-- the maximum message size can be given as -1, which means no limit
-- or by greater values, which denote the message size in bytes. The
-- type of 'setMaxMessageSize' is therefore:
--
-- @setMaxMessageSize :: 'Integral' i => 'Restricted' 'Nneg1' 'Int64' i -> 'Socket' a -> 'IO' ()@
--
-- which means any integral value in the range of @-1@ to
-- (@'maxBound' :: 'Int64'@) can be given. To create a restricted
-- value from plain value, use 'toRestricted' or 'restrict'.
--
-- /Devices/
--
-- Devices are no longer present in 0MQ 3.x and consequently have been
-- removed form this binding as well.
--
-- /Error Handling/
--
-- The type 'ZMQError' is introduced, together with inspection functions 'errno',
-- 'source' and 'message'. @zmq_strerror@ is used underneath to retrieve the
-- correct error message. ZMQError will be thrown when native 0MQ procedures return
-- an error status and it can be 'catch'ed as an 'Exception'.

module System.ZMQ3 (

    -- * Type Definitions
    Size
  , Context
  , Socket
  , Flag (SendMore)
  , Switch (..)
  , Timeout
  , Event (..)
  , EventType (..)
  , EventMsg (..)
  , Poll (..)

    -- ** Type Classes
  , SocketType
  , Sender
  , Receiver
  , Subscriber

    -- ** Socket Types
  , Pair(..)
  , Pub(..)
  , Sub(..)
  , XPub(..)
  , XSub(..)
  , Req(..)
  , Rep(..)
  , Dealer(..)
  , Router(..)
  , XReq
  , XRep
  , Pull(..)
  , Push(..)

    -- * General Operations
  , withContext
  , withSocket
  , bind
  , unbind
  , connect
  , send
  , send'
  , sendMulti
  , receive
  , receiveMulti
  , version
  , monitor
  , poll

  , System.ZMQ3.subscribe
  , System.ZMQ3.unsubscribe

    -- * Context Options (Read)
  , ioThreads
  , maxSockets

    -- * Context Options (Write)
  , setIoThreads
  , setMaxSockets

    -- * Socket Options (Read)
  , System.ZMQ3.affinity
  , System.ZMQ3.backlog
  , System.ZMQ3.delayAttachOnConnect
  , System.ZMQ3.events
  , System.ZMQ3.fileDescriptor
  , System.ZMQ3.identity
  , System.ZMQ3.ipv4Only
  , System.ZMQ3.lastEndpoint
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
  , System.ZMQ3.tcpKeepAlive
  , System.ZMQ3.tcpKeepAliveCount
  , System.ZMQ3.tcpKeepAliveIdle
  , System.ZMQ3.tcpKeepAliveInterval

    -- * Socket Options (Write)
  , setAffinity
  , setBacklog
  , setDelayAttachOnConnect
  , setIdentity
  , setIpv4Only
  , setLinger
  , setMaxMessageSize
  , setMcastHops
  , setRate
  , setReceiveBuffer
  , setReceiveHighWM
  , setReceiveTimeout
  , setReconnectInterval
  , setReconnectIntervalMax
  , setRecoveryInterval
  , setRouterMandatory
  , setSendBuffer
  , setSendHighWM
  , setSendTimeout
  , setTcpAcceptFilter
  , setTcpKeepAlive
  , setTcpKeepAliveCount
  , setTcpKeepAliveIdle
  , setTcpKeepAliveInterval
  , setXPubVerbose

    -- * Restrictions
  , Data.Restricted.restrict
  , Data.Restricted.toRestricted

    -- * Error Handling
  , ZMQError
  , errno
  , source
  , message

    -- * Low-level Functions
  , init
  , term
  , context
  , destroy
  , socket
  , close
  , waitRead
  , waitWrite

    -- * Utils
  , proxy
) where

import Prelude hiding (init)
import qualified Prelude as P
import Control.Applicative
import Control.Exception
import Control.Monad (unless, void)
import Control.Monad.IO.Class
import Data.List (intersect, foldl')
import Data.Restricted
import Foreign hiding (throwIf, throwIf_, throwIfNull, void)
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import System.Posix.Types (Fd(..))
import System.ZMQ3.Base
import qualified System.ZMQ3.Base as B
import System.ZMQ3.Internal
import System.ZMQ3.Error

import GHC.Conc (threadWaitRead, threadWaitWrite)

-- | Socket to communicate with a single peer. Allows for only a
-- single connect or a single bind. There's no message routing
-- or message filtering involved. /Compatible peer sockets/: 'Pair'.
data Pair = Pair

-- | Socket to distribute data. 'receive' function is not
-- implemented for this socket type. Messages are distributed in
-- fanout fashion to all the peers. /Compatible peer sockets/: 'Sub'.
data Pub = Pub

-- | Socket to subscribe for data. 'send' function is not implemented
-- for this socket type. Initially, socket is subscribed for no
-- messages. Use 'subscribe' to specify which messages to subscribe for.
-- /Compatible peer sockets/: 'Pub'.
data Sub = Sub

-- | Same as 'Pub' except that you can receive subscriptions from the
-- peers in form of incoming messages. Subscription message is a byte 1
-- (for subscriptions) or byte 0 (for unsubscriptions) followed by the
-- subscription body.
-- /Compatible peer sockets/: 'Sub', 'XSub'.
data XPub = XPub

-- | Same as 'Sub' except that you subscribe by sending subscription
-- messages to the socket. Subscription message is a byte 1 (for subscriptions)
-- or byte 0 (for unsubscriptions) followed by the subscription body.
-- /Compatible peer sockets/: 'Pub', 'XPub'.
data XSub = XSub

-- | Socket to send requests and receive replies. Requests are
-- load-balanced among all the peers. This socket type allows only an
-- alternated sequence of send's and recv's.
-- /Compatible peer sockets/: 'Rep', 'Router'.
data Req = Req

-- | Socket to receive requests and send replies. This socket type
-- allows only an alternated sequence of receive's and send's. Each
-- send is routed to the peer that issued the last received request.
-- /Compatible peer sockets/: 'Req', 'Dealer'.
data Rep = Rep

-- | Each message sent is round-robined among all connected peers,
-- and each message received is fair-queued from all connected peers.
-- /Compatible peer sockets/: 'Router', 'Req', 'Rep'.
data Dealer = Dealer

-- | /Deprecated Alias/
type XReq = Dealer
{-# DEPRECATED XReq "Use Dealer" #-}

-- | When receiving messages a Router socket shall prepend a message
-- part containing the identity of the originating peer to
-- the message before passing it to the application. Messages
-- received are fair-queued from among all connected peers. When
-- sending messages a Router socket shall remove the first part of
-- the message and use it to determine the identity of the peer the
-- message shall be routed to. If the peer does not exist anymore
-- the message shall be silently discarded.
-- /Compatible peer sockets/: 'Dealer', 'Req', 'Rep'.
data Router = Router

-- | /Deprecated Alias/
type XRep = Router
{-# DEPRECATED XRep "Use Router" #-}

-- | A socket of type Pull is used by a pipeline node to receive
-- messages from upstream pipeline nodes. Messages are fair-queued from
-- among all connected upstream nodes. The zmq_send() function is not
-- implemented for this socket type.
data Pull = Pull

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

-- | Sockets which can 'subscribe'.
class Subscriber a

-- | Sockets which can 'send'.
class Sender a

-- | Sockets which can 'receive'.
class Receiver a

instance SocketType Pair where zmqSocketType = const pair
instance Sender     Pair
instance Receiver   Pair

instance SocketType Pub where zmqSocketType = const pub
instance Sender     Pub

instance SocketType Sub where zmqSocketType = const sub
instance Subscriber Sub
instance Receiver   Sub

instance SocketType XPub where zmqSocketType = const xpub
instance Sender     XPub
instance Receiver   XPub

instance SocketType XSub where zmqSocketType = const xsub
instance Sender     XSub
instance Receiver   XSub

instance SocketType Req where zmqSocketType = const request
instance Sender     Req
instance Receiver   Req

instance SocketType Rep where zmqSocketType = const response
instance Sender     Rep
instance Receiver   Rep

instance SocketType Dealer where zmqSocketType = const dealer
instance Sender     Dealer
instance Receiver   Dealer

instance SocketType Router where zmqSocketType = const router
instance Sender     Router
instance Receiver   Router

instance SocketType Pull where zmqSocketType = const pull
instance Receiver   Pull

instance SocketType Push where zmqSocketType = const push
instance Sender     Push

-- | Socket events.
data Event =
    In     -- ^ ZMQ_POLLIN (incoming messages)
  | Out    -- ^ ZMQ_POLLOUT (outgoing messages, i.e. at least 1 byte can be written)
  | Err    -- ^ ZMQ_POLLERR
  deriving (Eq, Ord, Read, Show)

-- | Type representing a descriptor, poll is waiting for
-- (either a 0MQ socket or a file descriptor) plus the type
-- of event to wait for.
data Poll m where
    Sock :: Socket s -> [Event] -> Maybe ([Event] -> m ()) -> Poll m
    File :: Fd -> [Event] -> Maybe ([Event] -> m ()) -> Poll m

-- | Return the runtime version of the underlying 0MQ library as a
-- (major, minor, patch) triple.
version :: IO (Int, Int, Int)
version =
    with 0 $ \major_ptr ->
    with 0 $ \minor_ptr ->
    with 0 $ \patch_ptr ->
        c_zmq_version major_ptr minor_ptr patch_ptr >>
        tupleUp <$> peek major_ptr <*> peek minor_ptr <*> peek patch_ptr
  where
    tupleUp a b c = (fromIntegral a, fromIntegral b, fromIntegral c)

init :: Size -> IO Context
init n = do
    c <- context
    setIoThreads n c
    return c
{-# DEPRECATED init "Use context" #-}

-- | Initialize a 0MQ context (cf. zmq_ctx_new for details).  You should
-- normally prefer to use 'withContext' instead.
context :: IO Context
context = Context <$> throwIfNull "init" c_zmq_ctx_new

term :: Context -> IO ()
term = destroy
{-# DEPRECATED term "Use destroy" #-}

-- | Terminate a 0MQ context (cf. zmq_ctx_destroy).  You should normally
-- prefer to use 'withContext' instead.
destroy :: Context -> IO ()
destroy c = throwIfMinus1Retry_ "term" . c_zmq_ctx_destroy . _ctx $ c

-- | Run an action with a 0MQ context.  The 'Context' supplied to your
-- action will /not/ be valid after the action either returns or
-- throws an exception.
withContext :: (Context -> IO a) -> IO a
withContext act =
  bracket (throwIfNull "withContext (new)" $ c_zmq_ctx_new)
          (throwIfMinus1Retry_ "withContext (destroy)" . c_zmq_ctx_destroy)
          (act . Context)

-- | Run an action with a 0MQ socket. The socket will be closed after running
-- the supplied action even if an error occurs. The socket supplied to your
-- action will /not/ be valid after the action terminates.
withSocket :: SocketType a => Context -> a -> (Socket a -> IO b) -> IO b
withSocket c t = bracket (socket c t) close

-- | Create a new 0MQ socket within the given context. 'withSocket' provides
-- automatic socket closing and may be safer to use.
socket :: SocketType a => Context -> a -> IO (Socket a)
socket c t = Socket <$> mkSocketRepr t c

-- | Close a 0MQ socket. 'withSocket' provides automatic socket closing and may
-- be safer to use.
close :: Socket a -> IO ()
close = closeSock . _socketRepr

-- | Subscribe Socket to given subscription.
subscribe :: Subscriber a => Socket a -> SB.ByteString -> IO ()
subscribe s = setByteStringOpt s B.subscribe

-- | Unsubscribe Socket from given subscription.
unsubscribe :: Subscriber a => Socket a -> SB.ByteString -> IO ()
unsubscribe s = setByteStringOpt s B.unsubscribe

-- Read Only

-- | Cf. @zmq_getsockopt ZMQ_EVENTS@
events :: Socket a -> IO [Event]
events s = toEvents <$> getIntOpt s B.events 0

-- | Cf. @zmq_getsockopt ZMQ_FD@
fileDescriptor :: Socket a -> IO Fd
fileDescriptor s = Fd . fromIntegral <$> getInt32Option B.filedesc s

-- | Cf. @zmq_getsockopt ZMQ_RCVMORE@
moreToReceive :: Socket a -> IO Bool
moreToReceive s = (== 1) <$> getInt32Option B.receiveMore s

-- Read

-- | Cf. @zmq_ctx_get ZMQ_IO_THREADS@
ioThreads :: Context -> IO Word
ioThreads = ctxIntOption "ioThreads" _ioThreads

-- | Cf. @zmq_ctx_get ZMQ_MAX_SOCKETS@
maxSockets :: Context -> IO Word
maxSockets = ctxIntOption "maxSockets" _maxSockets

-- | Cf. @zmq_getsockopt ZMQ_IDENTITY@
identity :: Socket a -> IO SB.ByteString
identity s = getByteStringOpt s B.identity

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

-- | Cf. @zmq_getsockopt ZMQ_DELAY_ATTACH_ON_CONNECT@
delayAttachOnConnect :: Socket a -> IO Bool
delayAttachOnConnect s = (== 1) <$> getInt32Option B.delayAttachOnConnect s

-- | Cf. @zmq_getsockopt ZMQ_LINGER@
linger :: Socket a -> IO Int
linger = getInt32Option B.linger

-- | Cf. @zmq_getsockopt ZMQ_LAST_ENDPOINT@
lastEndpoint :: Socket a -> IO String
lastEndpoint s = getStrOpt s B.lastEndpoint

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

-- | Cf. @zmq_getsockopt ZMQ_TCP_KEEPALIVE@
tcpKeepAlive :: Socket a -> IO Switch
tcpKeepAlive s = getInt32Option B.tcpKeepAlive s >>= convert . toSwitch
  where
    convert Nothing  = throwError "Invalid value for ZMQ_TCP_KEEPALIVE"
    convert (Just i) = return i

-- | Cf. @zmq_getsockopt ZMQ_TCP_KEEPALIVE_CNT@
tcpKeepAliveCount :: Socket a -> IO Int
tcpKeepAliveCount = getInt32Option B.tcpKeepAliveCount

-- | Cf. @zmq_getsockopt ZMQ_TCP_KEEPALIVE_IDLE@
tcpKeepAliveIdle :: Socket a -> IO Int
tcpKeepAliveIdle = getInt32Option B.tcpKeepAliveIdle

-- | Cf. @zmq_getsockopt ZMQ_TCP_KEEPALIVE_INTVL@
tcpKeepAliveInterval :: Socket a -> IO Int
tcpKeepAliveInterval = getInt32Option B.tcpKeepAliveInterval

-- Write

-- | Cf. @zmq_ctx_set ZMQ_IO_THREADS@
setIoThreads :: Word -> Context -> IO ()
setIoThreads n = setCtxIntOption "ioThreads" _ioThreads n

-- | Cf. @zmq_ctx_set ZMQ_MAX_SOCKETS@
setMaxSockets :: Word -> Context -> IO ()
setMaxSockets n = setCtxIntOption "maxSockets" _maxSockets n

-- | Cf. @zmq_setsockopt ZMQ_IDENTITY@
setIdentity :: Restricted N1 N254 SB.ByteString -> Socket a -> IO ()
setIdentity x s = setByteStringOpt s B.identity (rvalue x)

-- | Cf. @zmq_setsockopt ZMQ_AFFINITY@
setAffinity :: Word64 -> Socket a -> IO ()
setAffinity x s = setIntOpt s B.affinity x

-- | Cf. @zmq_setsockopt ZMQ_DELAY_ATTACH_ON_CONNECT@
setDelayAttachOnConnect :: Bool -> Socket a -> IO ()
setDelayAttachOnConnect x s = setIntOpt s B.delayAttachOnConnect (bool2cint x)

-- | Cf. @zmq_setsockopt ZMQ_MAXMSGSIZE@
setMaxMessageSize :: Integral i => Restricted Nneg1 Int64 i -> Socket a -> IO ()
setMaxMessageSize x s = setIntOpt s B.maxMessageSize ((fromIntegral . rvalue $ x) :: Int64)

-- | Cf. @zmq_setsockopt ZMQ_IPV4ONLY@
setIpv4Only :: Bool -> Socket a -> IO ()
setIpv4Only x s  = setIntOpt s B.ipv4Only (bool2cint x)

-- | Cf. @zmq_setsockopt ZMQ_LINGER@
setLinger :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setLinger = setInt32OptFromRestricted B.linger

-- | Cf. @zmq_setsockopt ZMQ_RCVTIMEO@
setReceiveTimeout :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setReceiveTimeout = setInt32OptFromRestricted B.receiveTimeout

-- | Cf. @zmq_setsockopt ZMQ_ROUTER_MANDATORY@
setRouterMandatory :: Bool -> Socket Router -> IO ()
setRouterMandatory x s = setIntOpt s B.routerMandatory (bool2cint x)

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

-- | Cf. @zmq_setsockopt ZMQ_TCP_ACCEPT_FILTER@
setTcpAcceptFilter :: Maybe SB.ByteString -> Socket a -> IO ()
setTcpAcceptFilter Nothing sock = onSocket "setTcpAcceptFilter" sock $ \s ->
    throwIfMinus1Retry_ "setStrOpt" $
        c_zmq_setsockopt s (optVal tcpAcceptFilter) nullPtr 0
setTcpAcceptFilter (Just dat) sock = setByteStringOpt sock tcpAcceptFilter dat

-- | Cf. @zmq_setsockopt ZMQ_TCP_KEEPALIVE@
setTcpKeepAlive :: Switch -> Socket a -> IO ()
setTcpKeepAlive x s = setIntOpt s B.tcpKeepAlive (fromSwitch x :: CInt)

-- | Cf. @zmq_setsockopt ZMQ_TCP_KEEPALIVE_CNT@
setTcpKeepAliveCount :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setTcpKeepAliveCount = setInt32OptFromRestricted B.tcpKeepAliveCount

-- | Cf. @zmq_setsockopt ZMQ_TCP_KEEPALIVE_IDLE@
setTcpKeepAliveIdle :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setTcpKeepAliveIdle = setInt32OptFromRestricted B.tcpKeepAliveIdle

-- | Cf. @zmq_setsockopt ZMQ_TCP_KEEPALIVE_INTVL@
setTcpKeepAliveInterval :: Integral i => Restricted Nneg1 Int32 i -> Socket a -> IO ()
setTcpKeepAliveInterval = setInt32OptFromRestricted B.tcpKeepAliveInterval

-- | Cf. @zmq_setsockopt ZMQ_XPUB_VERBOSE@
setXPubVerbose :: Bool -> Socket XPub -> IO ()
setXPubVerbose x s = setIntOpt s B.xpubVerbose (bool2cint x)

-- | Bind the socket to the given address (cf. zmq_bind)
bind :: Socket a -> String -> IO ()
bind sock str = onSocket "bind" sock $
    throwIfMinus1_ "bind" . withCString str . c_zmq_bind

-- | Unbind the socket from the given address (cf. zmq_unbind)
unbind :: Socket a -> String -> IO ()
unbind sock str = onSocket "unbind" sock $
    throwIfMinus1_ "unbind" . withCString str . c_zmq_unbind

-- | Connect the socket to the given address (cf. zmq_connect).
connect :: Socket a -> String -> IO ()
connect sock str = onSocket "connect" sock $
    throwIfMinus1_ "connect" . withCString str . c_zmq_connect

-- | Send the given 'SB.ByteString' over the socket (cf. zmq_sendmsg).
--
-- /Note/: This function always calls @zmq_sendmsg@ in a non-blocking way,
-- i.e. there is no need to provide the @ZMQ_DONTWAIT@ flag as this is used
-- by default. Still 'send' is blocking the thread as long as the message
-- can not be queued on the socket using GHC's 'threadWaitWrite'.
send :: Sender a => Socket a -> [Flag] -> SB.ByteString -> IO ()
send sock fls val = bracket (messageOf val) messageClose $ \m ->
  onSocket "send" sock $ \s ->
    retry "send" (waitWrite sock) $
          c_zmq_sendmsg s (msgPtr m) (combineFlags (DontWait : fls))

-- | Send the given 'LB.ByteString' over the socket (cf. zmq_sendmsg).
-- This is operationally identical to @send socket (Strict.concat
-- (Lazy.toChunks lbs)) flags@ but may be more efficient.
--
-- /Note/: This function always calls @zmq_sendmsg@ in a non-blocking way,
-- i.e. there is no need to provide the @ZMQ_DONTWAIT@ flag as this is used
-- by default. Still 'send'' is blocking the thread as long as the message
-- can not be queued on the socket using GHC's 'threadWaitWrite'.
send' :: Sender a => Socket a -> [Flag] -> LB.ByteString -> IO ()
send' sock fls val = bracket (messageOfLazy val) messageClose $ \m ->
  onSocket "send'" sock $ \s ->
    retry "send'" (waitWrite sock) $
          c_zmq_sendmsg s (msgPtr m) (combineFlags (DontWait : fls))

-- | Send a multi-part message.
-- This function applies the 'SendMore' 'Flag' between all message parts.
-- 0MQ guarantees atomic delivery of a multi-part message
-- (cf. zmq_sendmsg for details).
sendMulti :: Sender a => Socket a -> [SB.ByteString] -> IO ()
sendMulti sock msgs = do
    mapM_ (send sock [SendMore]) (P.init msgs)
    send sock [] (last msgs)

-- | Receive a 'ByteString' from socket (cf. zmq_recvmsg).
--
-- /Note/: This function always calls @zmq_recvmsg@ in a non-blocking way,
-- i.e. there is no need to provide the @ZMQ_DONTWAIT@ flag as this is used
-- by default. Still 'receive' is blocking the thread as long as no data
-- is available using GHC's 'threadWaitRead'.
receive :: Receiver a => Socket a -> IO (SB.ByteString)
receive sock = bracket messageInit messageClose $ \m ->
  onSocket "receive" sock $ \s -> do
    retry "receive" (waitRead sock) $
          c_zmq_recvmsg s (msgPtr m) (flagVal dontWait)
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    SB.packCStringLen (data_ptr, fromIntegral size)

-- | Receive a multi-part message.
-- This function collects all message parts send via 'sendMulti'.
receiveMulti :: Receiver a => Socket a -> IO [SB.ByteString]
receiveMulti sock = recvall []
  where
    recvall acc = do
        msg <- receive sock
        moreToReceive sock >>= next (msg:acc)

    next acc True  = recvall acc
    next acc False = return (reverse acc)

-- | Setup socket monitoring, i.e. a 'Pair' socket which
-- sends monitoring events about the given 'Socket' to the
-- given address.
socketMonitor :: [EventType] -> String -> Socket a -> IO ()
socketMonitor es addr soc = onSocket "socketMonitor" soc $ \s ->
    withCString addr $ \a ->
        throwIfMinus1_ "zmq_socket_monitor" $
            c_zmq_socket_monitor s a (events2cint es)

-- | Monitor socket events.
-- This function returns a function which can be invoked to retrieve
-- the next socket event, potentially blocking until the next one becomes
-- available. When applied to 'False', monitoring will terminate, i.e.
-- internal monitoring resources will be disposed. Consequently after
-- 'monitor' has been invoked, the returned function must be applied
-- /once/ to 'False'.
monitor :: [EventType] -> Context -> Socket a -> IO (Bool -> IO (Maybe EventMsg))
monitor es ctx sock = do
    let addr = "inproc://" ++ show (_socket . _socketRepr $ sock)
    s <- socket ctx Pair
    socketMonitor es addr sock
    connect s addr
    next s <$> messageInit
  where
    next soc m False = messageClose m `finally` close soc >> return Nothing
    next soc m True  = onSocket "recv" soc $ \s -> do
        retry "recv" (waitRead soc) $ c_zmq_recvmsg s (msgPtr m) (flagVal dontWait)
        ptr <- c_zmq_msg_data (msgPtr m)
        str <- peekByteOff ptr zmqEventAddrOffset >>= SB.packCString
        dat <- peekByteOff ptr zmqEventDataOffset :: IO CInt
        tag <- peek ptr :: IO CInt
        return . Just $ eventMessage str dat (ZMQEventType tag)

-- | Polls for events on the given 'Poll' descriptors. Returns the
-- same list of 'Poll' descriptors with an "updated" 'PollEvent' field
-- (cf. zmq_poll). Sockets which have seen no activity have 'None' in
-- their 'PollEvent' field.
poll :: MonadIO m => Timeout -> [Poll m] -> m [[Event]]
poll to desc = do
    let len = length desc
    let ps  = map toZMQPoll desc
    ps' <- liftIO $ withArray ps $ \ptr -> do
        throwIfMinus1Retry_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        peekArray len ptr
    mapM fromZMQPoll (zip desc ps')
  where
    toZMQPoll :: MonadIO m => Poll m -> ZMQPoll
    toZMQPoll (Sock (Socket (SocketRepr s _)) e _) =
        ZMQPoll s 0 (combine (map fromEvent e)) 0

    toZMQPoll (File (Fd s) e _) =
        ZMQPoll nullPtr (fromIntegral s) (combine (map fromEvent e)) 0

    fromZMQPoll :: MonadIO m => (Poll m, ZMQPoll) -> m [Event]
    fromZMQPoll (p, zp) = do
        let e = toEvents . fromIntegral . pRevents $ zp
        let (e', f) = case p of
                        (Sock _ x g) -> (x, g)
                        (File _ x g) -> (x, g)
        unless (null (e `intersect` e')) $
            maybe (return ()) ($ e) f
        return e

    fromEvent :: Event -> CShort
    fromEvent In   = fromIntegral . pollVal $ pollIn
    fromEvent Out  = fromIntegral . pollVal $ pollOut
    fromEvent Err  = fromIntegral . pollVal $ pollerr

-- Convert bit-masked word into Event list.
toEvents :: Word32 -> [Event]
toEvents e = foldl' (\es f -> f e es) [] tests
  where
      tests =
        [ \i xs -> if i .&. (fromIntegral . pollVal $ pollIn)  /= 0 then In:xs else xs
        , \i xs -> if i .&. (fromIntegral . pollVal $ pollOut) /= 0 then Out:xs else xs
        , \i xs -> if i .&. (fromIntegral . pollVal $ pollerr) /= 0 then Err:xs else xs
        ]

retry :: String -> IO () -> IO CInt -> IO ()
retry msg wait act = throwIfMinus1RetryMayBlock_ msg act wait

wait' :: (Fd -> IO ()) -> ZMQPollEvent -> Socket a -> IO ()
wait' w f s = do
    fd <- getIntOpt s B.filedesc 0
    w (Fd fd)
    evs <- getInt32Option B.events s
    unless (testev evs) $
        wait' w f s
  where
    testev e = e .&. fromIntegral (pollVal f) /= 0

-- | Wait until data is available for reading from the given Socket.
-- After this function returns, a call to 'receive' will essentially be
-- non-blocking.
waitRead :: Socket a -> IO ()
waitRead = wait' threadWaitRead pollIn

-- | Wait until data can be written to the given Socket.
-- After this function returns, a call to 'send' will essentially be
-- non-blocking.
waitWrite :: Socket a -> IO ()
waitWrite = wait' threadWaitWrite pollOut

-- | Starts built-in 0MQ proxy.
--
-- Proxy connects front to back socket
--
-- Before calling proxy all sockets should be binded
--
-- If the capture socket is not Nothing, the proxy  shall send all
-- messages, received on both frontend and backend, to the capture socket.
proxy :: Socket a -> Socket b -> Maybe (Socket c) -> IO ()
proxy front back capture =
  onSocket "proxy-front" front $ \f ->
    onSocket "proxy-back" back $ \b ->
      void (c_zmq_proxy f b c)
  where
    c = maybe nullPtr (_socket . _socketRepr) capture

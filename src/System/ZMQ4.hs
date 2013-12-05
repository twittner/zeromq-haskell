{-# LANGUAGE GADTs #-}

-- |
-- Module      : System.ZMQ4
-- Copyright   : (c) 2010-2013 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable
--
-- 0MQ haskell binding. The API closely follows the C-API of 0MQ with
-- the main difference being that sockets are typed.
--
-- /Notes/
--
-- Many option settings use a 'Restriction' to further constrain the
-- range of possible values of their integral types. For example
-- the maximum message size can be given as -1, which means no limit
-- or by greater values, which denote the message size in bytes. The
-- type of 'setMaxMessageSize' is therefore:
--
-- @setMaxMessageSize :: Integral i
--                    => Restricted (Nneg1, Int64) i
--                    -> Socket a
--                    -> IO ()@
--
-- which means any integral value in the range of @-1@ to
-- (@maxBound :: Int64@) can be given. To create a restricted
-- value from plain value, use 'toRestricted' or 'restrict'.

module System.ZMQ4
  ( -- * Type Definitions
    -- ** Socket Types
    Pair   (..)
  , Pub    (..)
  , Sub    (..)
  , XPub   (..)
  , XSub   (..)
  , Req    (..)
  , Rep    (..)
  , Dealer (..)
  , Router (..)
  , XReq
  , XRep
  , Pull   (..)
  , Push   (..)
  , Stream (..)

    -- ** Socket type-classes
  , SocketType
  , Sender
  , Receiver
  , Subscriber
  , SocketLike
  , Conflatable
  , SendProbe

    -- ** Various type definitions
  , Size
  , Context
  , Socket
  , Flag              (SendMore)
  , Switch            (..)
  , Timeout
  , Event             (..)
  , EventType         (..)
  , EventMsg          (..)
  , Poll              (..)
  , KeyFormat         (..)
  , SecurityMechanism (..)

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

  , System.ZMQ4.subscribe
  , System.ZMQ4.unsubscribe

    -- * Context Options (Read)
  , ioThreads
  , maxSockets

    -- * Context Options (Write)
  , setIoThreads
  , setMaxSockets

    -- * Socket Options (Read)
  , System.ZMQ4.affinity
  , System.ZMQ4.backlog
  , System.ZMQ4.conflate
  , System.ZMQ4.curvePublicKey
  , System.ZMQ4.curveSecretKey
  , System.ZMQ4.curveServerKey
  , System.ZMQ4.delayAttachOnConnect
  , System.ZMQ4.events
  , System.ZMQ4.fileDescriptor
  , System.ZMQ4.identity
  , System.ZMQ4.immediate
  , System.ZMQ4.ipv4Only
  , System.ZMQ4.ipv6
  , System.ZMQ4.lastEndpoint
  , System.ZMQ4.linger
  , System.ZMQ4.maxMessageSize
  , System.ZMQ4.mcastHops
  , System.ZMQ4.mechanism
  , System.ZMQ4.moreToReceive
  , System.ZMQ4.plainServer
  , System.ZMQ4.plainPassword
  , System.ZMQ4.plainUserName
  , System.ZMQ4.rate
  , System.ZMQ4.receiveBuffer
  , System.ZMQ4.receiveHighWM
  , System.ZMQ4.receiveTimeout
  , System.ZMQ4.reconnectInterval
  , System.ZMQ4.reconnectIntervalMax
  , System.ZMQ4.recoveryInterval
  , System.ZMQ4.sendBuffer
  , System.ZMQ4.sendHighWM
  , System.ZMQ4.sendTimeout
  , System.ZMQ4.tcpKeepAlive
  , System.ZMQ4.tcpKeepAliveCount
  , System.ZMQ4.tcpKeepAliveIdle
  , System.ZMQ4.tcpKeepAliveInterval
  , System.ZMQ4.zapDomain

    -- * Socket Options (Write)
  , setAffinity
  , setBacklog
  , setConflate
  , setCurveServer
  , setCurvePublicKey
  , setCurveSecretKey
  , setCurveServerKey
  , setDelayAttachOnConnect
  , setIdentity
  , setImmediate
  , setIpv4Only
  , setIpv6
  , setLinger
  , setMaxMessageSize
  , setMcastHops
  , setPlainServer
  , setPlainPassword
  , setPlainUserName
  , setProbeRouter
  , setRate
  , setReceiveBuffer
  , setReceiveHighWM
  , setReceiveTimeout
  , setReconnectInterval
  , setReconnectIntervalMax
  , setRecoveryInterval
  , setReqCorrelate
  , setReqRelaxed
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
  , shutdown
  , context
  , socket
  , close
  , waitRead
  , waitWrite
  , z85Encode
  , z85Decode

    -- * Utils
  , proxy
  , curveKeyPair
  ) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Control.Monad (unless)
import Control.Monad.IO.Class
import Data.List (intersect, foldl')
import Data.List.NonEmpty (NonEmpty)
import Data.Restricted
import Data.Traversable (forM)
import Foreign hiding (throwIf, throwIf_, throwIfNull, void)
import Foreign.C.String
import Foreign.C.Types (CInt, CShort)
import System.Posix.Types (Fd(..))
import System.ZMQ4.Base
import System.ZMQ4.Internal
import System.ZMQ4.Error

import qualified Data.ByteString      as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.List.NonEmpty   as S
import qualified Prelude              as P
import qualified System.ZMQ4.Base     as B

import GHC.Conc (threadWaitRead, threadWaitWrite)

-----------------------------------------------------------------------------
-- Socket Types

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_PAIR>
data Pair = Pair

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_PUB>
data Pub = Pub

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_SUB>
data Sub = Sub

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_XPUB>
data XPub = XPub

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_XSUB>
data XSub = XSub

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_REQ>
data Req = Req

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_REP>
data Rep = Rep

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_DEALER>
data Dealer = Dealer

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_ROUTER>
data Router = Router

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_PULL>
data Pull = Pull

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_PUSH>
data Push = Push

-- | <http://api.zeromq.org/4-0:zmq-socket ZMQ_STREAM>
data Stream = Stream

type XReq = Dealer
{-# DEPRECATED XReq "Use Dealer" #-}

type XRep = Router
{-# DEPRECATED XRep "Use Router" #-}

-----------------------------------------------------------------------------
-- Socket Type Classifications

-- | Sockets which can 'subscribe'.
class Subscriber a

-- | Sockets which can 'send'.
class Sender a

-- | Sockets which can 'receive'.
class Receiver a

-- | Sockets which can be 'conflate'd.
class Conflatable a

-- | Sockets which can send probes (cf. 'setProbeRouter').
class SendProbe a

instance SocketType Pair where zmqSocketType = const pair
instance Sender     Pair
instance Receiver   Pair

instance SocketType  Pub where zmqSocketType = const pub
instance Sender      Pub
instance Conflatable Pub

instance SocketType  Sub where zmqSocketType = const sub
instance Subscriber  Sub
instance Receiver    Sub
instance Conflatable Sub

instance SocketType XPub where zmqSocketType = const xpub
instance Sender     XPub
instance Receiver   XPub

instance SocketType XSub where zmqSocketType = const xsub
instance Sender     XSub
instance Receiver   XSub

instance SocketType Req where zmqSocketType = const request
instance Sender     Req
instance Receiver   Req
instance SendProbe  Req

instance SocketType Rep where zmqSocketType = const response
instance Sender     Rep
instance Receiver   Rep

instance SocketType  Dealer where zmqSocketType = const dealer
instance Sender      Dealer
instance Receiver    Dealer
instance Conflatable Dealer
instance SendProbe   Dealer

instance SocketType Router where zmqSocketType = const router
instance Sender     Router
instance Receiver   Router
instance SendProbe  Router

instance SocketType  Pull where zmqSocketType = const pull
instance Receiver    Pull
instance Conflatable Pull

instance SocketType  Push where zmqSocketType = const push
instance Sender      Push
instance Conflatable Push

instance SocketType Stream where zmqSocketType = const stream
instance Sender     Stream
instance Receiver   Stream

-----------------------------------------------------------------------------

-- | Socket events.
data Event =
    In     -- ^ @ZMQ_POLLIN@ (incoming messages)
  | Out    -- ^ @ZMQ_POLLOUT@ (outgoing messages, i.e. at least 1 byte can be written)
  | Err    -- ^ @ZMQ_POLLERR@
  deriving (Eq, Ord, Read, Show)

-- | A 'Poll' value contains the object to poll (a 0MQ socket or a file
-- descriptor), the set of 'Event's which are of interest and--optionally--
-- a callback-function which is invoked iff the set of interested events
-- overlaps with the actual events.
data Poll s m where
    Sock :: s t -> [Event] -> Maybe ([Event] -> m ()) -> Poll s m
    File :: Fd -> [Event] -> Maybe ([Event] -> m ()) -> Poll s m

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

-- | Initialize a 0MQ context.
-- Equivalent to <http://api.zeromq.org/4-0:zmq-ctx-new zmq_ctx_new>.
context :: IO Context
context = Context <$> throwIfNull "init" c_zmq_ctx_new

-- | Terminate a 0MQ context.
-- Equivalent to <http://api.zeromq.org/4-0:zmq-ctx-term zmq_ctx_term>.
term :: Context -> IO ()
term c = throwIfMinus1Retry_ "term" . c_zmq_ctx_term . _ctx $ c

-- | Shutdown a 0MQ context.
-- Equivalent to <http://api.zeromq.org/4-0:zmq-ctx-shutdown zmq_ctx_shutdown>.
shutdown :: Context -> IO ()
shutdown = throwIfMinus1_ "shutdown" . c_zmq_ctx_shutdown . _ctx

-- | Run an action with a 0MQ context.  The 'Context' supplied to your
-- action will /not/ be valid after the action either returns or
-- throws an exception.
withContext :: (Context -> IO a) -> IO a
withContext act =
  bracket (throwIfNull "withContext (new)" $ c_zmq_ctx_new)
          (throwIfMinus1Retry_ "withContext (term)" . c_zmq_ctx_term)
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

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_EVENTS>.
events :: Socket a -> IO [Event]
events s = toEvents <$> getIntOpt s B.events 0

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_FD>.
fileDescriptor :: Socket a -> IO Fd
fileDescriptor s = Fd . fromIntegral <$> getInt32Option B.filedesc s

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RCVMORE>.
moreToReceive :: Socket a -> IO Bool
moreToReceive s = (== 1) <$> getInt32Option B.receiveMore s

-- Read

-- | <http://api.zeromq.org/4-0:zmq-ctx-get zmq_ctx_get ZMQ_IO_THREADS>.
ioThreads :: Context -> IO Word
ioThreads = ctxIntOption "ioThreads" _ioThreads

-- | <http://api.zeromq.org/4-0:zmq-ctx-get zmq_ctx_get ZMQ_MAX_SOCKETS>.
maxSockets :: Context -> IO Word
maxSockets = ctxIntOption "maxSockets" _maxSockets

-- | Restricts the outgoing and incoming socket buffers to a single message.
conflate :: Conflatable a => Socket a -> IO Bool
conflate s = (== 1) <$> getInt32Option B.conflate s

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_IMMEDIATE>.
immediate :: Socket a -> IO Bool
immediate s = (== 1) <$> getInt32Option B.immediate s

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_IDENTITY>.
identity :: Socket a -> IO SB.ByteString
identity s = getByteStringOpt s B.identity

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_AFFINITY>.
affinity :: Socket a -> IO Word64
affinity s = getIntOpt s B.affinity 0

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_MAXMSGSIZE>.
maxMessageSize :: Socket a -> IO Int64
maxMessageSize s = getIntOpt s B.maxMessageSize 0

ipv4Only :: Socket a -> IO Bool
ipv4Only s = (== 1) <$> getInt32Option B.ipv4Only s
{-# DEPRECATED ipv4Only "Use ipv6" #-}

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_IPV6>.
ipv6 :: Socket a -> IO Bool
ipv6 s = (== 1) <$> getInt32Option B.ipv6 s

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_BACKLOG>.
backlog :: Socket a -> IO Int
backlog = getInt32Option B.backlog

delayAttachOnConnect :: Socket a -> IO Bool
delayAttachOnConnect s = (== 1) <$> getInt32Option B.delayAttachOnConnect s
{-# DEPRECATED delayAttachOnConnect "Use immediate" #-}

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_LINGER>.
linger :: Socket a -> IO Int
linger = getInt32Option B.linger

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_LAST_ENDPOINT>.
lastEndpoint :: Socket a -> IO String
lastEndpoint s = getStrOpt s B.lastEndpoint

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RATE>.
rate :: Socket a -> IO Int
rate = getInt32Option B.rate

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RCVBUF>.
receiveBuffer :: Socket a -> IO Int
receiveBuffer = getInt32Option B.receiveBuf

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RECONNECT_IVL>.
reconnectInterval :: Socket a -> IO Int
reconnectInterval = getInt32Option B.reconnectIVL

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RECONNECT_IVL_MAX>.
reconnectIntervalMax :: Socket a -> IO Int
reconnectIntervalMax = getInt32Option B.reconnectIVLMax

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RECOVERY_IVL>.
recoveryInterval :: Socket a -> IO Int
recoveryInterval = getInt32Option B.recoveryIVL

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_SNDBUF>.
sendBuffer :: Socket a -> IO Int
sendBuffer = getInt32Option B.sendBuf

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_MULTICAST_HOPS>.
mcastHops :: Socket a -> IO Int
mcastHops = getInt32Option B.mcastHops

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RCVHWM>.
receiveHighWM :: Socket a -> IO Int
receiveHighWM = getInt32Option B.receiveHighWM

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_RCVTIMEO>.
receiveTimeout :: Socket a -> IO Int
receiveTimeout = getInt32Option B.receiveTimeout

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_SNDTIMEO>.
sendTimeout :: Socket a -> IO Int
sendTimeout = getInt32Option B.sendTimeout

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_SNDHWM>.
sendHighWM :: Socket a -> IO Int
sendHighWM = getInt32Option B.sendHighWM

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_TCP_KEEPALIVE>.
tcpKeepAlive :: Socket a -> IO Switch
tcpKeepAlive = fmap (toSwitch "Invalid ZMQ_TCP_KEEPALIVE")
             . getInt32Option B.tcpKeepAlive

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_TCP_KEEPALIVE_CNT>.
tcpKeepAliveCount :: Socket a -> IO Int
tcpKeepAliveCount = getInt32Option B.tcpKeepAliveCount

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_TCP_KEEPALIVE_IDLE>.
tcpKeepAliveIdle :: Socket a -> IO Int
tcpKeepAliveIdle = getInt32Option B.tcpKeepAliveIdle

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_TCP_KEEPALIVE_INTVL>.
tcpKeepAliveInterval :: Socket a -> IO Int
tcpKeepAliveInterval = getInt32Option B.tcpKeepAliveInterval

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_MECHANISM>.
mechanism :: Socket a -> IO SecurityMechanism
mechanism = fmap (fromMechanism "Invalid ZMQ_MECHANISM")
          . getInt32Option B.mechanism

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_PLAIN_SERVER>.
plainServer :: Socket a -> IO Bool
plainServer = fmap (== 1) . getInt32Option B.plainServer

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_PLAIN_USERNAME>.
plainUserName :: Socket a -> IO SB.ByteString
plainUserName s = getByteStringOpt s B.plainUserName

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_PLAIN_PASSWORD>.
plainPassword :: Socket a -> IO SB.ByteString
plainPassword s = getByteStringOpt s B.plainPassword

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_ZAP_DOMAIN>.
zapDomain :: Socket a -> IO SB.ByteString
zapDomain s = getByteStringOpt s B.zapDomain

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_CURVE_PUBLICKEY>.
curvePublicKey :: KeyFormat f -> Socket a -> IO SB.ByteString
curvePublicKey f s = getKey f s B.curvePublicKey

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_CURVE_SERVERKEY>.
curveServerKey :: KeyFormat f -> Socket a -> IO SB.ByteString
curveServerKey f s = getKey f s B.curveServerKey

-- | <http://api.zeromq.org/4-0:zmq-getsockopt zmq_getsockopt ZMQ_CURVE_SECRETKEY>.
curveSecretKey :: KeyFormat f -> Socket a -> IO SB.ByteString
curveSecretKey f s = getKey f s B.curveSecretKey

-- Write

-- | <http://api.zeromq.org/4-0:zmq-ctx-set zmq_ctx_get ZMQ_IO_THREADS>.
setIoThreads :: Word -> Context -> IO ()
setIoThreads n = setCtxIntOption "ioThreads" _ioThreads n

-- | <http://api.zeromq.org/4-0:zmq-ctx-set zmq_ctx_get ZMQ_MAX_SOCKETS>.
setMaxSockets :: Word -> Context -> IO ()
setMaxSockets n = setCtxIntOption "maxSockets" _maxSockets n

-- | Restrict the outgoing and incoming socket buffers to a single message.
setConflate :: Conflatable a => Bool -> Socket a -> IO ()
setConflate x s = setIntOpt s B.conflate (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_IMMEDIATE>.
setImmediate :: Bool -> Socket a -> IO ()
setImmediate x s = setIntOpt s B.immediate (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_IDENTITY>.
setIdentity :: Restricted (N1, N254) SB.ByteString -> Socket a -> IO ()
setIdentity x s = setByteStringOpt s B.identity (rvalue x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_AFFINITY>.
setAffinity :: Word64 -> Socket a -> IO ()
setAffinity x s = setIntOpt s B.affinity x

setDelayAttachOnConnect :: Bool -> Socket a -> IO ()
setDelayAttachOnConnect x s = setIntOpt s B.delayAttachOnConnect (bool2cint x)
{-# DEPRECATED setDelayAttachOnConnect "Use setImmediate" #-}

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_MAXMSGSIZE>.
setMaxMessageSize :: Integral i => Restricted (Nneg1, Int64) i -> Socket a -> IO ()
setMaxMessageSize x s = setIntOpt s B.maxMessageSize ((fromIntegral . rvalue $ x) :: Int64)

setIpv4Only :: Bool -> Socket a -> IO ()
setIpv4Only x s = setIntOpt s B.ipv4Only (bool2cint x)
{-# DEPRECATED setIpv4Only "Use setIpv6" #-}

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_IPV6>.
setIpv6 :: Bool -> Socket a -> IO ()
setIpv6 x s = setIntOpt s B.ipv6 (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_PLAIN_SERVER>.
setPlainServer :: Bool -> Socket a -> IO ()
setPlainServer x s = setIntOpt s B.plainServer (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_CURVE_SERVER>.
setCurveServer :: Bool -> Socket a -> IO ()
setCurveServer x s = setIntOpt s B.curveServer (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_PLAIN_USERNAME>.
setPlainUserName :: Restricted (N1, N254) SB.ByteString -> Socket a -> IO ()
setPlainUserName x s = setByteStringOpt s B.plainUserName (rvalue x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_PLAIN_USERNAME>.
setPlainPassword :: Restricted (N1, N254) SB.ByteString -> Socket a -> IO ()
setPlainPassword x s = setByteStringOpt s B.plainPassword (rvalue x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_LINGER>.
setLinger :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setLinger = setInt32OptFromRestricted B.linger

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RCVTIMEO>.
setReceiveTimeout :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setReceiveTimeout = setInt32OptFromRestricted B.receiveTimeout

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_ROUTER_MANDATORY>.
setRouterMandatory :: Bool -> Socket Router -> IO ()
setRouterMandatory x s = setIntOpt s B.routerMandatory (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_SNDTIMEO>.
setSendTimeout :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setSendTimeout = setInt32OptFromRestricted B.sendTimeout

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RATE>.
setRate :: Integral i => Restricted (N1, Int32) i -> Socket a -> IO ()
setRate = setInt32OptFromRestricted B.rate

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_MULTICAST_HOPS>.
setMcastHops :: Integral i => Restricted (N1, Int32) i -> Socket a -> IO ()
setMcastHops = setInt32OptFromRestricted B.mcastHops

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_BACKLOG>.
setBacklog :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setBacklog = setInt32OptFromRestricted B.backlog

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_CURVE_PUBLICKEY>.
setCurvePublicKey :: KeyFormat f -> Restricted f SB.ByteString -> Socket a -> IO ()
setCurvePublicKey _ k s = setByteStringOpt s B.curvePublicKey (rvalue k)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_CURVE_SECRETKEY>.
setCurveSecretKey :: KeyFormat f -> Restricted f SB.ByteString -> Socket a -> IO ()
setCurveSecretKey _ k s = setByteStringOpt s B.curveSecretKey (rvalue k)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_CURVE_SERVERKEY>.
setCurveServerKey :: KeyFormat f -> Restricted f SB.ByteString -> Socket a -> IO ()
setCurveServerKey _ k s = setByteStringOpt s B.curveServerKey (rvalue k)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_PROBE_ROUTER>.
setProbeRouter :: SendProbe a => Bool -> Socket a -> IO ()
setProbeRouter x s = setIntOpt s B.probeRouter (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RCVBUF>.
setReceiveBuffer :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setReceiveBuffer = setInt32OptFromRestricted B.receiveBuf

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RECONNECT_IVL>.
setReconnectInterval :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setReconnectInterval = setInt32OptFromRestricted B.reconnectIVL

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RECONNECT_IVL_MAX>.
setReconnectIntervalMax :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setReconnectIntervalMax = setInt32OptFromRestricted B.reconnectIVLMax

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_REQ_CORRELATE>.
setReqCorrelate :: Bool -> Socket Req -> IO ()
setReqCorrelate x s = setIntOpt s B.reqCorrelate (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_REQ_RELAXED>.
setReqRelaxed :: Bool -> Socket Req -> IO ()
setReqRelaxed x s = setIntOpt s B.reqRelaxed (bool2cint x)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_SNDBUF>.
setSendBuffer :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setSendBuffer = setInt32OptFromRestricted B.sendBuf

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RECOVERY_IVL>.
setRecoveryInterval :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setRecoveryInterval = setInt32OptFromRestricted B.recoveryIVL

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_RCVHWM>.
setReceiveHighWM :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setReceiveHighWM = setInt32OptFromRestricted B.receiveHighWM

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_SNDHWM>.
setSendHighWM :: Integral i => Restricted (N0, Int32) i -> Socket a -> IO ()
setSendHighWM = setInt32OptFromRestricted B.sendHighWM

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_TCP_ACCEPT_FILTER>.
setTcpAcceptFilter :: Maybe SB.ByteString -> Socket a -> IO ()
setTcpAcceptFilter Nothing sock = onSocket "setTcpAcceptFilter" sock $ \s ->
    throwIfMinus1Retry_ "setStrOpt" $
        c_zmq_setsockopt s (optVal tcpAcceptFilter) nullPtr 0
setTcpAcceptFilter (Just dat) sock = setByteStringOpt sock tcpAcceptFilter dat

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_TCP_KEEPALIVE>.
setTcpKeepAlive :: Switch -> Socket a -> IO ()
setTcpKeepAlive x s = setIntOpt s B.tcpKeepAlive (fromSwitch x :: CInt)

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_TCP_KEEPALIVE_CNT>.
setTcpKeepAliveCount :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setTcpKeepAliveCount = setInt32OptFromRestricted B.tcpKeepAliveCount

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_TCP_KEEPALIVE_IDLE>.
setTcpKeepAliveIdle :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setTcpKeepAliveIdle = setInt32OptFromRestricted B.tcpKeepAliveIdle

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_TCP_KEEPALIVE_INTVL>.
setTcpKeepAliveInterval :: Integral i => Restricted (Nneg1, Int32) i -> Socket a -> IO ()
setTcpKeepAliveInterval = setInt32OptFromRestricted B.tcpKeepAliveInterval

-- | <http://api.zeromq.org/4-0:zmq-setsockopt zmq_setsockopt ZMQ_XPUB_VERBOSE>.
setXPubVerbose :: Bool -> Socket XPub -> IO ()
setXPubVerbose x s = setIntOpt s B.xpubVerbose (bool2cint x)

-- | Bind the socket to the given address
-- (cf. <http://api.zeromq.org/4-0:zmq-bind zmq_bind>).
bind :: Socket a -> String -> IO ()
bind sock str = onSocket "bind" sock $
    throwIfMinus1Retry_ "bind" . withCString str . c_zmq_bind

-- | Unbind the socket from the given address
-- (cf. <http://api.zeromq.org/4-0:zmq-unbind zmq_unbind>).
unbind :: Socket a -> String -> IO ()
unbind sock str = onSocket "unbind" sock $
    throwIfMinus1Retry_ "unbind" . withCString str . c_zmq_unbind

-- | Connect the socket to the given address
-- (cf. <http://api.zeromq.org/4-0:zmq-connect zmq_connect>).
connect :: Socket a -> String -> IO ()
connect sock str = onSocket "connect" sock $
    throwIfMinus1Retry_ "connect" . withCString str . c_zmq_connect

-- | Send the given 'SB.ByteString' over the socket
-- (cf. <http://api.zeromq.org/4-0:zmq-sendmsg zmq_sendmsg>).
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

-- | Send the given 'LB.ByteString' over the socket
-- (cf. <http://api.zeromq.org/4-0:zmq-sendmsg zmq_sendmsg>).
--
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
-- (cf. <http://api.zeromq.org/4-0:zmq-sendmsg zmq_sendmsg>).
sendMulti :: Sender a => Socket a -> NonEmpty SB.ByteString -> IO ()
sendMulti sock msgs = do
    mapM_ (send sock [SendMore]) (S.init msgs)
    send sock [] (S.last msgs)

-- | Receive a 'ByteString' from socket
-- (cf. <http://api.zeromq.org/4-0:zmq-recvmsg zmq_recvmsg>).
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

-- | Monitor socket events
-- (cf. <http://api.zeromq.org/4-0:zmq-socket-monitor zmq_socket_monitor>).
--
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
        evt <- peek ptr
        str <- receive soc
        return . Just $ eventMessage str evt

-- | Polls for events on the given 'Poll' descriptors. Returns a list of
-- events per descriptor which have occured.
-- (cf. <http://api.zeromq.org/4-0:zmq-poll zmq_poll>)
poll :: (SocketLike s, MonadIO m) => Timeout -> [Poll s m] -> m [[Event]]
poll _    [] = return []
poll to desc = do
    let len = length desc
    let ps  = map toZMQPoll desc
    ps' <- liftIO $ withArray ps $ \ptr -> do
        throwIfMinus1Retry_ "poll" $
            c_zmq_poll ptr (fromIntegral len) (fromIntegral to)
        peekArray len ptr
    mapM fromZMQPoll (zip desc ps')
  where
    toZMQPoll :: (SocketLike s, MonadIO m) => Poll s m -> ZMQPoll
    toZMQPoll (Sock s e _) =
        ZMQPoll (_socket . _socketRepr . toSocket $ s) 0 (combine (map fromEvent e)) 0

    toZMQPoll (File (Fd s) e _) =
        ZMQPoll nullPtr (fromIntegral s) (combine (map fromEvent e)) 0

    fromZMQPoll :: (SocketLike s, MonadIO m) => (Poll s m, ZMQPoll) -> m [Event]
    fromZMQPoll (p, zp) = do
        let e = toEvents . fromIntegral . pRevents $ zp
        let (e', f) = case p of
                        (Sock _ x g) -> (x, g)
                        (File _ x g) -> (x, g)
        forM f (unless (P.null (e `intersect` e')) . ($ e)) >> return e

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

-- | Starts built-in 0MQ proxy
-- (cf. <http://api.zeromq.org/4-0:zmq-proxy zmq_proxy>)
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
    onSocket "proxy-back"  back  $ \b ->
        throwIfMinus1Retry_ "c_zmq_proxy" $ c_zmq_proxy f b c
  where
    c = maybe nullPtr (_socket . _socketRepr) capture

-- | Generate a new curve key pair.
-- (cf. <http://api.zeromq.org/4-0:zmq-curve-keypair zmq_curve_keypair>)
curveKeyPair :: MonadIO m => m (Restricted Div5 SB.ByteString, Restricted Div5 SB.ByteString)
curveKeyPair = liftIO $
    allocaBytes 41 $ \cstr1 ->
    allocaBytes 41 $ \cstr2 -> do
        throwIfMinus1_ "c_zmq_curve_keypair" $ c_zmq_curve_keypair cstr1 cstr2
        public  <- toRestricted <$> SB.packCString cstr1
        private <- toRestricted <$> SB.packCString cstr2
        maybe (fail errmsg) return ((,) <$> public <*> private)
      where
        errmsg = "curveKeyPair: invalid key-lengths produced"


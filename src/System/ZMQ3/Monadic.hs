{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- |
-- Module      : System.ZMQ3.Monadic
-- Copyright   : (c) 2013 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable

module System.ZMQ3.Monadic (

  -- * Type Definitions
    Context
  , Socket
  , Z.Switch (..)

  -- ** Type Classes
  , Z.SocketType
  , Z.Sender
  , Z.Receiver
  , Z.Subscriber

  -- ** Socket Types
  , Z.Event (..)
  , Z.Pair(..)
  , Z.Pub(..)
  , Z.Sub(..)
  , Z.XPub(..)
  , Z.XSub(..)
  , Z.Req(..)
  , Z.Rep(..)
  , Z.Dealer(..)
  , Z.Router(..)
  , Z.Pull(..)
  , Z.Push(..)

  -- * General Operations
  , version
  , runContext
  , forkContext
  , runSocket

  -- * Context Options (Read)
  , ioThreads
  , maxSockets

  -- * Context Options (Write)
  , setIoThreads
  , setMaxSockets

  -- * Socket operations
  , subscribe
  , unsubscribe
  , bind
  , unbind
  , connect
  , send
  , send'
  , sendMulti
  , receive
  , receiveMulti

  -- * Socket Options (Read)
  , affinity
  , backlog
  , delayAttachOnConnect
  , events
  , fileDescriptor
  , identity
  , ipv4Only
  , lastEndpoint
  , linger
  , maxMessageSize
  , mcastHops
  , moreToReceive
  , rate
  , receiveBuffer
  , receiveHighWM
  , receiveTimeout
  , reconnectInterval
  , reconnectIntervalMax
  , recoveryInterval
  , sendBuffer
  , sendHighWM
  , sendTimeout
  , tcpKeepAlive
  , tcpKeepAliveCount
  , tcpKeepAliveIdle
  , tcpKeepAliveInterval

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

  -- * Error Handling
  , Z.ZMQError
  , Z.errno
  , Z.source
  , Z.message

  -- * Re-exports
  , Control.Monad.IO.Class.liftIO
  , Data.Restricted.restrict
  , Data.Restricted.toRestricted

  -- * Low-level Functions
  , waitRead
  , waitWrite

) where

import Control.Applicative
import Control.Concurrent (ThreadId, forkIO)
import Control.Exception (bracket, finally)
import Control.Monad
import Control.Monad.Trans.Reader
import Control.Monad.IO.Class
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import Data.Int
import Data.IORef
import Data.Restricted
import Data.Word
import System.Posix.Types (Fd(..))
import qualified System.ZMQ3 as Z

data CtxEnv = CtxEnv {
    _refcount :: !(IORef Word)
  , _context  :: !Z.Context
  }

newtype Context a = Context {
    _ctxenv :: ReaderT CtxEnv IO a
  } deriving (Functor, Applicative, Monad, MonadIO)

runContext :: MonadIO m => Context a -> m a
runContext c = liftIO $ bracket make destroy (runReaderT (_ctxenv c))
  where
    make = CtxEnv <$> newIORef 1 <*> Z.context

forkContext :: Context a -> Context ThreadId
forkContext c = Context $ do
    env <- ask
    _   <- liftIO $ atomicModifyIORef' (_refcount env) $ \n -> (succ n, ())
    liftIO $ forkIO $
        (runReaderT (_ctxenv c) env >> return ()) `finally` destroy env

ioThreads :: Context Word
ioThreads = onContext Z.ioThreads

setIoThreads :: Word -> Context ()
setIoThreads = onContext . Z.setIoThreads

maxSockets :: Context Word
maxSockets = onContext Z.maxSockets

setMaxSockets :: Word -> Context ()
setMaxSockets = onContext . Z.setMaxSockets

version :: Context (Int, Int, Int)
version = liftIO Z.version

newtype Socket t a = Socket {
    _socket :: ReaderT (Z.Socket t) IO a
  } deriving (Functor, Applicative, Monad, MonadIO)

runSocket :: Z.SocketType t => t -> Socket t a -> Context a
runSocket t s = onContext $ \c ->
    bracket (Z.socket c t) Z.close (runReaderT (_socket s))

subscribe :: Z.Subscriber t => String -> Socket t ()
subscribe = onSocket . flip Z.subscribe

unsubscribe :: Z.Subscriber t => String -> Socket t ()
unsubscribe = onSocket . flip Z.unsubscribe

bind :: String -> Socket t ()
bind = onSocket . flip Z.bind

unbind :: String -> Socket t ()
unbind = onSocket . flip Z.unbind

connect :: String -> Socket t ()
connect = onSocket . flip Z.connect

send :: Z.Sender t => [Z.Flag] -> SB.ByteString -> Socket t ()
send fs bs = onSocket $ \s -> Z.send s fs bs

sendMulti :: Z.Sender t => [SB.ByteString] -> Socket t ()
sendMulti = onSocket . flip Z.sendMulti

send' :: Z.Sender t => [Z.Flag] -> LB.ByteString -> Socket t ()
send' fs bs = onSocket $ \s -> Z.send' s fs bs

receive :: Z.Receiver t => Socket t SB.ByteString
receive = onSocket Z.receive

receiveMulti :: Z.Receiver t => Socket t [SB.ByteString]
receiveMulti = onSocket Z.receiveMulti

waitRead :: Socket t ()
waitRead = onSocket Z.waitRead

waitWrite :: Socket t ()
waitWrite = onSocket Z.waitWrite

affinity :: Socket t Word64
affinity = onSocket Z.affinity

backlog :: Socket t Int
backlog = onSocket Z.backlog

delayAttachOnConnect :: Socket t Bool
delayAttachOnConnect = onSocket Z.delayAttachOnConnect

events :: Socket t Z.Event
events = onSocket Z.events

fileDescriptor :: Socket t Fd
fileDescriptor = onSocket Z.fileDescriptor

identity :: Socket t String
identity = onSocket Z.identity

ipv4Only :: Socket t Bool
ipv4Only = onSocket Z.ipv4Only

lastEndpoint :: Socket t String
lastEndpoint = onSocket Z.lastEndpoint

linger :: Socket t Int
linger = onSocket Z.linger

maxMessageSize :: Socket t Int64
maxMessageSize = onSocket Z.maxMessageSize

mcastHops :: Socket t Int
mcastHops = onSocket Z.mcastHops

moreToReceive :: Socket t Bool
moreToReceive = onSocket Z.moreToReceive

rate :: Socket t Int
rate = onSocket Z.rate

receiveBuffer :: Socket t Int
receiveBuffer = onSocket Z.receiveBuffer

receiveHighWM :: Socket t Int
receiveHighWM = onSocket Z.receiveHighWM

receiveTimeout :: Socket t Int
receiveTimeout = onSocket Z.receiveTimeout

reconnectInterval :: Socket t Int
reconnectInterval = onSocket Z.reconnectInterval

reconnectIntervalMax :: Socket t Int
reconnectIntervalMax = onSocket Z.reconnectIntervalMax

recoveryInterval :: Socket t Int
recoveryInterval = onSocket Z.recoveryInterval

sendBuffer :: Socket t Int
sendBuffer = onSocket Z.sendBuffer

sendHighWM :: Socket t Int
sendHighWM = onSocket Z.sendHighWM

sendTimeout :: Socket t Int
sendTimeout = onSocket Z.sendTimeout

tcpKeepAlive :: Socket t Z.Switch
tcpKeepAlive = onSocket Z.tcpKeepAlive

tcpKeepAliveCount :: Socket t Int
tcpKeepAliveCount = onSocket Z.tcpKeepAliveCount

tcpKeepAliveIdle :: Socket t Int
tcpKeepAliveIdle = onSocket Z.tcpKeepAliveIdle

tcpKeepAliveInterval :: Socket t Int
tcpKeepAliveInterval = onSocket Z.tcpKeepAliveInterval

setAffinity :: Word64 -> Socket t ()
setAffinity = onSocket . Z.setAffinity

setBacklog :: Integral i => Restricted N0 Int32 i -> Socket t ()
setBacklog = onSocket . Z.setBacklog

setDelayAttachOnConnect :: Bool -> Socket t ()
setDelayAttachOnConnect = onSocket . Z.setDelayAttachOnConnect

setIdentity :: Restricted N1 N254 String -> Socket t ()
setIdentity = onSocket . Z.setIdentity

setIpv4Only :: Bool -> Socket t ()
setIpv4Only = onSocket . Z.setIpv4Only

setLinger :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setLinger = onSocket . Z.setLinger

setMaxMessageSize :: Integral i => Restricted Nneg1 Int64 i -> Socket t ()
setMaxMessageSize = onSocket . Z.setMaxMessageSize

setMcastHops :: Integral i => Restricted N1 Int32 i -> Socket t ()
setMcastHops = onSocket . Z.setMcastHops

setRate :: Integral i => Restricted N1 Int32 i -> Socket t ()
setRate = onSocket . Z.setRate

setReceiveBuffer :: Integral i => Restricted N0 Int32 i -> Socket t ()
setReceiveBuffer = onSocket . Z.setReceiveBuffer

setReceiveHighWM :: Integral i => Restricted N0 Int32 i -> Socket t ()
setReceiveHighWM = onSocket . Z.setReceiveHighWM

setReceiveTimeout :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setReceiveTimeout = onSocket . Z.setReceiveTimeout

setReconnectInterval :: Integral i => Restricted N0 Int32 i -> Socket t ()
setReconnectInterval = onSocket . Z.setReconnectInterval

setReconnectIntervalMax :: Integral i => Restricted N0 Int32 i -> Socket t ()
setReconnectIntervalMax = onSocket . Z.setReconnectIntervalMax

setRecoveryInterval :: Integral i => Restricted N0 Int32 i -> Socket t ()
setRecoveryInterval = onSocket . Z.setRecoveryInterval

setRouterMandatory :: Bool -> Socket Z.Router ()
setRouterMandatory = onSocket . Z.setRouterMandatory

setSendBuffer :: Integral i => Restricted N0 Int32 i -> Socket t ()
setSendBuffer = onSocket . Z.setSendBuffer

setSendHighWM :: Integral i => Restricted N0 Int32 i -> Socket t ()
setSendHighWM = onSocket . Z.setSendHighWM

setSendTimeout :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setSendTimeout = onSocket . Z.setSendTimeout

setTcpAcceptFilter :: Maybe String -> Socket t ()
setTcpAcceptFilter = onSocket . Z.setTcpAcceptFilter

setTcpKeepAlive :: Z.Switch -> Socket t ()
setTcpKeepAlive = onSocket . Z.setTcpKeepAlive

setTcpKeepAliveCount :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setTcpKeepAliveCount = onSocket . Z.setTcpKeepAliveCount

setTcpKeepAliveIdle :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setTcpKeepAliveIdle = onSocket . Z.setTcpKeepAliveIdle

setTcpKeepAliveInterval :: Integral i => Restricted Nneg1 Int32 i -> Socket t ()
setTcpKeepAliveInterval = onSocket . Z.setTcpKeepAliveInterval

setXPubVerbose :: Bool -> Socket Z.XPub ()
setXPubVerbose = onSocket . Z.setXPubVerbose

-- Internal

onContext :: (Z.Context -> IO a) -> Context a
onContext f = Context $ asks _context >>= liftIO . f

destroy :: CtxEnv -> IO ()
destroy env = do
    n <- atomicModifyIORef' (_refcount env) $ \n -> (pred n, n)
    when (n == 1) $
        Z.destroy (_context env)

onSocket :: (Z.Socket t -> IO a) -> Socket t a
onSocket f = Socket $ ask >>= liftIO . f

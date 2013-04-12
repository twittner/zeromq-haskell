{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
{-# LANGUAGE CPP #-}
-- |
-- Module      : System.ZMQ3.Monadic
-- Copyright   : (c) 2013 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable

module System.ZMQ3.Monadic (

  -- * Type Definitions
    ZMQ
  , MonadZMQ (..)
  , Z.Socket
  , Z.Flag (SendMore)
  , Z.Switch (..)
  , Z.Timeout
  , Z.Event (..)
  , Z.EventType (..)
  , Z.EventMsg (..)
  , Z.Poll (..)

  -- ** Type Classes
  , Z.SocketType
  , Z.Sender
  , Z.Receiver
  , Z.Subscriber

  -- ** Socket Types
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
  , runZMQ
  , async
  , socket

  -- * ZMQ Options (Read)
  , ioThreads
  , maxSockets

  -- * ZMQ Options (Write)
  , setIoThreads
  , setMaxSockets

  -- * Socket operations
  , close
  , bind
  , unbind
  , connect
  , send
  , send'
  , sendMulti
  , receive
  , receiveMulti
  , subscribe
  , unsubscribe
  , proxy
  , monitor
  , Z.poll

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

import Prelude hiding (catch)
import Control.Applicative
import Control.Concurrent (forkIO)
import Control.Monad
import Control.Monad.Trans.Reader
import Control.Monad.IO.Class
import Control.Monad.CatchIO
import Data.Int
import Data.IORef
import Data.Restricted
import Data.Word
import Data.ByteString (ByteString)
import System.Posix.Types (Fd)
import qualified Data.ByteString.Lazy as Lazy
import qualified Control.Exception as E
import qualified System.ZMQ3 as Z
import qualified System.ZMQ3.Internal as I

data ZMQEnv = ZMQEnv
  { _refcount :: !(IORef Word)
  , _context  :: !Z.Context
  , _sockets  :: !(IORef [I.SocketRepr])
  }

newtype ZMQ a = ZMQ {
    _unzmq :: ReaderT ZMQEnv IO a
  }

class ( Monad m
      , MonadIO m
      , MonadCatchIO m
      , MonadPlus m
      , Functor m
      , Applicative m
      , Alternative m
      ) => MonadZMQ m
  where
    liftZMQ :: ZMQ a -> m a

instance MonadZMQ ZMQ where
    liftZMQ = id

instance Monad ZMQ where
    return = ZMQ . return
    (ZMQ m) >>= f = ZMQ $! m >>= _unzmq . f

instance MonadIO ZMQ where
    liftIO m = ZMQ $! liftIO m

instance MonadCatchIO ZMQ where
    catch (ZMQ m) f = ZMQ $! m `catch` (_unzmq . f)
    block (ZMQ m) = ZMQ $! block m
    unblock (ZMQ m) = ZMQ $! unblock m

instance Functor ZMQ where
    fmap = liftM

instance Applicative ZMQ where
    pure  = return
    (<*>) = ap

instance MonadPlus ZMQ where
    mzero = ZMQ $! mzero
    (ZMQ m) `mplus` (ZMQ n) = ZMQ $! m `mplus` n

instance Alternative ZMQ where
    empty = mzero
    (<|>) = mplus

runZMQ :: MonadIO m => ZMQ a -> m a
runZMQ z = liftIO $ E.bracket make destroy (runReaderT (_unzmq z))
  where
    make = ZMQEnv <$> newIORef 1 <*> Z.context <*> newIORef []

async :: ZMQ a -> ZMQ ()
async z = ZMQ $ do
    e <- ask
    liftIO $ atomicModifyIORef' (_refcount e) $ \n -> (succ n, ())
    liftIO . forkIO $ (runReaderT (_unzmq z) e >> return ()) `E.finally` destroy e
    return ()

ioThreads :: MonadZMQ m => m Word
ioThreads = onContext Z.ioThreads

setIoThreads :: MonadZMQ m => Word -> m ()
setIoThreads = onContext . Z.setIoThreads

maxSockets :: MonadZMQ m => m Word
maxSockets = onContext Z.maxSockets

setMaxSockets :: MonadZMQ m => Word -> m ()
setMaxSockets = onContext . Z.setMaxSockets

socket :: (MonadZMQ m, Z.SocketType t) => t -> m (Z.Socket t)
socket t = liftZMQ $! ZMQ $ do
    c <- asks _context
    s <- asks _sockets
    x <- liftIO $ I.mkSocketRepr t c
    liftIO $ atomicModifyIORef' s $ \ss -> (x:ss, ())
    return (I.Socket x)

version :: MonadZMQ m => m (Int, Int, Int)
version = liftIO $! Z.version

-- * Socket operations

close :: MonadZMQ m => Z.Socket t -> m ()
close = liftIO . Z.close

bind :: MonadZMQ m => Z.Socket t -> String -> m ()
bind s = liftIO . Z.bind s

unbind :: MonadZMQ m => Z.Socket t -> String -> m ()
unbind s = liftIO . Z.unbind s

connect :: MonadZMQ m => Z.Socket t -> String -> m ()
connect s = liftIO . Z.connect s

send :: (MonadZMQ m, Z.Sender t) => Z.Socket t -> [Z.Flag] -> ByteString -> m ()
send s f = liftIO . Z.send s f

send' :: (MonadZMQ m, Z.Sender t) => Z.Socket t -> [Z.Flag] -> Lazy.ByteString -> m ()
send' s f = liftIO . Z.send' s f

sendMulti :: (MonadZMQ m, Z.Sender t) => Z.Socket t -> [ByteString] -> m ()
sendMulti s = liftIO . Z.sendMulti s

receive :: (MonadZMQ m, Z.Receiver t) => Z.Socket t -> m ByteString
receive = liftIO . Z.receive

receiveMulti :: (MonadZMQ m, Z.Receiver t) => Z.Socket t -> m [ByteString]
receiveMulti = liftIO . Z.receiveMulti

subscribe :: (MonadZMQ m, Z.Subscriber t) => Z.Socket t -> ByteString -> m ()
subscribe s = liftIO . Z.subscribe s

unsubscribe :: (MonadZMQ m, Z.Subscriber t) => Z.Socket t -> ByteString -> m ()
unsubscribe s = liftIO . Z.unsubscribe s

proxy :: MonadZMQ m => Z.Socket a -> Z.Socket b -> Maybe (Z.Socket c) -> m ()
proxy a b = liftIO . Z.proxy a b

monitor :: MonadZMQ m => [Z.EventType] -> Z.Socket t -> m (Bool -> IO (Maybe Z.EventMsg))
monitor es s = onContext $ \ctx -> Z.monitor es ctx s

-- * Socket Options (Read)

affinity :: MonadZMQ m => Z.Socket t -> m Word64
affinity = liftIO . Z.affinity

backlog :: MonadZMQ m => Z.Socket t -> m Int
backlog = liftIO . Z.backlog

delayAttachOnConnect :: MonadZMQ m => Z.Socket t -> m Bool
delayAttachOnConnect = liftIO . Z.delayAttachOnConnect

events :: MonadZMQ m => Z.Socket t -> m [Z.Event]
events = liftIO . Z.events

fileDescriptor :: MonadZMQ m => Z.Socket t -> m Fd
fileDescriptor = liftIO . Z.fileDescriptor

identity :: MonadZMQ m => Z.Socket t -> m ByteString
identity = liftIO . Z.identity

ipv4Only :: MonadZMQ m => Z.Socket t -> m Bool
ipv4Only = liftIO . Z.ipv4Only

lastEndpoint :: MonadZMQ m => Z.Socket t -> m String
lastEndpoint = liftIO . Z.lastEndpoint

linger :: MonadZMQ m => Z.Socket t -> m Int
linger = liftIO . Z.linger

maxMessageSize :: MonadZMQ m => Z.Socket t -> m Int64
maxMessageSize = liftIO . Z.maxMessageSize

mcastHops :: MonadZMQ m => Z.Socket t -> m Int
mcastHops = liftIO . Z.mcastHops

moreToReceive :: MonadZMQ m => Z.Socket t -> m Bool
moreToReceive = liftIO . Z.moreToReceive

rate :: MonadZMQ m => Z.Socket t -> m Int
rate = liftIO . Z.rate

receiveBuffer :: MonadZMQ m => Z.Socket t -> m Int
receiveBuffer = liftIO . Z.receiveBuffer

receiveHighWM :: MonadZMQ m => Z.Socket t -> m Int
receiveHighWM = liftIO . Z.receiveHighWM

receiveTimeout :: MonadZMQ m => Z.Socket t -> m Int
receiveTimeout = liftIO . Z.receiveTimeout

reconnectInterval :: MonadZMQ m => Z.Socket t -> m Int
reconnectInterval = liftIO . Z.reconnectInterval

reconnectIntervalMax :: MonadZMQ m => Z.Socket t -> m Int
reconnectIntervalMax = liftIO . Z.reconnectIntervalMax

recoveryInterval :: MonadZMQ m => Z.Socket t -> m Int
recoveryInterval = liftIO . Z.recoveryInterval

sendBuffer :: MonadZMQ m => Z.Socket t -> m Int
sendBuffer = liftIO . Z.sendBuffer

sendHighWM :: MonadZMQ m => Z.Socket t -> m Int
sendHighWM = liftIO . Z.sendHighWM

sendTimeout :: MonadZMQ m => Z.Socket t -> m Int
sendTimeout = liftIO . Z.sendTimeout

tcpKeepAlive :: MonadZMQ m => Z.Socket t -> m Z.Switch
tcpKeepAlive = liftIO . Z.tcpKeepAlive

tcpKeepAliveCount :: MonadZMQ m => Z.Socket t -> m Int
tcpKeepAliveCount = liftIO . Z.tcpKeepAliveCount

tcpKeepAliveIdle :: MonadZMQ m => Z.Socket t -> m Int
tcpKeepAliveIdle = liftIO . Z.tcpKeepAliveIdle

tcpKeepAliveInterval :: MonadZMQ m => Z.Socket t -> m Int
tcpKeepAliveInterval = liftIO . Z.tcpKeepAliveInterval

-- * Socket Options (Write)

setAffinity :: MonadZMQ m => Word64 -> Z.Socket t -> m ()
setAffinity a = liftIO . Z.setAffinity a

setBacklog :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setBacklog b = liftIO . Z.setBacklog b

setDelayAttachOnConnect :: MonadZMQ m => Bool -> Z.Socket t -> m ()
setDelayAttachOnConnect d = liftIO . Z.setDelayAttachOnConnect d

setIdentity :: MonadZMQ m => Restricted N1 N254 ByteString -> Z.Socket t -> m ()
setIdentity i = liftIO . Z.setIdentity i

setIpv4Only :: MonadZMQ m => Bool -> Z.Socket t -> m ()
setIpv4Only i = liftIO . Z.setIpv4Only i

setLinger :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setLinger l = liftIO . Z.setLinger l

setMaxMessageSize :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int64 i -> Z.Socket t -> m ()
setMaxMessageSize s = liftIO . Z.setMaxMessageSize s

setMcastHops :: (MonadZMQ m, Integral i) => Restricted N1 Int32 i -> Z.Socket t -> m ()
setMcastHops k = liftIO . Z.setMcastHops k

setRate :: (MonadZMQ m, Integral i) => Restricted N1 Int32 i -> Z.Socket t -> m ()
setRate r = liftIO . Z.setRate r

setReceiveBuffer :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setReceiveBuffer k = liftIO . Z.setReceiveBuffer k

setReceiveHighWM :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setReceiveHighWM k = liftIO . Z.setReceiveHighWM k

setReceiveTimeout :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setReceiveTimeout t = liftIO . Z.setReceiveTimeout t

setReconnectInterval :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setReconnectInterval i = liftIO . Z.setReconnectInterval i

setReconnectIntervalMax :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setReconnectIntervalMax i = liftIO . Z.setReconnectIntervalMax i

setRecoveryInterval :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setRecoveryInterval i = liftIO . Z.setRecoveryInterval i

setRouterMandatory :: MonadZMQ m => Bool -> Z.Socket Z.Router -> m ()
setRouterMandatory b = liftIO . Z.setRouterMandatory b

setSendBuffer :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setSendBuffer i = liftIO . Z.setSendBuffer i

setSendHighWM :: (MonadZMQ m, Integral i) => Restricted N0 Int32 i -> Z.Socket t -> m ()
setSendHighWM i = liftIO . Z.setSendHighWM i

setSendTimeout :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setSendTimeout i = liftIO . Z.setSendTimeout i

setTcpAcceptFilter :: MonadZMQ m => Maybe ByteString -> Z.Socket t -> m ()
setTcpAcceptFilter s = liftIO . Z.setTcpAcceptFilter s

setTcpKeepAlive :: MonadZMQ m => Z.Switch -> Z.Socket t -> m ()
setTcpKeepAlive s = liftIO . Z.setTcpKeepAlive s

setTcpKeepAliveCount :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setTcpKeepAliveCount c = liftIO . Z.setTcpKeepAliveCount c

setTcpKeepAliveIdle :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setTcpKeepAliveIdle i = liftIO . Z.setTcpKeepAliveIdle i

setTcpKeepAliveInterval :: (MonadZMQ m, Integral i) => Restricted Nneg1 Int32 i -> Z.Socket t -> m ()
setTcpKeepAliveInterval i = liftIO . Z.setTcpKeepAliveInterval i

setXPubVerbose :: MonadZMQ m => Bool -> Z.Socket Z.XPub -> m ()
setXPubVerbose b = liftIO . Z.setXPubVerbose b

-- * Low Level Functions

waitRead :: MonadZMQ m => Z.Socket t -> m ()
waitRead = liftIO . Z.waitRead

waitWrite :: MonadZMQ m => Z.Socket t -> m ()
waitWrite = liftIO . Z.waitWrite

-- * Internal

onContext :: MonadZMQ m => (Z.Context -> IO a) -> m a
onContext f = liftZMQ $! ZMQ $! asks _context >>= liftIO . f

destroy :: ZMQEnv -> IO ()
destroy env = do
    n <- atomicModifyIORef' (_refcount env) $ \n -> (pred n, n)
    when (n == 1) $ do
        readIORef (_sockets env) >>= mapM_ close'
        Z.destroy (_context env)
  where
    close' s = I.closeSock s `E.catch` (\e -> print (e :: E.SomeException))

-- Back compatibility hacks
#if !MIN_VERSION_base(4,6,0)
-- | Strict version of 'atomicModifyIORef'.  This forces both the value stored
-- in the 'IORef' as well as the value returned.
atomicModifyIORef' :: IORef a -> (a -> (a,b)) -> IO b
atomicModifyIORef' ref f = do
    b <- atomicModifyIORef ref
            (\x -> let (a, b) = f x
                    in (a, a `seq` b))
    b `seq` return b
#endif

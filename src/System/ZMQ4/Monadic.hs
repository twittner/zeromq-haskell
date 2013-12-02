{-# LANGUAGE RankNTypes                         #-}
{-# OPTIONS_GHC -fno-warn-warnings-deprecations #-}

-- |
-- Module      : System.ZMQ4.Monadic
-- Copyright   : (c) 2013 Toralf Wittner
-- License     : MIT
-- Maintainer  : Toralf Wittner <tw@dtex.org>
-- Stability   : experimental
-- Portability : non-portable
--
-- This modules exposes a monadic interface of 'System.ZMQ4'. Actions run
-- inside a 'ZMQ' monad and 'Socket's are guaranteed not to leak outside
-- their corresponding 'runZMQ' scope. Running 'ZMQ' computations
-- asynchronously is directly supported through 'async'.
module System.ZMQ4.Monadic
  ( -- * Type Definitions
    ZMQ
  , Socket
  , Z.Flag              (SendMore)
  , Z.Switch            (..)
  , Z.Timeout
  , Z.Event             (..)
  , Z.EventType         (..)
  , Z.EventMsg          (..)
  , Z.Poll              (..)
  , Z.KeyFormat         (..)
  , Z.SecurityMechanism (..)

  -- ** Socket type-classes
  , Z.SocketType
  , Z.Sender
  , Z.Receiver
  , Z.Subscriber
  , Z.SocketLike
  , Z.Conflatable
  , Z.SendProbe

  -- ** Socket Types
  , Z.Pair   (..)
  , Z.Pub    (..)
  , Z.Sub    (..)
  , Z.XPub   (..)
  , Z.XSub   (..)
  , Z.Req    (..)
  , Z.Rep    (..)
  , Z.Dealer (..)
  , Z.Router (..)
  , Z.Pull   (..)
  , Z.Push   (..)
  , Z.Stream (..)

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
  , conflate
  , curvePublicKey
  , curveSecretKey
  , curveServerKey
  , delayAttachOnConnect
  , events
  , fileDescriptor
  , identity
  , immediate
  , ipv4Only
  , ipv6
  , lastEndpoint
  , linger
  , maxMessageSize
  , mcastHops
  , mechanism
  , moreToReceive
  , plainServer
  , plainPassword
  , plainUserName
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
  , zapDomain

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
  , I.z85Encode
  , I.z85Decode
  , Z.curveKeyPair
  ) where

import Control.Applicative
import Control.Concurrent.Async (Async)
import Control.Monad
import Control.Monad.Trans.Reader
import Control.Monad.IO.Class
import Control.Monad.Catch
import Control.Monad.CatchIO
import Data.Int
import Data.IORef
import Data.List.NonEmpty (NonEmpty)
import Data.Restricted
import Data.Word
import Data.ByteString (ByteString)
import System.Posix.Types (Fd)

import qualified Control.Concurrent.Async as A
import qualified Control.Exception        as E
import qualified Control.Monad.Catch      as C
import qualified Control.Monad.CatchIO    as M
import qualified Data.ByteString.Lazy     as Lazy
import qualified System.ZMQ4              as Z
import qualified System.ZMQ4.Internal     as I

data ZMQEnv = ZMQEnv
  { _refcount :: !(IORef Word)
  , _context  :: !Z.Context
  , _sockets  :: !(IORef [I.SocketRepr])
  }

-- | The ZMQ monad is modeled after 'Control.Monad.ST' and encapsulates
-- a 'System.ZMQ4.Context'. It uses the uninstantiated type variable 'z' to
-- distinguish different invoctions of 'runZMQ' and to prevent
-- unintented use of 'Socket's outside their scope. Cf. the paper
-- of John Launchbury and Simon Peyton Jones /Lazy Functional State Threads/.
newtype ZMQ z a = ZMQ { _unzmq :: ReaderT ZMQEnv IO a }

-- | The ZMQ socket, parameterised by 'SocketType' and belonging to
-- a particular 'ZMQ' thread.
newtype Socket z t = Socket { _unsocket :: Z.Socket t }

instance I.SocketLike (Socket z) where
    toSocket = _unsocket

instance Monad (ZMQ z) where
    return = ZMQ . return
    (ZMQ m) >>= f = ZMQ $ m >>= _unzmq . f

instance MonadIO (ZMQ z) where
    liftIO m = ZMQ $! liftIO m

instance MonadCatch (ZMQ z) where
    throwM          = ZMQ . C.throwM
    catch (ZMQ m) f = ZMQ $ m `C.catch` (_unzmq . f)

    mask a = ZMQ . ReaderT $ \env ->
        C.mask $ \restore ->
            let f (ZMQ (ReaderT b)) = ZMQ $ ReaderT (restore . b)
            in runReaderT (_unzmq (a $ f)) env

    uninterruptibleMask a = ZMQ . ReaderT $ \env ->
        C.uninterruptibleMask $ \restore ->
            let f (ZMQ (ReaderT b)) = ZMQ $ ReaderT (restore . b)
            in runReaderT (_unzmq (a $ f)) env

instance MonadCatchIO (ZMQ z) where
    catch (ZMQ m) f = ZMQ $ m `M.catch` (_unzmq . f)
    block (ZMQ m)   = ZMQ $ block m
    unblock (ZMQ m) = ZMQ $ unblock m

instance Functor (ZMQ z) where
    fmap = liftM

instance Applicative (ZMQ z) where
    pure  = return
    (<*>) = ap

-- | Return the value computed by the given 'ZMQ' monad. Rank-2
-- polymorphism is used to prevent leaking of 'z'.
-- An invocation of 'runZMQ' will internally create a 'System.ZMQ4.Context'
-- and all actions are executed relative to this context. On finish the
-- context will be disposed, but see 'async'.
runZMQ :: MonadIO m => (forall z. ZMQ z a) -> m a
runZMQ z = liftIO $ E.bracket make term (runReaderT (_unzmq z))
  where
    make = ZMQEnv <$> newIORef 1 <*> Z.context <*> newIORef []

-- | Run the given 'ZMQ' computation asynchronously, i.e. this function
-- runs the computation in a new thread using 'Control.Concurrent.Async.async'.
-- /N.B./ reference counting is used to prolong the lifetime of the
-- 'System.ZMQ.Context' encapsulated in 'ZMQ' as necessary, e.g.:
--
-- @
-- runZMQ $ do
--     s <- socket Pair
--     async $ do
--         liftIO (threadDelay 10000000)
--         identity s >>= liftIO . print
-- @
--
-- Here, 'runZMQ' will finish before the code section in 'async', but due to
-- reference counting, the 'System.ZMQ4.Context' will only be disposed after
-- 'async' finishes as well.
async :: ZMQ z a -> ZMQ z (Async a)
async z = ZMQ $ do
    e <- ask
    liftIO $ atomicModifyIORef (_refcount e) $ \n -> (succ n, ())
    liftIO . A.async $ (runReaderT (_unzmq z) e) `E.finally` term e

ioThreads :: ZMQ z Word
ioThreads = onContext Z.ioThreads

setIoThreads :: Word -> ZMQ z ()
setIoThreads = onContext . Z.setIoThreads

maxSockets :: ZMQ z Word
maxSockets = onContext Z.maxSockets

setMaxSockets :: Word -> ZMQ z ()
setMaxSockets = onContext . Z.setMaxSockets

socket :: Z.SocketType t => t -> ZMQ z (Socket z t)
socket t = ZMQ $ do
    c <- asks _context
    s <- asks _sockets
    x <- liftIO $ I.mkSocketRepr t c
    liftIO $ atomicModifyIORef s $ \ss -> (x:ss, ())
    return (Socket (I.Socket x))

version :: ZMQ z (Int, Int, Int)
version = liftIO $! Z.version

-- * Socket operations

close :: Socket z t -> ZMQ z ()
close = liftIO . Z.close . _unsocket

bind :: Socket z t -> String -> ZMQ z ()
bind s = liftIO . Z.bind (_unsocket s)

unbind :: Socket z t -> String -> ZMQ z ()
unbind s = liftIO . Z.unbind (_unsocket s)

connect :: Socket z t -> String -> ZMQ z ()
connect s = liftIO . Z.connect (_unsocket s)

send :: Z.Sender t => Socket z t -> [Z.Flag] -> ByteString -> ZMQ z ()
send s f = liftIO . Z.send (_unsocket s) f

send' :: Z.Sender t => Socket z t -> [Z.Flag] -> Lazy.ByteString -> ZMQ z ()
send' s f = liftIO . Z.send' (_unsocket s) f

sendMulti :: Z.Sender t => Socket z t -> NonEmpty ByteString -> ZMQ z ()
sendMulti s = liftIO . Z.sendMulti (_unsocket s)

receive :: Z.Receiver t => Socket z t -> ZMQ z ByteString
receive = liftIO . Z.receive . _unsocket

receiveMulti :: Z.Receiver t => Socket z t -> ZMQ z [ByteString]
receiveMulti = liftIO . Z.receiveMulti . _unsocket

subscribe :: Z.Subscriber t => Socket z t -> ByteString -> ZMQ z ()
subscribe s = liftIO . Z.subscribe (_unsocket s)

unsubscribe :: Z.Subscriber t => Socket z t -> ByteString -> ZMQ z ()
unsubscribe s = liftIO . Z.unsubscribe (_unsocket s)

proxy :: Socket z a -> Socket z b -> Maybe (Socket z c) -> ZMQ z ()
proxy a b c = liftIO $ Z.proxy (_unsocket a) (_unsocket b) (_unsocket <$> c)

monitor :: [Z.EventType] -> Socket z t -> ZMQ z (Bool -> IO (Maybe Z.EventMsg))
monitor es s = onContext $ \ctx -> Z.monitor es ctx (_unsocket s)

-- * Socket Options (Read)

affinity :: Socket z t -> ZMQ z Word64
affinity = liftIO . Z.affinity . _unsocket

backlog :: Socket z t -> ZMQ z Int
backlog = liftIO . Z.backlog . _unsocket

conflate :: Z.Conflatable t => Socket z t -> ZMQ z Bool
conflate = liftIO . Z.conflate . _unsocket

curvePublicKey :: Z.KeyFormat f -> Socket z t -> ZMQ z ByteString
curvePublicKey f = liftIO . Z.curvePublicKey f . _unsocket

curveSecretKey :: Z.KeyFormat f -> Socket z t -> ZMQ z ByteString
curveSecretKey f = liftIO . Z.curveSecretKey f . _unsocket

curveServerKey :: Z.KeyFormat f -> Socket z t -> ZMQ z ByteString
curveServerKey f = liftIO . Z.curveServerKey f . _unsocket

delayAttachOnConnect :: Socket z t -> ZMQ z Bool
delayAttachOnConnect = liftIO . Z.delayAttachOnConnect . _unsocket
{-# DEPRECATED delayAttachOnConnect "Use immediate" #-}

events :: Socket z t -> ZMQ z [Z.Event]
events = liftIO . Z.events . _unsocket

fileDescriptor :: Socket z t -> ZMQ z Fd
fileDescriptor = liftIO . Z.fileDescriptor . _unsocket

identity :: Socket z t -> ZMQ z ByteString
identity = liftIO . Z.identity . _unsocket

immediate :: Socket z t -> ZMQ z Bool
immediate = liftIO . Z.immediate . _unsocket

ipv4Only :: Socket z t -> ZMQ z Bool
ipv4Only = liftIO . Z.ipv4Only . _unsocket
{-# DEPRECATED ipv4Only "Use ipv6" #-}

ipv6 :: Socket z t -> ZMQ z Bool
ipv6 = liftIO . Z.ipv6 . _unsocket

lastEndpoint :: Socket z t -> ZMQ z String
lastEndpoint = liftIO . Z.lastEndpoint . _unsocket

linger :: Socket z t -> ZMQ z Int
linger = liftIO . Z.linger . _unsocket

maxMessageSize :: Socket z t -> ZMQ z Int64
maxMessageSize = liftIO . Z.maxMessageSize . _unsocket

mcastHops :: Socket z t -> ZMQ z Int
mcastHops = liftIO . Z.mcastHops . _unsocket

mechanism :: Socket z t -> ZMQ z Z.SecurityMechanism
mechanism = liftIO . Z.mechanism . _unsocket

moreToReceive :: Socket z t -> ZMQ z Bool
moreToReceive = liftIO . Z.moreToReceive . _unsocket

plainServer :: Socket z t -> ZMQ z Bool
plainServer = liftIO . Z.plainServer . _unsocket

plainPassword :: Socket z t -> ZMQ z ByteString
plainPassword = liftIO . Z.plainPassword . _unsocket

plainUserName :: Socket z t -> ZMQ z ByteString
plainUserName = liftIO . Z.plainUserName . _unsocket

rate :: Socket z t -> ZMQ z Int
rate = liftIO . Z.rate . _unsocket

receiveBuffer :: Socket z t -> ZMQ z Int
receiveBuffer = liftIO . Z.receiveBuffer . _unsocket

receiveHighWM :: Socket z t -> ZMQ z Int
receiveHighWM = liftIO . Z.receiveHighWM . _unsocket

receiveTimeout :: Socket z t -> ZMQ z Int
receiveTimeout = liftIO . Z.receiveTimeout . _unsocket

reconnectInterval :: Socket z t -> ZMQ z Int
reconnectInterval = liftIO . Z.reconnectInterval . _unsocket

reconnectIntervalMax :: Socket z t -> ZMQ z Int
reconnectIntervalMax = liftIO . Z.reconnectIntervalMax . _unsocket

recoveryInterval :: Socket z t -> ZMQ z Int
recoveryInterval = liftIO . Z.recoveryInterval . _unsocket

sendBuffer :: Socket z t -> ZMQ z Int
sendBuffer = liftIO . Z.sendBuffer . _unsocket

sendHighWM :: Socket z t -> ZMQ z Int
sendHighWM = liftIO . Z.sendHighWM . _unsocket

sendTimeout :: Socket z t -> ZMQ z Int
sendTimeout = liftIO . Z.sendTimeout . _unsocket

tcpKeepAlive :: Socket z t -> ZMQ z Z.Switch
tcpKeepAlive = liftIO . Z.tcpKeepAlive . _unsocket

tcpKeepAliveCount :: Socket z t -> ZMQ z Int
tcpKeepAliveCount = liftIO . Z.tcpKeepAliveCount . _unsocket

tcpKeepAliveIdle :: Socket z t -> ZMQ z Int
tcpKeepAliveIdle = liftIO . Z.tcpKeepAliveIdle . _unsocket

tcpKeepAliveInterval :: Socket z t -> ZMQ z Int
tcpKeepAliveInterval = liftIO . Z.tcpKeepAliveInterval . _unsocket

zapDomain :: Socket z t -> ZMQ z ByteString
zapDomain = liftIO . Z.zapDomain . _unsocket

-- * Socket Options (Write)

setAffinity :: Word64 -> Socket z t -> ZMQ z ()
setAffinity a = liftIO . Z.setAffinity a . _unsocket

setBacklog :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setBacklog b = liftIO . Z.setBacklog b . _unsocket

setConflate :: Z.Conflatable t => Bool -> Socket z t -> ZMQ z ()
setConflate i = liftIO . Z.setConflate i . _unsocket

setCurvePublicKey :: Z.KeyFormat f -> Restricted f ByteString -> Socket z t -> ZMQ z ()
setCurvePublicKey f k = liftIO . Z.setCurvePublicKey f k . _unsocket

setCurveSecretKey :: Z.KeyFormat f -> Restricted f ByteString -> Socket z t -> ZMQ z ()
setCurveSecretKey f k = liftIO . Z.setCurveSecretKey f k . _unsocket

setCurveServer :: Bool -> Socket z t -> ZMQ z ()
setCurveServer b = liftIO . Z.setCurveServer b . _unsocket

setCurveServerKey :: Z.KeyFormat f -> Restricted f ByteString -> Socket z t -> ZMQ z ()
setCurveServerKey f k = liftIO . Z.setCurveServerKey f k . _unsocket

setDelayAttachOnConnect :: Bool -> Socket z t -> ZMQ z ()
setDelayAttachOnConnect d = liftIO . Z.setDelayAttachOnConnect d . _unsocket
{-# DEPRECATED setDelayAttachOnConnect "Use setImmediate" #-}

setIdentity :: Restricted (N1, N254) ByteString -> Socket z t -> ZMQ z ()
setIdentity i = liftIO . Z.setIdentity i . _unsocket

setImmediate :: Bool -> Socket z t -> ZMQ z ()
setImmediate i = liftIO . Z.setImmediate i . _unsocket

setIpv4Only :: Bool -> Socket z t -> ZMQ z ()
setIpv4Only i = liftIO . Z.setIpv4Only i . _unsocket
{-# DEPRECATED setIpv4Only "Use setIpv6" #-}

setIpv6 :: Bool -> Socket z t -> ZMQ z ()
setIpv6 i = liftIO . Z.setIpv6 i . _unsocket

setLinger :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setLinger l = liftIO . Z.setLinger l . _unsocket

setMaxMessageSize :: Integral i => Restricted (Nneg1, Int64) i -> Socket z t -> ZMQ z ()
setMaxMessageSize s = liftIO . Z.setMaxMessageSize s . _unsocket

setMcastHops :: Integral i => Restricted (N1, Int32) i -> Socket z t -> ZMQ z ()
setMcastHops k = liftIO . Z.setMcastHops k . _unsocket

setPlainServer :: Bool -> Socket z t -> ZMQ z ()
setPlainServer b = liftIO . Z.setPlainServer b . _unsocket

setPlainPassword :: Restricted (N1, N254) ByteString -> Socket z t -> ZMQ z ()
setPlainPassword s = liftIO . Z.setPlainPassword s . _unsocket

setPlainUserName :: Restricted (N1, N254) ByteString -> Socket z t -> ZMQ z ()
setPlainUserName s = liftIO . Z.setPlainUserName s . _unsocket

setProbeRouter :: Z.SendProbe t => Bool -> Socket z t -> ZMQ z ()
setProbeRouter b = liftIO . Z.setProbeRouter b . _unsocket

setRate :: Integral i => Restricted (N1, Int32) i -> Socket z t -> ZMQ z ()
setRate r = liftIO . Z.setRate r . _unsocket

setReceiveBuffer :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setReceiveBuffer k = liftIO . Z.setReceiveBuffer k . _unsocket

setReceiveHighWM :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setReceiveHighWM k = liftIO . Z.setReceiveHighWM k . _unsocket

setReceiveTimeout :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setReceiveTimeout t = liftIO . Z.setReceiveTimeout t . _unsocket

setReconnectInterval :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setReconnectInterval i = liftIO . Z.setReconnectInterval i . _unsocket

setReconnectIntervalMax :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setReconnectIntervalMax i = liftIO . Z.setReconnectIntervalMax i . _unsocket

setRecoveryInterval :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setRecoveryInterval i = liftIO . Z.setRecoveryInterval i . _unsocket

setReqCorrelate :: Bool -> Socket z Z.Req -> ZMQ z ()
setReqCorrelate b = liftIO . Z.setReqCorrelate b . _unsocket

setReqRelaxed :: Bool -> Socket z Z.Req -> ZMQ z ()
setReqRelaxed b = liftIO . Z.setReqRelaxed b . _unsocket

setRouterMandatory :: Bool -> Socket z Z.Router -> ZMQ z ()
setRouterMandatory b = liftIO . Z.setRouterMandatory b . _unsocket

setSendBuffer :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setSendBuffer i = liftIO . Z.setSendBuffer i . _unsocket

setSendHighWM :: Integral i => Restricted (N0, Int32) i -> Socket z t -> ZMQ z ()
setSendHighWM i = liftIO . Z.setSendHighWM i . _unsocket

setSendTimeout :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setSendTimeout i = liftIO . Z.setSendTimeout i . _unsocket

setTcpAcceptFilter :: Maybe ByteString -> Socket z t -> ZMQ z ()
setTcpAcceptFilter s = liftIO . Z.setTcpAcceptFilter s . _unsocket

setTcpKeepAlive :: Z.Switch -> Socket z t -> ZMQ z ()
setTcpKeepAlive s = liftIO . Z.setTcpKeepAlive s . _unsocket

setTcpKeepAliveCount :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setTcpKeepAliveCount c = liftIO . Z.setTcpKeepAliveCount c . _unsocket

setTcpKeepAliveIdle :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setTcpKeepAliveIdle i = liftIO . Z.setTcpKeepAliveIdle i . _unsocket

setTcpKeepAliveInterval :: Integral i => Restricted (Nneg1, Int32) i -> Socket z t -> ZMQ z ()
setTcpKeepAliveInterval i = liftIO . Z.setTcpKeepAliveInterval i . _unsocket

setXPubVerbose :: Bool -> Socket z Z.XPub -> ZMQ z ()
setXPubVerbose b = liftIO . Z.setXPubVerbose b . _unsocket

-- * Low Level Functions

waitRead :: Socket z t -> ZMQ z ()
waitRead = liftIO . Z.waitRead . _unsocket

waitWrite :: Socket z t -> ZMQ z ()
waitWrite = liftIO . Z.waitWrite . _unsocket

-- * Internal

onContext :: (Z.Context -> IO a) -> ZMQ z a
onContext f = ZMQ $! asks _context >>= liftIO . f

term :: ZMQEnv -> IO ()
term env = do
    n <- atomicModifyIORef (_refcount env) $ \n -> (pred n, n)
    when (n == 1) $ do
        readIORef (_sockets env) >>= mapM_ close'
        Z.term (_context env)
  where
    close' s = I.closeSock s `E.catch` (\e -> print (e :: E.SomeException))

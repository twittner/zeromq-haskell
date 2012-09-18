{-# LANGUAGE KindSignatures       #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module System.ZMQ3.Safe (

    -- * Type Definitions
    Z.Size
  , Context
  , Socket
  , Z.Flag (SendMore)
  , Z.Timeout
  , Z.Event (..)

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
  , Z.XReq
  , Z.XRep
  , Z.Pull(..)
  , Z.Push(..)

    -- * General Operations
  , context
  , socket
  , bind
  , connect
  , send
  , send'
  , sendMulti
  , receive
  , receiveMulti
  , Z.version

  , subscribe
  , unsubscribe

    -- * Socket Options (Read)
  , affinity
  , backlog
  , events
  , fileDescriptor
  , identity
  , ipv4Only
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

    -- * Socket Options (Write)
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

    -- * Restrictions
  , Data.Restricted.restrict
  , Data.Restricted.toRestricted

    -- * Error Handling
  , Z.ZMQError
  , Z.errno
  , Z.source
  , Z.message

) where

import Control.Monad.IO.Class
import Control.Scope
import Control.Scope.Internal
import Data.IORef (modifyIORef)
import Data.Restricted
import Data.Word
import Data.Int
import System.Posix.Types (Fd(..))
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified System.ZMQ3 as Z

newtype Context (m :: * -> *)   = Context Z.Context
newtype Socket  (m :: * -> *) a = Socket (Z.Socket a)

instance Resource Z.Context where
    dispose = Z.term

instance Resource (Z.Socket a) where
    dispose = Z.close

context :: MonadIO m => Z.Size -> ScopeT s m Z.Context (Context (ScopeT s m Z.Context))
context ioThreads = ScopeT $ do
    c <- liftIO $ Z.init ioThreads
    r <- ask
    liftIO $ modifyIORef r (c:)
    return (Context c)

socket :: (InScope m1 m2, MonadIO m2, Z.SocketType a)
       => Context m1
       -> a
       -> ScopeT s m2 (Z.Socket a) (Socket (ScopeT s m2 (Z.Socket a)) a)
socket (Context c) t = ScopeT $ do
    s <- liftIO $ Z.socket c t
    r <- ask
    liftIO $ modifyIORef r (s:)
    return (Socket s)

bind :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> String -> m2 ()
bind (Socket s) addr = liftIO $ Z.bind s addr

connect :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> String -> m2 ()
connect (Socket s) addr = liftIO $ Z.connect s addr

subscribe :: (InScope m1 m2, MonadIO m2, Z.Subscriber a) => Socket m1 a -> String -> m2 ()
subscribe (Socket s) x = liftIO $ Z.subscribe s x

unsubscribe :: (InScope m1 m2, MonadIO m2, Z.Subscriber a) => Socket m1 a -> String -> m2 ()
unsubscribe (Socket s) x = liftIO $ Z.unsubscribe s x

send :: (InScope m1 m2, MonadIO m2, Z.Sender a) => Socket m1 a -> [Z.Flag] -> SB.ByteString -> m2 ()
send (Socket s) fs str = liftIO $ Z.send s fs str

send' :: (InScope m1 m2, MonadIO m2, Z.Sender a) => Socket m1 a -> [Z.Flag] -> LB.ByteString -> m2 ()
send' (Socket s) fs str = liftIO $ Z.send' s fs str

sendMulti :: (InScope m1 m2, MonadIO m2, Z.Sender a) => Socket m1 a -> [SB.ByteString] -> m2 ()
sendMulti (Socket s) ss = liftIO $ Z.sendMulti s ss

receive :: (InScope m1 m2, MonadIO m2, Z.Receiver a) => Socket m1 a -> m2 SB.ByteString
receive (Socket s) = liftIO $ Z.receive s

receiveMulti :: (InScope m1 m2, MonadIO m2, Z.Receiver a) => Socket m1 a -> m2 [SB.ByteString]
receiveMulti (Socket s) = liftIO $ Z.receiveMulti s

events :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Z.Event
events (Socket s) = liftIO $ Z.events s

fileDescriptor :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Fd
fileDescriptor (Socket s) = liftIO $ Z.fileDescriptor s

moreToReceive :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Bool
moreToReceive (Socket s) = liftIO $ Z.moreToReceive s

identity :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 String
identity (Socket s) = liftIO $ Z.identity s

affinity :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Word64
affinity (Socket s) = liftIO $ Z.affinity s

maxMessageSize :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int64
maxMessageSize (Socket s) = liftIO $ Z.maxMessageSize s

ipv4Only :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Bool
ipv4Only (Socket s) = liftIO $ Z.ipv4Only s

backlog :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
backlog (Socket s) = liftIO $ Z.backlog s

linger :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
linger (Socket s) = liftIO $ Z.linger s

rate :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
rate (Socket s) = liftIO $ Z.rate s

receiveBuffer :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
receiveBuffer (Socket s) = liftIO $ Z.receiveBuffer s

reconnectInterval :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
reconnectInterval (Socket s) = liftIO $ Z.reconnectInterval s

reconnectIntervalMax :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
reconnectIntervalMax (Socket s) = liftIO $ Z.reconnectIntervalMax s

recoveryInterval :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
recoveryInterval (Socket s) = liftIO $ Z.recoveryInterval s

sendBuffer :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
sendBuffer (Socket s) = liftIO $ Z.sendBuffer s

mcastHops :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
mcastHops (Socket s) = liftIO $ Z.mcastHops s

receiveHighWM :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
receiveHighWM (Socket s) = liftIO $ Z.receiveHighWM s

receiveTimeout :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
receiveTimeout (Socket s) = liftIO $ Z.receiveTimeout s

sendTimeout :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
sendTimeout (Socket s) = liftIO $ Z.sendTimeout s

sendHighWM :: (InScope m1 m2, MonadIO m2) => Socket m1 a -> m2 Int
sendHighWM (Socket s) = liftIO $ Z.sendHighWM s

setIdentity :: (InScope m1 m2, MonadIO m2) => Restricted N1 N254 String -> Socket m1 a -> m2 ()
setIdentity x (Socket s) = liftIO $ Z.setIdentity x s

setAffinity :: (InScope m1 m2, MonadIO m2) => Word64 -> Socket m1 a -> m2 ()
setAffinity x (Socket s) = liftIO $ Z.setAffinity x s

setMaxMessageSize :: (InScope m1 m2, MonadIO m2, Integral i) =>Restricted Nneg1 Int64 i -> Socket m1 a -> m2 ()
setMaxMessageSize x (Socket s) = liftIO $ Z.setMaxMessageSize x s

setIpv4Only :: (InScope m1 m2, MonadIO m2) => Bool -> Socket m1 a -> m2 ()
setIpv4Only x (Socket s) = liftIO $ Z.setIpv4Only x s

setLinger :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted Nneg1 Int32 i -> Socket m1 a -> m2 ()
setLinger x (Socket s) = liftIO $ Z.setLinger x s

setReceiveTimeout :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted Nneg1 Int32 i -> Socket m1 a -> m2 ()
setReceiveTimeout x (Socket s) = liftIO $ Z.setReceiveTimeout x s

setSendTimeout :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted Nneg1 Int32 i -> Socket m1 a -> m2 ()
setSendTimeout x (Socket s) = liftIO $ Z.setSendTimeout x s

setRate :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N1 Int32 i -> Socket m1 a -> m2 ()
setRate x (Socket s) = liftIO $ Z.setRate x s

setMcastHops :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N1 Int32 i -> Socket m1 a -> m2 ()
setMcastHops x (Socket s) = liftIO $ Z.setMcastHops x s

setBacklog :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setBacklog x (Socket s) = liftIO $ Z.setBacklog x s

setReceiveBuffer :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setReceiveBuffer x (Socket s) = liftIO $ Z.setReceiveBuffer x s

setReconnectInterval :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setReconnectInterval x (Socket s) = liftIO $ Z.setReconnectInterval x s

setReconnectIntervalMax :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setReconnectIntervalMax x (Socket s) = liftIO $ Z.setReconnectIntervalMax x s

setSendBuffer :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setSendBuffer x (Socket s) = liftIO $ Z.setSendBuffer x s

setRecoveryInterval :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setRecoveryInterval x (Socket s) = liftIO $ Z.setRecoveryInterval x s

setReceiveHighWM :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setReceiveHighWM x (Socket s) = liftIO $ Z.setReceiveHighWM x s

setSendHighWM :: (InScope m1 m2, MonadIO m2, Integral i) => Restricted N0 Int32 i -> Socket m1 a -> m2 ()
setSendHighWM x (Socket s) = liftIO $ Z.setSendHighWM x s

{-# LANGUAGE DoAndIfThenElse #-}
-- |
-- Module: System.ZMQ.IO
--  
-- A variant of the System.ZMQ module which registers with the GHC IO
-- manager to allow better multithreaded scaling.

module System.ZMQ.IO
    ( Context
    , Socket
    , Flag(..)
    , SocketOption(..)
    , Poll(..)
    , PollEvent(..)
    , Device(..)

    , SType
    , SubsType
    , Pair(..)
    , Pub(..)
    , Sub(..)
    , Req(..)
    , Rep(..)
    , XReq(..)
    , XRep(..)
    , Pull(..)
    , Push(..)
    , Up(..)
    , Down(..)

    , init
    , term
    , close
    , setOption
    , getOption
    , subscribe
    , unsubscribe
    , socket
    , bind
    , connect
    , send
    , send'
    , receive
    , moreToReceive
    , poll
    , device
    ) where

import Prelude hiding (init)
import Control.Exception
import Control.Monad (unless)

import System.Posix.Types (Fd(..))
import GHC.Conc (threadWaitRead, threadWaitWrite)

import Data.Bits ((.&.))

import Foreign.C.Error (throwErrnoIfMinus1RetryMayBlock_)
import Foreign.C.Types (CInt)

import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB

import System.ZMQ hiding (send, send', receive)
import System.ZMQ.Internal hiding (sock)
import System.ZMQ.Base hiding (subscribe, unsubscribe, events)

retry :: String -> IO () -> IO CInt -> IO ()
retry msg wait act = throwErrnoIfMinus1RetryMayBlock_ msg act wait

wait' :: (Fd -> IO ()) -> ZMQPollEvent -> Socket a -> IO ()
wait' w f s = do (FD fd) <- getOption s (FD undefined)
                 w (Fd fd)
                 (Events events) <- getOption s (Events undefined)
                 unless (testev events) $ wait' w f s
    where testev e = e .&. fromIntegral (pollVal f) /= 0

waitRead, waitWrite :: Socket a -> IO ()
waitRead = wait' threadWaitRead pollIn
waitWrite = wait' threadWaitWrite pollOut

-- | Send the given 'SB.ByteString' over the socket (zmq_send).
send :: Socket a -> SB.ByteString -> [Flag] -> IO ()
send sock@(Socket s) val fls = bracket (messageOf val) messageClose $ \m ->
    retry "send" (waitWrite sock) $
          c_zmq_send s (msgPtr m) (combine (NoBlock : fls))

-- | Send the given 'LB.ByteString' over the socket (zmq_send).
--   This is operationally identical to @send socket (Strict.concat
--   (Lazy.toChunks lbs)) flags@ but may be more efficient.
send' :: Socket a -> LB.ByteString -> [Flag] -> IO ()
send' sock@(Socket s) val fls = bracket (messageOfLazy val) messageClose $ \m ->
    retry "send'" (waitWrite sock) $
          c_zmq_send s (msgPtr m) (combine (NoBlock : fls))

-- | Receive a 'ByteString' from socket (zmq_recv).
receive :: Socket a -> [Flag] -> IO (SB.ByteString)
receive sock@(Socket s) fls = bracket messageInit messageClose $ \m -> do
    retry "receive" (waitRead sock) $
          c_zmq_recv_unsafe s (msgPtr m) (combine (NoBlock : fls))
    data_ptr <- c_zmq_msg_data (msgPtr m)
    size     <- c_zmq_msg_size (msgPtr m)
    SB.packCStringLen (data_ptr, fromIntegral size)

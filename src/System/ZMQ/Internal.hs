module System.ZMQ.Internal
    ( Context(..)
    , Socket(..)
    , Message(..)
    , Flag(..)
    , Timeout
    , Size

    , messageOf
    , messageOfLazy
    , messageClose
    , messageInit
    , messageInitSize
    , setIntOpt
    , setStrOpt
    , getBoolOpt
    , getIntOpt
    , getStrOpt
    , toZMQFlag
    , combine
    , mkSocket
    , withSocket
    ) where

import Control.Applicative
import Control.Monad (foldM_)
import Control.Exception
import Data.IORef (IORef)

import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt, CSize)

import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB
import Data.IORef (newIORef)

import System.ZMQ.Base

type Timeout = Int64
type Size    = Word

-- | Flags to apply on send operations (cf. man zmq_send)
--
-- [@NoBlock@] Send operation should be performed in non-blocking mode.
-- If it cannot be performed immediatley an error will be thrown (errno
-- is set to EAGAIN).
data Flag = NoBlock -- ^ ZMQ_NOBLOCK
          | SndMore -- ^ ZMQ_SNDMORE
  deriving (Eq, Ord, Show)

-- | A 0MQ context representation.
newtype Context = Context { ctx :: ZMQCtx }

-- | A 0MQ Socket.
data Socket a = Socket {
      _socket :: ZMQSocket
    , _sockLive :: IORef Bool
    }

-- A 0MQ Message representation.
newtype Message = Message { msgPtr :: ZMQMsgPtr }

-- internal helpers:

withSocket :: String -> Socket a -> (ZMQSocket -> IO b) -> IO b
withSocket _func (Socket sock _state) act = act sock
{-# INLINE withSocket #-}

mkSocket :: ZMQSocket -> IO (Socket a)
mkSocket s = Socket s <$> newIORef True

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
setIntOpt sock (ZMQOption o) i = withSocket "setIntOpt" sock $ \s ->
    throwErrnoIfMinus1_ "setIntOpt" $ with i $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castPtr ptr)
                           (fromIntegral . sizeOf $ i)

setStrOpt :: Socket a -> ZMQOption -> String -> IO ()
setStrOpt sock (ZMQOption o) str = withSocket "setStrOpt" sock $ \s ->
  throwErrnoIfMinus1_ "setStrOpt" $ withCStringLen str $ \(cstr, len) ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castPtr cstr)
                           (fromIntegral len)

getBoolOpt :: Socket a -> ZMQOption -> IO Bool
getBoolOpt s o = ((1 :: Int64) ==) <$> getIntOpt s o

getIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> IO b
getIntOpt sock (ZMQOption o) = withSocket "getIntOpt" sock $ \s -> do
    let i = 0
    bracket (new i) free $ \iptr ->
        bracket (new (fromIntegral . sizeOf $ i :: CSize)) free $ \jptr -> do
            throwErrnoIfMinus1_ "integralOpt" $
                c_zmq_getsockopt s (fromIntegral o) (castPtr iptr) jptr
            peek iptr

getStrOpt :: Socket a -> ZMQOption -> IO String
getStrOpt sock (ZMQOption o) = withSocket "getStrOpt" sock $ \s ->
    bracket (mallocBytes 255) free $ \bPtr ->
    bracket (new (255 :: CSize)) free $ \sPtr -> do
        throwErrnoIfMinus1_ "getStrOpt" $
            c_zmq_getsockopt s (fromIntegral o) (castPtr bPtr) sPtr
        peek sPtr >>= \len -> peekCStringLen (bPtr, fromIntegral len)

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag NoBlock = noBlock
toZMQFlag SndMore = sndMore

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . toZMQFlag) 0

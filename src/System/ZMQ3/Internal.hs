module System.ZMQ3.Internal
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
    , getIntOpt
    , getStrOpt
    , getIntMsgOpt
    , getInt32Option
    , setInt32OptFromRestricted

    , toZMQFlag
    , combine
    , mkSocket
    , onSocket

    ) where

import Control.Applicative
import Control.Monad (foldM_, when)
import Control.Exception
import Data.IORef (IORef, mkWeakIORef, readIORef)

import Foreign
import Foreign.C.String
import Foreign.C.Types (CInt, CSize)

import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB
import Data.IORef (newIORef)
import Data.Restricted

import System.ZMQ3.Base
import System.ZMQ3.Error

type Timeout = Int64
type Size    = Word

-- | Flags to apply on send operations (cf. man zmq_send)
data Flag = DontWait -- ^ ZMQ_DONTWAIT
          | SendMore -- ^ ZMQ_SNDMORE
  deriving (Eq, Ord, Show)

-- | A 0MQ context representation.
newtype Context = Context { ctx :: ZMQCtx }

-- | A 0MQ Socket.
data Socket a = Socket {
      _socket   :: ZMQSocket
    , _sockLive :: IORef Bool
    }

-- A 0MQ Message representation.
newtype Message = Message { msgPtr :: ZMQMsgPtr }

-- internal helpers:

onSocket :: String -> Socket a -> (ZMQSocket -> IO b) -> IO b
onSocket _func (Socket sock _state) act = act sock
{-# INLINE onSocket #-}

mkSocket :: ZMQSocket -> IO (Socket a)
mkSocket s = do
    ref <- newIORef True
    addFinalizer ref $ do
        alive <- readIORef ref
        when alive $ c_zmq_close s >> return ()
    return (Socket s ref)
  where
    addFinalizer r f = mkWeakIORef r f >> return ()

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
    throwIfMinus1_ "messageClose" $ c_zmq_msg_close ptr
    free ptr

messageInit :: IO Message
messageInit = do
    ptr <- new (ZMQMsg nullPtr)
    throwIfMinus1_ "messageInit" $ c_zmq_msg_init ptr
    return (Message ptr)

messageInitSize :: Size -> IO Message
messageInitSize s = do
    ptr <- new (ZMQMsg nullPtr)
    throwIfMinus1_ "messageInitSize" $
        c_zmq_msg_init_size ptr (fromIntegral s)
    return (Message ptr)

setIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> b -> IO ()
setIntOpt sock (ZMQOption o) i = onSocket "setIntOpt" sock $ \s ->
    throwIfMinus1Retry_ "setIntOpt" $ with i $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castPtr ptr)
                           (fromIntegral . sizeOf $ i)

setStrOpt :: Socket a -> ZMQOption -> String -> IO ()
setStrOpt sock (ZMQOption o) str = onSocket "setStrOpt" sock $ \s ->
  throwIfMinus1Retry_ "setStrOpt" $ withCStringLen str $ \(cstr, len) ->
        c_zmq_setsockopt s (fromIntegral o)
                           (castPtr cstr)
                           (fromIntegral len)

getIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> b -> IO b
getIntOpt sock (ZMQOption o) i = onSocket "getIntOpt" sock $ \s -> do
    bracket (new i) free $ \iptr ->
        bracket (new (fromIntegral . sizeOf $ i :: CSize)) free $ \jptr -> do
            throwIfMinus1Retry_ "getIntOpt" $
                c_zmq_getsockopt s (fromIntegral o) (castPtr iptr) jptr
            peek iptr

getStrOpt :: Socket a -> ZMQOption -> IO String
getStrOpt sock (ZMQOption o) = onSocket "getStrOpt" sock $ \s ->
    bracket (mallocBytes 255) free $ \bPtr ->
    bracket (new (255 :: CSize)) free $ \sPtr -> do
        throwIfMinus1Retry_ "getStrOpt" $
            c_zmq_getsockopt s (fromIntegral o) (castPtr bPtr) sPtr
        peek sPtr >>= \len -> peekCStringLen (bPtr, fromIntegral len)

getIntMsgOpt :: (Storable a, Integral a) => Message -> ZMQMsgOption -> a -> IO a
getIntMsgOpt (Message m) (ZMQMsgOption o) i = do
    bracket (new i) free $ \iptr ->
        bracket (new (fromIntegral . sizeOf $ i :: CSize)) free $ \jptr -> do
            throwIfMinus1Retry_ "getIntMsgOpt" $
                c_zmq_getmsgopt m (fromIntegral o) (castPtr iptr) jptr
            peek iptr

getInt32Option :: ZMQOption -> Socket a -> IO Int
getInt32Option o s = fromIntegral <$> getIntOpt s o (0 :: CInt)

setInt32OptFromRestricted :: Integral i => ZMQOption -> Restricted l u i -> Socket b -> IO ()
setInt32OptFromRestricted o x s = setIntOpt s o ((fromIntegral . rvalue $ x) :: CInt)

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag DontWait = dontWait
toZMQFlag SendMore = sndMore

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . toZMQFlag) 0

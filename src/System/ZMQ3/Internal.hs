module System.ZMQ3.Internal
    ( Context(..)
    , Socket(..)
    , SocketRepr(..)
    , SocketType(..)
    , Message(..)
    , Flag(..)
    , Timeout
    , Size
    , Switch (..)
    , EventType (..)
    , EventMsg (..)

    , messageOf
    , messageOfLazy
    , messageClose
    , messageInit
    , messageInitSize
    , setIntOpt
    , setStrOpt
    , getIntOpt
    , getStrOpt
    , getInt32Option
    , setInt32OptFromRestricted
    , ctxIntOption
    , setCtxIntOption
    , getByteStringOpt
    , setByteStringOpt

    , toZMQFlag
    , combine
    , combineFlags
    , mkSocketRepr
    , closeSock
    , onSocket

    , bool2cint
    , toSwitch
    , fromSwitch
    , events2cint
    , eventMessage

    ) where

import Control.Applicative
import Control.Monad (foldM_, when)
import Control.Exception
import Data.IORef (IORef, mkWeakIORef, readIORef, atomicModifyIORef)

import Foreign hiding (throwIfNull)
import Foreign.C.String
import Foreign.C.Types (CInt, CSize)

import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB
import Data.IORef (newIORef)
import Data.Restricted

import System.Posix.Types (Fd(..))
import System.ZMQ3.Base
import System.ZMQ3.Error

type Timeout = Int64
type Size    = Word

-- | Flags to apply on send operations (cf. man zmq_send)
data Flag =
    DontWait -- ^ ZMQ_DONTWAIT
  | SendMore -- ^ ZMQ_SNDMORE
  deriving (Eq, Ord, Show)

-- | Configuration switch
data Switch =
    Default -- ^ Use default setting
  | On      -- ^ Activate setting
  | Off     -- ^ De-activate setting
  deriving (Eq, Ord, Show)

-- | Event types to monitor.
data EventType =
    ConnectedEvent
  | ConnectDelayedEvent
  | ConnectRetriedEvent
  | ListeningEvent
  | BindFailedEvent
  | AcceptedEvent
  | AcceptFailedEvent
  | ClosedEvent
  | CloseFailedEvent
  | DisconnectedEvent
  | AllEvents
  deriving (Eq, Ord, Show)

-- | Event Message to receive when monitoring socket events.
data EventMsg =
    Connected      !SB.ByteString !Fd
  | ConnectDelayed !SB.ByteString !Fd
  | ConnectRetried !SB.ByteString !Int
  | Listening      !SB.ByteString !Fd
  | BindFailed     !SB.ByteString !Fd
  | Accepted       !SB.ByteString !Fd
  | AcceptFailed   !SB.ByteString !Int
  | Closed         !SB.ByteString !Fd
  | CloseFailed    !SB.ByteString !Int
  | Disconnected   !SB.ByteString !Int
  deriving (Eq, Show)

-- | A 0MQ context representation.
newtype Context = Context { _ctx :: ZMQCtx }

-- | A 0MQ Socket.
newtype Socket a = Socket
  { _socketRepr :: SocketRepr }

data SocketRepr = SocketRepr
  { _socket   :: ZMQSocket
  , _sockLive :: IORef Bool
  }

-- | Socket types.
class SocketType a where
    zmqSocketType :: a -> ZMQSocketType

-- A 0MQ Message representation.
newtype Message = Message { msgPtr :: ZMQMsgPtr }

-- internal helpers:

onSocket :: String -> Socket a -> (ZMQSocket -> IO b) -> IO b
onSocket _func (Socket (SocketRepr sock _state)) act = act sock
{-# INLINE onSocket #-}

mkSocketRepr :: SocketType t => t -> Context -> IO SocketRepr
mkSocketRepr t c = do
    let ty = typeVal (zmqSocketType t)
    s   <- throwIfNull "mkSocketRepr" (c_zmq_socket (_ctx c) ty)
    ref <- newIORef True
    addFinalizer ref $ do
        alive <- readIORef ref
        when alive $ c_zmq_close s >> return ()
    return (SocketRepr s ref)
  where
    addFinalizer r f = mkWeakIORef r f >> return ()

closeSock :: SocketRepr -> IO ()
closeSock (SocketRepr s status) = do
  alive <- atomicModifyIORef status (\b -> (False, b))
  when alive $ throwIfMinus1_ "close" . c_zmq_close $ s

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

setCStrOpt :: ZMQSocket -> ZMQOption -> CStringLen -> IO CInt
setCStrOpt s (ZMQOption o) (cstr, len) =
    c_zmq_setsockopt s (fromIntegral o) (castPtr cstr) (fromIntegral len)

setByteStringOpt :: Socket a -> ZMQOption -> SB.ByteString -> IO ()
setByteStringOpt sock opt str = onSocket "setByteStringOpt" sock $ \s ->
    throwIfMinus1Retry_ "setByteStringOpt" . UB.unsafeUseAsCStringLen str $ setCStrOpt s opt

setStrOpt :: Socket a -> ZMQOption -> String -> IO ()
setStrOpt sock opt str = onSocket "setStrOpt" sock $ \s ->
    throwIfMinus1Retry_ "setStrOpt" . withCStringLen str $ setCStrOpt s opt

getIntOpt :: (Storable b, Integral b) => Socket a -> ZMQOption -> b -> IO b
getIntOpt sock (ZMQOption o) i = onSocket "getIntOpt" sock $ \s -> do
    bracket (new i) free $ \iptr ->
        bracket (new (fromIntegral . sizeOf $ i :: CSize)) free $ \jptr -> do
            throwIfMinus1Retry_ "getIntOpt" $
                c_zmq_getsockopt s (fromIntegral o) (castPtr iptr) jptr
            peek iptr

getCStrOpt :: (CStringLen -> IO s) -> Socket a -> ZMQOption -> IO s
getCStrOpt peekA sock (ZMQOption o) = onSocket "getCStrOpt" sock $ \s ->
    bracket (mallocBytes 255) free $ \bPtr ->
    bracket (new (255 :: CSize)) free $ \sPtr -> do
        throwIfMinus1Retry_ "getCStrOpt" $
            c_zmq_getsockopt s (fromIntegral o) (castPtr bPtr) sPtr
        peek sPtr >>= \len -> peekA (bPtr, fromIntegral len)

getStrOpt :: Socket a -> ZMQOption -> IO String
getStrOpt = getCStrOpt peekCStringLen

getByteStringOpt :: Socket a -> ZMQOption -> IO SB.ByteString
getByteStringOpt = getCStrOpt SB.packCStringLen

getInt32Option :: ZMQOption -> Socket a -> IO Int
getInt32Option o s = fromIntegral <$> getIntOpt s o (0 :: CInt)

setInt32OptFromRestricted :: Integral i => ZMQOption -> Restricted l u i -> Socket b -> IO ()
setInt32OptFromRestricted o x s = setIntOpt s o ((fromIntegral . rvalue $ x) :: CInt)

ctxIntOption :: Integral i => String -> ZMQCtxOption -> Context -> IO i
ctxIntOption name opt ctx = fromIntegral <$>
    (throwIfMinus1 name $ c_zmq_ctx_get (_ctx ctx) (ctxOptVal opt))

setCtxIntOption :: Integral i => String -> ZMQCtxOption -> i -> Context -> IO ()
setCtxIntOption name opt val ctx = throwIfMinus1_ name $
    c_zmq_ctx_set (_ctx ctx) (ctxOptVal opt) (fromIntegral val)

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag DontWait = dontWait
toZMQFlag SendMore = sndMore

combineFlags :: [Flag] -> CInt
combineFlags = fromIntegral . combine . map (flagVal . toZMQFlag)

combine :: (Integral i, Bits i) => [i] -> i
combine = foldr (.|.) 0

bool2cint :: Bool -> CInt
bool2cint True  = 1
bool2cint False = 0

toSwitch :: Integral a => a -> Maybe Switch
toSwitch (-1) = Just Default
toSwitch  0   = Just Off
toSwitch  1   = Just On
toSwitch _    = Nothing

fromSwitch :: Integral a => Switch -> a
fromSwitch Default = -1
fromSwitch Off     = 0
fromSwitch On      = 1

toZMQEventType :: EventType -> ZMQEventType
toZMQEventType AllEvents           = allEvents
toZMQEventType ConnectedEvent      = connected
toZMQEventType ConnectDelayedEvent = connectDelayed
toZMQEventType ConnectRetriedEvent = connectRetried
toZMQEventType ListeningEvent      = listening
toZMQEventType BindFailedEvent     = bindFailed
toZMQEventType AcceptedEvent       = accepted
toZMQEventType AcceptFailedEvent   = acceptFailed
toZMQEventType ClosedEvent         = closed
toZMQEventType CloseFailedEvent    = closeFailed
toZMQEventType DisconnectedEvent   = disconnected

events2cint :: [EventType] -> CInt
events2cint = fromIntegral . foldr ((.|.) . eventTypeVal . toZMQEventType) 0

eventMessage :: Integral a => SB.ByteString -> a -> ZMQEventType -> EventMsg
eventMessage str dat tag
    | tag == connected      = Connected      str (Fd . fromIntegral $ dat)
    | tag == connectDelayed = ConnectDelayed str (Fd . fromIntegral $ dat)
    | tag == connectRetried = ConnectRetried str (fromIntegral dat)
    | tag == listening      = Listening      str (Fd . fromIntegral $ dat)
    | tag == bindFailed     = BindFailed     str (Fd . fromIntegral $ dat)
    | tag == accepted       = Accepted       str (Fd . fromIntegral $ dat)
    | tag == acceptFailed   = AcceptFailed   str (fromIntegral dat)
    | tag == closed         = Closed         str (Fd . fromIntegral $ dat)
    | tag == closeFailed    = CloseFailed    str (fromIntegral dat)
    | tag == disconnected   = Disconnected   str (fromIntegral dat)
    | otherwise             = error $ "unknown event type: " ++ (show . eventTypeVal $ tag)

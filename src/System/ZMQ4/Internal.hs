{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE StandaloneDeriving #-}

-- | /Warning/: This is an internal module and subject
-- to change without notice.
module System.ZMQ4.Internal
    ( Context           (..)
    , Socket            (..)
    , SocketRepr        (..)
    , SocketType        (..)
    , SocketLike        (..)
    , Message           (..)
    , Flag              (..)
    , Timeout
    , Size
    , Switch            (..)
    , EventType         (..)
    , EventMsg          (..)
    , SecurityMechanism (..)
    , KeyFormat         (..)

    , messageOf
    , messageOfLazy
    , messageClose
    , messageFree
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

    , z85Encode
    , z85Decode

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

    , toMechanism
    , fromMechanism

    , getKey
    ) where

import Control.Applicative
import Control.Monad (foldM_, when, void)
import Control.Monad.IO.Class
import Control.Exception
import Data.IORef (IORef, mkWeakIORef, readIORef, atomicModifyIORef)

import Foreign hiding (throwIfNull, void)
import Foreign.C.String
import Foreign.C.Types (CInt, CSize)

import Data.IORef (newIORef)
import Data.Restricted
import Data.Typeable
import Prelude

import System.Posix.Types (Fd(..))
import System.ZMQ4.Internal.Base
import System.ZMQ4.Internal.Error

import qualified Data.ByteString        as SB
import qualified Data.ByteString.Lazy   as LB
import qualified Data.ByteString.Unsafe as UB

type Timeout = Int64
type Size    = Word

-- | Flags to apply on send operations (cf. man zmq_send)
data Flag =
    DontWait -- ^ ZMQ_DONTWAIT (Only relevant on Windows.)
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
  | MonitorStoppedEvent
  | AllEvents
  deriving (Eq, Ord, Show)

-- | Event Message to receive when monitoring socket events.
data EventMsg =
    Connected      !SB.ByteString !Fd
  | ConnectDelayed !SB.ByteString
  | ConnectRetried !SB.ByteString !Int
  | Listening      !SB.ByteString !Fd
  | BindFailed     !SB.ByteString !Int
  | Accepted       !SB.ByteString !Fd
  | AcceptFailed   !SB.ByteString !Int
  | Closed         !SB.ByteString !Fd
  | CloseFailed    !SB.ByteString !Int
  | Disconnected   !SB.ByteString !Fd
  | MonitorStopped !SB.ByteString !Int
  deriving (Eq, Show)

data SecurityMechanism
  = Null
  | Plain
  | Curve
  deriving (Eq, Show)

data KeyFormat a where
  BinaryFormat :: KeyFormat Div4
  TextFormat   :: KeyFormat Div5

deriving instance Eq   (KeyFormat a)
deriving instance Show (KeyFormat a)

-- | A 0MQ context representation.
newtype Context = Context { _ctx :: ZMQCtx }

deriving instance Typeable Context

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

class SocketLike s where
    toSocket :: s t -> Socket t

instance SocketLike Socket where
    toSocket = id

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

messageFree :: Message -> IO ()
messageFree (Message ptr) = free ptr

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
getStrOpt = getCStrOpt (peekCString . fst)

getByteStringOpt :: Socket a -> ZMQOption -> IO SB.ByteString
getByteStringOpt = getCStrOpt SB.packCStringLen

getInt32Option :: ZMQOption -> Socket a -> IO Int
getInt32Option o s = fromIntegral <$> getIntOpt s o (0 :: CInt)

setInt32OptFromRestricted :: Integral i => ZMQOption -> Restricted r i -> Socket b -> IO ()
setInt32OptFromRestricted o x s = setIntOpt s o ((fromIntegral . rvalue $ x) :: CInt)

ctxIntOption :: Integral i => String -> ZMQCtxOption -> Context -> IO i
ctxIntOption name opt ctx = fromIntegral <$>
    (throwIfMinus1 name $ c_zmq_ctx_get (_ctx ctx) (ctxOptVal opt))

setCtxIntOption :: Integral i => String -> ZMQCtxOption -> i -> Context -> IO ()
setCtxIntOption name opt val ctx = throwIfMinus1_ name $
    c_zmq_ctx_set (_ctx ctx) (ctxOptVal opt) (fromIntegral val)

z85Encode :: (MonadIO m) => Restricted Div4 SB.ByteString -> m SB.ByteString
z85Encode b = liftIO $ UB.unsafeUseAsCStringLen (rvalue b) $ \(c, s) ->
    allocaBytes ((s * 5) `div` 4 + 1) $ \w -> do
        void . throwIfNull "z85Encode" $
            c_zmq_z85_encode w (castPtr c) (fromIntegral s)
        SB.packCString w

z85Decode :: (MonadIO m) => Restricted Div5 SB.ByteString -> m SB.ByteString
z85Decode b = liftIO $ SB.useAsCStringLen (rvalue b) $ \(c, s) -> do
    let size = (s * 4) `div` 5
    allocaBytes size $ \w -> do
        void . throwIfNull "z85Decode" $
            c_zmq_z85_decode (castPtr w) (castPtr c)
        SB.packCStringLen (w, size)

getKey :: KeyFormat f -> Socket a -> ZMQOption -> IO SB.ByteString
getKey kf sock (ZMQOption o) = onSocket "getKey" sock $ \s -> do
    let len = case kf of
            BinaryFormat -> 32
            TextFormat   -> 41
    with len $ \lenptr -> allocaBytes len $ \w -> do
        throwIfMinus1Retry_ "getKey" $
            c_zmq_getsockopt s (fromIntegral o) (castPtr w) (castPtr lenptr)
        SB.packCString w

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

toSwitch :: (Show a, Integral a) => String -> a -> Switch
toSwitch _ (-1) = Default
toSwitch _   0  = Off
toSwitch _   1  = On
toSwitch m   n  = error $ m ++ ": " ++ show n

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
toZMQEventType MonitorStoppedEvent = monitorStopped

toMechanism :: SecurityMechanism -> ZMQSecMechanism
toMechanism Null  = secNull
toMechanism Plain = secPlain
toMechanism Curve = secCurve

fromMechanism :: String -> Int -> SecurityMechanism
fromMechanism s m
    | m == secMechanism secNull  = Null
    | m == secMechanism secPlain = Plain
    | m == secMechanism secCurve = Curve
    | otherwise                  = error $ s ++ ": " ++ show m

events2cint :: [EventType] -> CInt
events2cint = fromIntegral . foldr ((.|.) . eventTypeVal . toZMQEventType) 0

eventMessage :: SB.ByteString -> ZMQEvent -> EventMsg
eventMessage str (ZMQEvent e v)
    | e == connected      = Connected      str (Fd . fromIntegral $ v)
    | e == connectDelayed = ConnectDelayed str
    | e == connectRetried = ConnectRetried str (fromIntegral $ v)
    | e == listening      = Listening      str (Fd . fromIntegral $ v)
    | e == bindFailed     = BindFailed     str (fromIntegral $ v)
    | e == accepted       = Accepted       str (Fd . fromIntegral $ v)
    | e == acceptFailed   = AcceptFailed   str (fromIntegral $ v)
    | e == closed         = Closed         str (Fd . fromIntegral $ v)
    | e == closeFailed    = CloseFailed    str (fromIntegral $ v)
    | e == disconnected   = Disconnected   str (fromIntegral $ v)
    | e == monitorStopped = MonitorStopped str (fromIntegral $ v)
    | otherwise           = error $ "unknown event type: " ++ show e

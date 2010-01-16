-- |
-- Module      : System.ZMQ
-- Copyright   : (c) 2010 Toralf Wittner
-- License     : LGPL
-- Maintainer  : toralf.wittner@gmail.com
-- Stability   : experimental
-- Portability : non-portable
-- 

module System.ZMQ (

    Size,
    Context,
    Socket,
    Message,
    Flag(..),
    SocketType(..),
    SocketOption(..),

    init,
    term,

    socket,
    close,
    setOption,
    bind,
    connect,
    send,
    flush,
    receive

) where

import Prelude hiding (init)
import Control.Applicative
import Control.Exception
import Data.Binary
import Data.Int
import System.ZMQ.Base
import Foreign
import Foreign.C.Error
import Foreign.C.String
import Foreign.C.Types (CInt)
import qualified Data.ByteString as SB
import qualified Data.ByteString.Lazy as LB
import qualified Data.ByteString.Unsafe as UB

type    Size    = Word
newtype Context = Context { ctx  :: ZMQCtx }
newtype Socket  = Socket  { sock :: ZMQSocket }
newtype Message = Message { msg_ptr :: ZMQMsgPtr }

data SocketType = P2P | Pub | Sub | Req | Rep | XReq | XRep | Up | Down
    deriving (Eq, Ord, Show)

data SocketOption =
    HighWM      Int64
  | LowWM       Int64
  | Swap        Int64
  | Affinity    Int64
  | Identity    String
  | Subscribe   String
  | Unsubscribe String
  | Rate        Word64
  | RecoveryIVL Word64
  | McastLoop   Word64
  | SendBuf     Word64
  | ReceiveBuf  Word64
  deriving (Eq, Ord, Show)

data Flag = NoBlock | NoFlush deriving (Eq, Ord, Show)

init :: Size -> Size -> Bool  -> IO Context
init appThreads ioThreads poll = do
    c <- throwErrnoIfNull "init" $
         c_zmq_init (fromIntegral appThreads)
                    (fromIntegral ioThreads)
                    (if poll then usePoll else 0)
    return (Context c)

term :: Context -> IO ()
term = throwErrnoIfMinus1_ "term" . c_zmq_term . ctx

socket :: Context -> SocketType -> IO Socket
socket c st = Socket <$> make c (st2cst st)

close :: Socket -> IO ()
close = throwErrnoIfMinus1_ "close" . c_zmq_close . sock

setOption :: Socket -> SocketOption -> IO ()
setOption s (HighWM o)      = setIntOpt s highWM o
setOption s (LowWM o)       = setIntOpt s lowWM o
setOption s (Swap o)        = setIntOpt s swap o
setOption s (Affinity o)    = setIntOpt s affinity o
setOption s (Identity o)    = setStrOpt s identity o
setOption s (Subscribe o)   = setStrOpt s subscribe o
setOption s (Unsubscribe o) = setStrOpt s unsubscribe o
setOption s (Rate o)        = setIntOpt s rate o
setOption s (RecoveryIVL o) = setIntOpt s recoveryIVL o
setOption s (McastLoop o)   = setIntOpt s mcastLoop o
setOption s (SendBuf o)     = setIntOpt s sendBuf o
setOption s (ReceiveBuf o)  = setIntOpt s receiveBuf o

bind :: Socket -> String -> IO ()
bind (Socket s) str = throwErrnoIfMinus1_ "bind" $
    withCString str (c_zmq_bind s)

connect :: Socket -> String -> IO ()
connect (Socket s) str = throwErrnoIfMinus1_ "connect" $
    withCString str (c_zmq_connect s)

send :: Binary a => Socket -> a -> [Flag] -> IO ()
send (Socket s) val fls = mapM_ sendChunk (LB.toChunks . encode $ val)
 where
    sendChunk :: SB.ByteString -> IO ()
    sendChunk b = bracket (messageOf b) messageClose $ \m ->
        throwErrnoIfMinus1_ "sendChunk" $
            c_zmq_send s (msg_ptr m) (combine fls)

flush :: Socket -> IO ()
flush = throwErrnoIfMinus1_ "flush" . c_zmq_flush . sock

receive :: Binary a => Socket -> [Flag] -> IO a
receive (Socket s) fls = bracket messageInit messageClose $ \m -> do
    throwErrnoIfMinus1_ "receive" $ c_zmq_recv s (msg_ptr m) (combine fls)
    data_ptr <- c_zmq_msg_data (msg_ptr m)
    size     <- c_zmq_msg_size (msg_ptr m)
    bstr     <- SB.packCStringLen (data_ptr, fromIntegral size)
    return $ decode (LB.fromChunks [bstr])

-- internal helpers:

messageOf :: SB.ByteString -> IO Message
messageOf b = UB.unsafeUseAsCStringLen b $ \(cstr, len) -> do
    msg <- messageInitSize (fromIntegral len)
    data_ptr <- c_zmq_msg_data (msg_ptr msg)
    copyBytes data_ptr cstr len
    return msg

messageClose :: Message -> IO ()
messageClose m = throwErrnoIfMinus1_ "messageClose" $
    c_zmq_msg_close (msg_ptr m)
    -- free?

messageInit :: IO Message
messageInit = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInit" $
        c_zmq_msg_init ptr
    return (Message ptr)

messageInitSize :: Size -> IO Message
messageInitSize s = do
    ptr <- new (ZMQMsg nullPtr)
    throwErrnoIfMinus1_ "messageInitSize" $
        c_zmq_msg_init_size ptr (fromIntegral s)
    return (Message ptr)

make :: Context -> ZMQSocketType -> IO ZMQSocket
make (Context c) = throwErrnoIfNull "socket" . c_zmq_socket c . typeVal

setIntOpt :: (Storable a, Integral a) => Socket -> ZMQOption -> a -> IO ()
setIntOpt (Socket s) (ZMQOption o) i = throwErrnoIfMinus1_ "setIntOpt" $
    withStablePtrOf i $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (fromStablePtr ptr)
                           (fromIntegral . sizeOf $ i)

setStrOpt :: Socket -> ZMQOption -> String -> IO ()
setStrOpt (Socket s) (ZMQOption o) str = throwErrnoIfMinus1_ "setStrOpt" $
    withCStringLen str $ \(cstr, len) ->
        c_zmq_setsockopt s (fromIntegral o) (castPtr cstr) (fromIntegral len)

st2cst :: SocketType -> ZMQSocketType
st2cst P2P  = p2p
st2cst Pub  = pub
st2cst Sub  = sub
st2cst Req  = request
st2cst Rep  = response
st2cst XReq = xrequest
st2cst XRep = xresponse
st2cst Up   = upstream
st2cst Down = downstream

toZMQFlag :: Flag -> ZMQFlag
toZMQFlag NoBlock = noBlock
toZMQFlag NoFlush = noFlush

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . toZMQFlag) 0

withStablePtrOf :: a -> (StablePtr a -> IO b) -> IO b
withStablePtrOf x f = bracket (newStablePtr x) freeStablePtr f

fromStablePtr :: StablePtr a -> Ptr b
fromStablePtr = castPtr . castStablePtrToPtr

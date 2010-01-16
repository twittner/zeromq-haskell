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
    SocketType(..),
    SocketOption(..),
    Flag,
    Message,

    init,
    term,

    socket,
    close,
    setSockOpt,
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

init :: Size -> Size -> Flag -> IO Context
init appThreads ioThreads flag = do
    c <- throwErrnoIfNull "init" $
         c_zmq_init (fromIntegral appThreads)
                    (fromIntegral ioThreads)
                    (flagVal . fl2cfl $ flag)
    return (Context c)


term :: Context -> IO ()
term = throwErrnoIfMinus1_ "term" . c_zmq_term . ctx

socket :: Context -> SocketType -> IO Socket
socket c st = Socket <$> make c (st2cst st)

close :: Socket -> IO ()
close = throwErrnoIfMinus1_ "close" . c_zmq_close . sock

setSockOpt :: Socket -> SocketOption -> IO ()
setSockOpt s (HighWM o)      = setOpt s highWM o
setSockOpt s (LowWM o)       = setOpt s lowWM o
setSockOpt s (Swap o)        = setOpt s swap o
setSockOpt s (Affinity o)    = setOpt s affinity o
setSockOpt s (Identity o)    = withCString o $ setOpt s identity
setSockOpt s (Subscribe o)   = withCString o $ setOpt s subscribe
setSockOpt s (Unsubscribe o) = withCString o $ setOpt s unsubscribe
setSockOpt s (Rate o)        = setOpt s rate o
setSockOpt s (RecoveryIVL o) = setOpt s recoveryIVL o
setSockOpt s (McastLoop o)   = setOpt s mcastLoop o
setSockOpt s (SendBuf o)     = setOpt s sendBuf o
setSockOpt s (ReceiveBuf o)  = setOpt s receiveBuf o

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
    sendChunk b = bracket (messageOf b) messageClose $ \msg ->
        withStablePtrOf msg $ \ptr -> throwErrnoIfMinus1_ "sendChunk" $
            c_zmq_send s (castPtr . castStablePtrToPtr $ ptr)
                         (combine fls)

flush :: Socket -> IO ()
flush = throwErrnoIfMinus1_ "flush" . c_zmq_flush . sock

receive :: Binary a => Socket -> [Flag] -> IO a
receive = undefined

-- internal helpers:

messageOf :: SB.ByteString -> IO (Message SB.ByteString)
messageOf b = UB.unsafeUseAsCStringLen b $ \(cstr, len) -> do
    msg <- messageInitSize (fromIntegral len)
    withStablePtrOf msg $ \ptr -> do
        data_ptr <- c_zmq_msg_data (fromStablePtr ptr)
        copyBytes data_ptr cstr len
    return msg

messageClose :: Message a -> IO ()
messageClose m = withStablePtrOf m $ \ptr ->
    throwErrnoIfMinus1_ "messageClose" $
        c_zmq_msg_close (fromStablePtr ptr)

messageInit :: IO (Message a)
messageInit = do
    let msg = Message nullPtr
    bracket (newStablePtr msg) freeStablePtr $ \ptr ->
        throwErrnoIfMinus1_ "messageInit" $
            c_zmq_msg_init (castPtr . castStablePtrToPtr $ ptr)
    return msg

messageInitSize :: Word -> IO (Message a)
messageInitSize s = do
    let msg = Message nullPtr
    bracket (newStablePtr msg) freeStablePtr $ \ptr ->
        throwErrnoIfMinus1_ "messageInitSize" $
            c_zmq_msg_init_size (castPtr . castStablePtrToPtr $ ptr)
                                (fromIntegral s)
    return msg

make :: Context -> CSocketType -> IO ZMQSocket
make (Context c) = throwErrnoIfNull "socket" . c_zmq_socket c . typeVal

setOpt :: (Storable a) => Socket -> OptionType -> a -> IO ()
setOpt (Socket s) (OptionType o) i = throwErrnoIfMinus1_ "setSockOpt" $
    withStablePtrOf i $ \ptr ->
        c_zmq_setsockopt s (fromIntegral o)
                           (fromStablePtr ptr)
                           (fromIntegral . sizeOf $ i)

st2cst :: SocketType -> CSocketType
st2cst P2P  = p2p
st2cst Pub  = pub
st2cst Sub  = sub
st2cst Req  = request
st2cst Rep  = response
st2cst XReq = xrequest
st2cst XRep = xresponse
st2cst Up   = upstream
st2cst Down = downstream

fl2cfl :: Flag -> CFlag
fl2cfl NoBlock = noBlock
fl2cfl NoFlush = noFlush

combine :: [Flag] -> CInt
combine = fromIntegral . foldr ((.|.) . flagVal . fl2cfl) 0

withStablePtrOf :: a -> (StablePtr a -> IO b) -> IO b
withStablePtrOf x f = bracket (newStablePtr x) freeStablePtr f

fromStablePtr :: StablePtr a -> Ptr b
fromStablePtr = castPtr . castStablePtrToPtr

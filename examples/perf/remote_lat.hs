import Control.Monad
import System.IO
import System.Exit
import System.Environment
import Data.Time.Clock
import qualified System.ZMQ3 as ZMQ
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 3) $ do
        hPutStrLn stderr usage
        exitFailure
    let connTo  = args !! 0
        size    = read $ args !! 1
        rounds  = read $ args !! 2
        message = SB.replicate size 0x65
    ZMQ.withContext $ \c ->
        ZMQ.withSocket c ZMQ.Req $ \s -> do
            ZMQ.connect s connTo
            start <- getCurrentTime
            loop s rounds message
            end <- getCurrentTime
            print (diffUTCTime end start)
  where
    loop s r msg = unless (r <= 0) $ do
        ZMQ.send s [] msg
        msg' <- ZMQ.receive s
        when (SB.length msg' /= SB.length msg) $
            error "message of incorrect size received"
        loop s (r - 1) msg

usage :: String
usage = "usage: remote_lat <connect-to> <message-size> <roundtrip-count>"


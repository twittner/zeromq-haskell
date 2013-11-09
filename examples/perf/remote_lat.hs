import Control.Monad
import System.IO
import System.Exit
import System.Environment
import Data.Time.Clock
import System.ZMQ4.Monadic
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
    runZMQ $ do
        s <- socket Req
        connect s connTo
        start <- liftIO $ getCurrentTime
        loop s rounds message
        end <- liftIO $ getCurrentTime
        liftIO $ print (diffUTCTime end start)
  where
    loop s r msg = unless (r <= 0) $ do
        send s [] msg
        msg' <- receive s
        when (SB.length msg' /= SB.length msg) $
            error "message of incorrect size received"
        loop s (r - 1) msg

usage :: String
usage = "usage: remote_lat <connect-to> <message-size> <roundtrip-count>"


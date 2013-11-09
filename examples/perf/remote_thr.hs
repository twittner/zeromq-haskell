import Control.Monad
import Control.Concurrent
import System.IO
import System.Exit
import System.Environment
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
        count   = read $ args !! 2
        message = SB.replicate size 0x65
    runZMQ $ do
        s <- socket Pub
        connect s connTo
        replicateM_ count $ send s [] message
        liftIO $ threadDelay 10000000

usage :: String
usage = "usage: remote_thr <connect-to> <message-size> <message-count>"


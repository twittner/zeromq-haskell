import Control.Monad
import Control.Concurrent
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ as ZMQ
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
    ZMQ.with 1 $ \c -> do
      s <- ZMQ.socket c ZMQ.Pub
      ZMQ.connect s connTo
      replicateM_ count $ ZMQ.send s message []
      threadDelay 10000000
      ZMQ.close s

usage :: String
usage = "usage: remote_thr <connect-to> <message-size> <message-count>"


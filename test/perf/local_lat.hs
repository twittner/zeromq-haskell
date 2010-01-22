import Control.Monad
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
    let bindTo  = args !! 0
        msgSize = read $ args !! 1 :: Int
        rounds  = read $ args !! 2
    c <- ZMQ.init 1 1 False
    s <- ZMQ.socket c ZMQ.Rep
    ZMQ.bind s bindTo
    loop s rounds msgSize
 where
    loop s r sz = unless (r <= 0) $ do
        msg <- ZMQ.receive s []
        when (SB.length msg /= sz) $
            error "message of incorrect size received"
        ZMQ.send s msg []
        loop s (r - 1) sz

usage :: String
usage = "usage: local_lat <bind-to> <message-size> <roundtrip-count>"


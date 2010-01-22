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
    let bindTo = args !! 0
        size   = read $ args !! 1
        rounds = read $ args !! 2
    c <- ZMQ.init 1 1 False
    s <- ZMQ.socket c ZMQ.Rep
    ZMQ.bind s bindTo
    loop s rounds size
    ZMQ.close s
    ZMQ.term c
 where
    loop s r sz = unless (r <= 0) $ do
        msg <- ZMQ.receive s []
        when (SB.length msg /= sz) $
            error "message of incorrect size received"
        ZMQ.send s msg []
        loop s (r - 1) sz

usage :: String
usage = "usage: local_lat <bind-to> <message-size> <roundtrip-count>"


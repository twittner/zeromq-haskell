import Control.Applicative
import Control.Monad
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ as ZMQ
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 1) $ do
        hPutStrLn stderr usage
        exitFailure
    c <- ZMQ.init 1 1 True
    s <- ZMQ.socket c ZMQ.Rep
    let bindTo = head args
        toPoll = [ZMQ.S s ZMQ.In]
    ZMQ.bind s bindTo
    forever $
        ZMQ.poll toPoll 1000000 >>= receive
 where
    receive []               = return ()
    receive ((ZMQ.S s e):ss) = do
        msg <- ZMQ.receive s []
        ZMQ.send s msg []
        receive ss

usage :: String
usage = "usage: poll <bind-to>"


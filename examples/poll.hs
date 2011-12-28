import Control.Applicative
import Control.Monad
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ3 as ZMQ
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args /= 1) $ do
        hPutStrLn stderr usage
        exitFailure
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c ZMQ.Rep $ \s -> do
            let bindTo = head args
                toPoll = [ZMQ.S s ZMQ.In]
            ZMQ.bind s bindTo
            forever $
                ZMQ.poll toPoll 1000000 >>= receive
 where
    receive []               = return ()
    receive ((ZMQ.S s e):ss) = do
        msg <- ZMQ.receive s
        ZMQ.send s [] msg
        receive ss

usage :: String
usage = "usage: poll <bind-to>"


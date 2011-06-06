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
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c ZMQ.Rep $ \s -> do
            let bindTo = head args
            ZMQ.bind s bindTo
            forever $
                ZMQ.poll [ZMQ.S s ZMQ.In, s] 1000000 >>= mapM_ receive
 where
   receive s = do
     msg <- ZMG.receive s []
     ZMQ.send s msg []

usage :: String
usage = "usage: poll <bind-to>"


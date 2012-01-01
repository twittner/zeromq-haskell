import Control.Monad
import System.IO
import System.Exit
import System.Environment
import Control.Exception
import qualified System.ZMQ3 as ZMQ
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args < 1) $ do
        hPutStrLn stderr "usage: display <address> [<address>, ...]"
        exitFailure
    ZMQ.withContext 1 $ \c ->
        ZMQ.withSocket c ZMQ.Sub $ \s -> do
            ZMQ.subscribe s ""
            mapM (ZMQ.connect s) args
            forever $ do
                line <- ZMQ.receive s
                SB.putStrLn line
                hFlush stdout


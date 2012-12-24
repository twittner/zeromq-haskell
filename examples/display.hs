import Control.Monad
import System.IO
import System.Exit
import System.Environment
import Control.Exception
import qualified System.ZMQ3 as ZMQ
import qualified Data.ByteString as SB
import qualified Data.ByteString.Char8 as CS

main :: IO ()
main = do
    args <- getArgs
    when (length args < 1) $ do
        hPutStrLn stderr "usage: display <address> [<address>, ...]"
        exitFailure
    ZMQ.withContext $ \c ->
        ZMQ.withSocket c ZMQ.Sub $ \s -> do
            ZMQ.subscribe s ""
            mapM (ZMQ.connect s) args
            forever $ do
                line <- ZMQ.receive s
                CS.putStrLn line
                hFlush stdout


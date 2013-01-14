import Control.Applicative
import Control.Exception
import Control.Monad
import System.Exit
import System.IO
import System.Environment
import System.ZMQ3.Monadic
import qualified Data.ByteString.Char8 as CS

main :: IO ()
main = do
    args <- getArgs
    when (length args < 1) $ do
        hPutStrLn stderr "usage: display <address> [<address>, ...]"
        exitFailure
    runContext $
        runSocket Sub $ do
            subscribe ""
            mapM connect args
            forever $ do
                receive >>= liftIO . CS.putStrLn
                liftIO $ hFlush stdout

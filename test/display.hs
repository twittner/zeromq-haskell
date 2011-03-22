import Control.Monad
import System.IO
import System.Exit
import System.Environment
import qualified System.ZMQ as ZMQ
import qualified Data.ByteString as SB

main :: IO ()
main = do
    args <- getArgs
    when (length args < 1) $ do
        hPutStrLn stderr "usage: display <address> [<address>, ...]"
        exitFailure
    ZMQ.with 1 $ \c -> do
      s <- ZMQ.socket c ZMQ.Sub
      ZMQ.subscribe s ""
      mapM (ZMQ.connect s) args
      forever $ do
        line <- ZMQ.receive s []
        SB.putStrLn line
        hFlush stdout


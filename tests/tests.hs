import Test.Framework (defaultMain)
import qualified System.ZMQ3.Test.Properties as Properties

main :: IO ()
main = defaultMain Properties.tests


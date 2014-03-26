import Test.Tasty

import qualified System.ZMQ4.Test.Properties as Properties

main :: IO ()
main = defaultMain Properties.tests


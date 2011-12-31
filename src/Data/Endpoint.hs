module Data.Endpoint (
    Endpoint (..)
  , TcpAddress (..)
  , PgmAddress (..)
) where

import Control.Applicative
import Data.IP
import Data.Word
import Data.Char (isDigit)
import Data.String
import Text.Printf
import Text.Read (lift, readPrec)
import Text.ParserCombinators.ReadP

-- | An Endpoint is used in 'connect' and 'bind' calls and specifies
-- a transport plus address data.
data Endpoint =
    InProc String   -- ^ cf. zmq_inproc (7)
  | IPC String      -- ^ cf. zmq_ipc (7)
  | TCP TcpAddress  -- ^ cf. zmq_tcp (7)
  | PGM PgmAddress  -- ^ cf. zmq_pgm (7)
  | EPGM PgmAddress -- ^ cf. zmq_pgm (7)
  deriving Eq

-- | A TcpAddress is either an IP address (IPv4 or IPv6) plus a port
-- number, or an interface name (use @\"*\"@ to refer to all interfaces) plus
-- port number.
data TcpAddress =
    TAddr IP Word16      -- ^ IPv{4,6} address and port number.
  | TIface String Word16 -- ^ Interface name and port number.
  deriving Eq

-- | A (E)PGM address representation.
data PgmAddress =
    PAddr IP IP Word16      -- ^ Interface IP address ';' Multicast IP address ':' port
  | PIface String IP Word16 -- ^ Interface name ';' Multicast IP address ':' port
  deriving Eq

instance Show Endpoint where
    show (InProc x) = printf "inproc://%s" x
    show (IPC x)    = printf "ipc://%s" x
    show (TCP x)    = printf "tcp://%s"  (show x)
    show (PGM x)    = printf "pgm://%s"  (show x)
    show (EPGM x)   = printf "epgm://%s" (show x)

instance Show TcpAddress where
    show (TAddr ip port)    = printf "%s:%u" (show ip) port
    show (TIface name port) = printf "%s:%u" name port

instance Show PgmAddress where
    show (PAddr ip mc port)    = printf "%s;%s:%u" (show ip) (show mc) port
    show (PIface name mc port) = printf "%s;%s:%u" name      (show mc) port

instance Read Endpoint where
    readPrec = lift readEndpoint

instance Read TcpAddress where
    readPrec = lift readTcpAddress

instance Read PgmAddress where
    readPrec = lift readPgmAddress

instance IsString Endpoint where
    fromString = read

instance IsString TcpAddress where
    fromString = read

instance IsString PgmAddress where
    fromString = read

readEndpoint :: ReadP Endpoint
readEndpoint =
      (string "tcp://"    >> TCP    <$> readTcpAddress)
  +++ (string "ipc://"    >> IPC    <$> many1 get)
  +++ (string "inproc://" >> InProc <$> many1 get)
  +++ (string "pgm://"    >> PGM    <$> readPgmAddress)
  +++ (string "epgm://"   >> EPGM   <$> readPgmAddress)

readTcpAddress :: ReadP TcpAddress
readTcpAddress = do
    (ip:port:[]) <- (many1 get) `sepBy1` (char ':')
    if isDigit (head ip)
        then return $ TAddr (read ip) (read port)
        else return $ TIface ip (read port)

readPgmAddress :: ReadP PgmAddress
readPgmAddress = do
    (ip:mc:port:[]) <- (many1 get) `sepBy1` (char ';' +++ char ':')
    if isDigit (head ip)
        then return $ PAddr (read ip) (read mc) (read port)
        else return $ PIface ip (read mc) (read port)


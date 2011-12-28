{-# LANGUAGE EmptyDataDecls         #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE UndecidableInstances   #-}
{-# LANGUAGE TypeSynonymInstances   #-}

module Data.Restricted (

    Restricted
  , Restriction (..)
  , rvalue

  , Nneg1
  , N1
  , N0
  , N254
  , Inf

) where

import Data.Int

-- | Type level range.
data Restricted l u v = Restricted !v

instance (Show l, Show u, Show v) => Show (Restricted l u v) where
    show (Restricted v) = show v

-- | A uniform way to restrict values to a certain range.
class Restriction l u v where
    restrict :: v -> Maybe (Restricted l u v)
    fit      :: v -> Restricted l u v

-- | Get the actual value.
rvalue :: Restricted l u v -> v
rvalue (Restricted v) = v

data Nneg1
data N0
data N1
data N254
data Inf

instance Show Nneg1 where show _ = "Nneg1"
instance Show N0    where show _ = "N0"
instance Show N1    where show _ = "N1"
instance Show N254  where show _ = "N254"
instance Show Inf   where show _ = "Inf"

-- Natural numbers

instance (Integral a) => Restriction N0 Inf a where
    restrict i | lbcheck 0 i = Just $ Restricted i
               | otherwise   = Nothing
    fit = Restricted . lbfit 0

instance (Integral a) => Restriction N0 Int32 a where
    restrict i | check (0, fromIntegral (maxBound :: Int32)) i = Just $ Restricted i
               | otherwise                                     = Nothing
    fit = Restricted . lbfit 0 . ubfit (fromIntegral (maxBound :: Int32))

instance (Integral a) => Restriction N0 Int64 a where
    restrict i | check (0, fromIntegral (maxBound :: Int64)) i = Just $ Restricted i
               | otherwise                                     = Nothing
    fit = Restricted . lbfit 0 . ubfit (fromIntegral (maxBound :: Int64))

-- Positive natural numbers

instance (Integral a) => Restriction N1 Inf a where
    restrict i | lbcheck 1 i = Just $ Restricted i
               | otherwise   = Nothing
    fit = Restricted . lbfit 1

instance (Integral a) => Restriction N1 Int32 a where
    restrict i | check (1, fromIntegral (maxBound :: Int32)) i = Just $ Restricted i
               | otherwise                                     = Nothing
    fit = Restricted . lbfit 1 . ubfit (fromIntegral (maxBound :: Int32))

instance (Integral a) => Restriction N1 Int64 a where
    restrict i | check (1, fromIntegral (maxBound :: Int64)) i = Just $ Restricted i
               | otherwise                                     = Nothing
    fit = Restricted . lbfit 1 . ubfit (fromIntegral (maxBound :: Int64))

-- Other ranges

instance (Integral a) => Restriction Nneg1 Int32 a where
    restrict i | check (-1, fromIntegral (maxBound :: Int32)) i = Just $ Restricted i
               | otherwise                                      = Nothing
    fit = Restricted . lbfit (-1) . ubfit (fromIntegral (maxBound :: Int32))

instance Restriction N1 N254 String where
    restrict s | check (1, 254) (length s) = Just $ Restricted s
               | otherwise                 = Nothing
    fit s | length s < 1 = Restricted " "
          | otherwise    = Restricted (take 254 s)

-- Bounds checks

lbcheck :: Ord a => a -> a -> Bool
lbcheck lb a = a >= lb

ubcheck :: Ord a => a -> a -> Bool
ubcheck ub a = a <= ub

check :: Ord a => (a, a) -> a -> Bool
check (lb, ub) a = lbcheck lb a && ubcheck ub a

-- Fit

lbfit :: Integral a => a -> a -> a
lbfit lb a | a >= lb   = a
           | otherwise = lb

ubfit :: Integral a => a -> a -> a
ubfit ub a | a <= ub   = a
           | otherwise = ub

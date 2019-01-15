-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.Basics.AllSat
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for basic allsat calls
-----------------------------------------------------------------------------

{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveDataTypeable #-}

module TestSuite.Basics.AllSat(tests) where

import Data.Generics
import Utils.SBVTestFramework

import Data.List (sortOn)

tests :: TestTree
tests =
  testGroup "Basics.AllSat"
    [ goldenVsStringShow "allSat1" t1
    , goldenVsStringShow "allSat2" t2
    , goldenVsStringShow "allSat3" $            allSat $ \x -> x .== (0::SFloat)
    , goldenVsStringShow "allSat4" $            allSat $ \x -> x .<  (0::SWord8)
    , goldenVsStringShow "allSat5" $ fmap srt $ allSat $ \x y -> x .< y .&& y .< (4::SWord8)
    , goldenVsStringShow "allSat6" $            allSat $ exists "x" >>= \x -> exists "y" >>= \y -> forall "z" >>= \z -> return (x .< (y::SWord8) .&& y .< 3 .&& z .== (z::SWord8))
    ]

srt :: AllSatResult -> AllSatResult
srt (AllSatResult (b1, b2, rs)) = AllSatResult (b1, b2, sortOn getModelDictionary rs)

newtype Q = Q () deriving (Eq, Ord, Data, Read, Show, SymVal, HasKind)
type SQ = SBV Q

t1 :: IO AllSatResult
t1 = allSat $ do x <- free "x"
                 y <- free "y"
                 return $ x .== (y :: SQ)

t2 :: IO AllSatResult
t2 = allSat $ do x <- free "x"
                 y <- free "y"
                 z <- free "z"
                 return $ x .== (y :: SQ) .&& z .== (z :: SQ)

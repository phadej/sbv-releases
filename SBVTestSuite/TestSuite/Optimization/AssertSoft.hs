-----------------------------------------------------------------------------
-- |
-- Module      :  TestSuite.Optimization.AssertSoft
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Test suite for optimization routines, soft assertions
-----------------------------------------------------------------------------

module TestSuite.Optimization.AssertSoft(tests) where

import Utils.SBVTestFramework

-- Test suite
tests :: TestTree
tests =
  testGroup "Optimization.AssertSoft"
    [ goldenVsStringShow "assertSoft1" (optimize Lexicographic assertSoft1)
    , goldenVsStringShow "assertSoft2" (optimize Lexicographic assertSoft2)
    ]

assertSoft1 :: Goal
assertSoft1 = do x <- sInteger "x"
                 y <- sInteger "y"

                 let a1 = x .> 0
                     a2 = x .< y
                     a3 = x+y .<= 0

                 constrain $ a1 .== a3
                 constrain $ a3 ||| a2

                 assertSoft "as1" a3        (Penalty  3 Nothing)
                 assertSoft "as2" (bnot a3) (Penalty  5 Nothing)
                 assertSoft "as3" (bnot a1) (Penalty 10 Nothing)
                 assertSoft "as4" (bnot a2) (Penalty  3 Nothing)

assertSoft2 :: Goal
assertSoft2 = do a1 <- sBool "a1"
                 a2 <- sBool "a2"
                 a3 <- sBool "a3"

                 assertSoft "as_a1" a1                    (Penalty  0.1 Nothing)
                 assertSoft "as_a2" a2                    (Penalty  1.0 Nothing)
                 assertSoft "as_a3" a3                    (Penalty  1   Nothing)
                 assertSoft "as_a4" (bnot a1 ||| bnot a2) (Penalty 3.2 Nothing)

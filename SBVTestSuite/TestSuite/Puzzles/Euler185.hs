-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.Puzzles.Euler185
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for Documentation.SBV.Examples.Puzzles.Euler185
-----------------------------------------------------------------------------

module TestSuite.Puzzles.Euler185(tests) where

import Documentation.SBV.Examples.Puzzles.Euler185

import Utils.SBVTestFramework

-- Test suite
tests :: TestTree
tests =
  testGroup "Puzzles.Euler185"
    [ goldenVsStringShow "euler185" (allSat euler185)
    ]

-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.CodeGeneration.Fibonacci
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for Documentation.SBV.Examples.CodeGeneration.Fibonacci
-----------------------------------------------------------------------------

module TestSuite.CodeGeneration.Fibonacci(tests) where

import Data.SBV.Internals
import Documentation.SBV.Examples.CodeGeneration.Fibonacci

import Utils.SBVTestFramework

-- Test suite
tests :: TestTree
tests = testGroup "CodeGeneration.Fibonacci" [
   goldenVsStringShow "fib1" $ tst [12] "fib1" (fib1 64)
 , goldenVsStringShow "fib2" $ tst [20] "fib2" (fib2 64)
 ]
 where tst vs nm f = snd <$> compileToC' nm (do cgPerformRTCs True
                                                cgSetDriverValues vs
                                                n <- cgInput "n"
                                                cgReturn $ f n)

-----------------------------------------------------------------------------
-- |
-- Module    : TestSuite.Basics.Index
-- Author    : Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Test suite for Examples.Basics.Index
-----------------------------------------------------------------------------

module TestSuite.Basics.Index(tests) where

import Utils.SBVTestFramework

tests :: TestTree
tests =
  testGroup "Basics.Index"
    (zipWith
      mkTest
      [f x | f <- [test1, test2, test3], x <- [0..13]]
      [(0::Int)..])

mkTest :: IO Bool -> Int -> TestTree
mkTest tst i =
  testCase ("index-" ++ show i)
    (assert tst)

-- prove that the "select" primitive is working correctly
test1 :: Int -> IO Bool
test1 n = isTheorem $ do
            elts <- mkForallVars n
            err  <- forall_
            ind  <- forall_
            ind2 <- forall_
            let r1 = (select :: [SWord8] -> SWord8 -> SInt8 -> SWord8) elts err ind
                r2 = (select :: [SWord8] -> SWord8 -> SWord8 -> SWord8) elts err ind2
                r3 = slowSearch elts err ind
                r4 = slowSearch elts err ind2
            return $ r1 .== r3 .&& r2 .== r4
 where slowSearch elts err i = ite (i .< 0) err (go elts i)
         where go []     _      = err
               go (x:xs) curInd = ite (curInd .== 0) x (go xs (curInd - 1))

test2 :: Int -> IO Bool
test2 n = isTheorem $ do
            elts1 <- mkForallVars n
            elts2 <- mkForallVars n
            let elts = zip elts1 elts2
            err1  <- forall_
            err2  <- forall_
            let err = (err1, err2)
            ind  <- forall_
            ind2 <- forall_
            let r1 = (select :: [(SWord8, SWord8)] -> (SWord8, SWord8) -> SInt8 -> (SWord8, SWord8)) elts err ind
                r2 = (select :: [(SWord8, SWord8)] -> (SWord8, SWord8) -> SWord8 -> (SWord8, SWord8)) elts err ind2
                r3 = slowSearch elts err ind
                r4 = slowSearch elts err ind2
            return $ r1 .== r3 .&& r2 .== r4
 where slowSearch elts err i = ite (i .< 0) err (go elts i)
         where go []     _      = err
               go (x:xs) curInd = ite (curInd .== 0) x (go xs (curInd - 1))

test3 :: Int -> IO Bool
test3 n = isTheorem $ do
            eltsI <- mkForallVars n
            let elts = map Left eltsI
            errI  <- forall_
            let err = Left errI
            ind  <- forall_
            let r1 = (select :: [Either SWord8 SWord8] -> Either SWord8 SWord8 -> SInt8 -> Either SWord8 SWord8) elts err ind
                r2 = slowSearch elts err ind
            return $ r1 .== r2
 where slowSearch elts err i = ite (i .< 0) err (go elts i)
         where go []     _      = err
               go (x:xs) curInd = ite (curInd .== 0) x (go xs (curInd - 1))

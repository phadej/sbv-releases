----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.SMT.SMTLib2
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Conversion of symbolic programs to SMTLib format, Using v2 of the standard
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Data.SBV.SMT.SMTLib2(cvt, addNonEqConstraints) where

import Data.Bits     (bit)
import Data.Function (on)
import Data.Ord      (comparing)
import Data.List     (intercalate, partition, groupBy, sortBy)

import qualified Data.Foldable as F (toList)
import qualified Data.Map      as M
import qualified Data.IntMap   as IM
import qualified Data.Set      as Set

import Data.SBV.BitVectors.Data
import Data.SBV.BitVectors.PrettyNum (smtRoundingMode, cwToSMTLib)

-- | Add constraints to generate /new/ models. This function is used to query the SMT-solver, while
-- disallowing a previous model.
addNonEqConstraints :: RoundingMode -> [(Quantifier, NamedSymVar)] -> [[(String, CW)]] -> SMTLibPgm -> Maybe String
addNonEqConstraints rm qinps allNonEqConstraints (SMTLibPgm _ (aliasTable, pre, post))
  | null allNonEqConstraints
  = Just $ intercalate "\n" $ pre ++ post
  | null refutedModel
  = Nothing
  | True
  = Just $ intercalate "\n" $ pre
    ++ [ "; --- refuted-models ---" ]
    ++ refutedModel
    ++ post
 where refutedModel = concatMap (nonEqs rm . map intName) nonEqConstraints
       intName (s, c)
          | Just sw <- s `lookup` aliasTable = (show sw, c)
          | True                             = (s, c)
       -- with existentials, we only add top-level existentials to the refuted-models list
       nonEqConstraints = filter (not . null) $ map (filter (\(s, _) -> s `elem` topUnivs)) allNonEqConstraints
       topUnivs = [s | (_, (_, s)) <- takeWhile (\p -> fst p == EX) qinps]

nonEqs :: RoundingMode -> [(String, CW)] -> [String]
nonEqs rm scs = format $ interp ps ++ disallow (map eqClass uninterpClasses)
  where isFree (KUserSort _ (Left _, _)) = True
        isFree _                         = False
        (ups, ps) = partition (isFree . kindOf . snd) scs
        format []     =  []
        format [m]    =  ["(assert " ++ m ++ ")"]
        format (m:ms) =  ["(assert (or " ++ m]
                      ++ map ("            " ++) ms
                      ++ ["        ))"]
        -- Regular (or interpreted) sorts simply get a constraint that we disallow the current assignment
        interp = map $ nonEq rm
        -- Determine the equivalence classes of uninterpreted sorts:
        uninterpClasses = filter (\l -> length l > 1) -- Only need this class if it has at least two members
                        . map (map fst)               -- throw away sorts, we only need the names
                        . groupBy ((==) `on` snd)     -- make sure they belong to the same sort and have the same value
                        . sortBy (comparing snd)      -- sort them according to their sorts first
                        $ ups                         -- take the uninterpreted sorts
        -- Uninterpreted sorts get a constraint that says the equivalence classes as determined by the solver are disallowed:
        eqClass :: [String] -> String
        eqClass [] = error "SBV.allSat.nonEqs: Impossible happened, disallow received an empty list"
        eqClass cs = "(= " ++ unwords cs ++ ")"
        -- Now, take the conjunction of equivalence classes and assert it's negation:
        disallow = map $ \ec -> "(not " ++ ec ++ ")"

nonEq :: RoundingMode -> (String, CW) -> String
nonEq rm (s, c) = "(not (= " ++ s ++ " " ++ cvtCW rm c ++ "))"

tbd :: String -> a
tbd e = error $ "SBV.SMTLib2: Not-yet-supported: " ++ e

-- | Translate a problem into an SMTLib2 script
cvt :: RoundingMode               -- ^ User selected rounding mode to be used for floating point arithmetic
    -> Maybe Logic                  -- ^ SMT-Lib logic, if requested by the user
    -> SolverCapabilities           -- ^ capabilities of the current solver
    -> Set.Set Kind                 -- ^ kinds used
    -> Bool                         -- ^ is this a sat problem?
    -> [String]                     -- ^ extra comments to place on top
    -> [(Quantifier, NamedSymVar)]  -- ^ inputs
    -> [Either SW (SW, [SW])]       -- ^ skolemized version inputs
    -> [(SW, CW)]                   -- ^ constants
    -> [((Int, Kind, Kind), [SW])]  -- ^ auto-generated tables
    -> [(Int, ArrayInfo)]           -- ^ user specified arrays
    -> [(String, SBVType)]          -- ^ uninterpreted functions/constants
    -> [(String, [String])]         -- ^ user given axioms
    -> SBVPgm                       -- ^ assignments
    -> [SW]                         -- ^ extra constraints
    -> SW                           -- ^ output variable
    -> ([String], [String])
cvt rm smtLogic solverCaps kindInfo isSat comments inputs skolemInps consts tbls arrs uis axs (SBVPgm asgnsSeq) cstrs out = (pre, [])
  where -- the logic is an over-approaximation
        hasInteger = KUnbounded `Set.member` kindInfo
        hasReal    = KReal      `Set.member` kindInfo
        hasFloat   = KFloat     `Set.member` kindInfo
        hasDouble  = KDouble    `Set.member` kindInfo
        hasBVs     = not $ null [() | KBounded{} <- Set.toList kindInfo]
        usorts     = [(s, dt) | KUserSort s dt <- Set.toList kindInfo]
        logic
           | Just l <- smtLogic
           = ["(set-logic " ++ show l ++ ") ; NB. User specified."]
           | hasDouble || hasFloat    -- NB. We don't check for quantifiers here, we probably should..
           = if hasBVs
             then ["(set-logic QF_FPBV)"]
             else ["(set-logic QF_FP)"]
           | hasInteger || hasReal || not (null usorts)
           = case mbDefaultLogic solverCaps of
                Nothing -> ["; Has unbounded values (Int/Real) or uninterpreted sorts; no logic specified."]   -- combination, let the solver pick
                Just l  -> ["(set-logic " ++ l ++ ")"]
           | True
           = ["(set-logic " ++ qs ++ as ++ ufs ++ "BV)"]
          where qs  | null foralls && null axs = "QF_"  -- axioms are likely to contain quantifiers
                    | True                     = ""
                as  | null arrs                = ""
                    | True                     = "A"
                ufs | null uis && null tbls    = ""     -- we represent tables as UFs
                    | True                     = "UF"
        getModels
          | supportsProduceModels solverCaps = ["(set-option :produce-models true)"]
          | True                             = []
        pre  =  ["; Automatically generated by SBV. Do not edit."]
             ++ map ("; " ++) comments
             ++ getModels
             ++ logic
             ++ [ "; --- uninterpreted sorts ---" ]
             ++ concatMap declSort usorts
             ++ [ "; --- literal constants ---" ]
             ++ concatMap (declConst (supportsMacros solverCaps)) consts
             ++ [ "; --- skolem constants ---" ]
             ++ [ "(declare-fun " ++ show s ++ " " ++ swFunType ss s ++ ")" ++ userName s | Right (s, ss) <- skolemInps]
             ++ [ "; --- constant tables ---" ]
             ++ concatMap constTable constTables
             ++ [ "; --- skolemized tables ---" ]
             ++ map (skolemTable (unwords (map swType foralls))) skolemTables
             ++ [ "; --- arrays ---" ]
             ++ concat arrayConstants
             ++ [ "; --- uninterpreted constants ---" ]
             ++ concatMap declUI uis
             ++ [ "; --- user given axioms ---" ]
             ++ map declAx axs
             ++ [ "; --- formula ---" ]
             ++ [if null foralls
                 then "(assert ; no quantifiers"
                 else "(assert (forall (" ++ intercalate "\n                 "
                                             ["(" ++ show s ++ " " ++ swType s ++ ")" | s <- foralls] ++ ")"]
             ++ map (letAlign . mkLet) asgns
             ++ map letAlign (if null delayedEqualities then [] else ("(and " ++ deH) : map (align 5) deTs)
             ++ [ impAlign (letAlign assertOut) ++ replicate noOfCloseParens ')' ]
        noOfCloseParens = length asgns + (if null foralls then 1 else 2) + (if null delayedEqualities then 0 else 1)
        (constTables, skolemTables) = ([(t, d) | (t, Left d) <- allTables], [(t, d) | (t, Right d) <- allTables])
        allTables = [(t, genTableData rm skolemMap (not (null foralls), forallArgs) (map fst consts) t) | t <- tbls]
        (arrayConstants, allArrayDelayeds) = unzip $ map (declArray (not (null foralls)) (map fst consts) skolemMap) arrs
        delayedEqualities@(~(deH:deTs)) = concatMap snd skolemTables ++ concat allArrayDelayeds
        foralls = [s | Left s <- skolemInps]
        forallArgs = concatMap ((" " ++) . show) foralls
        letAlign s
          | null foralls = "   " ++ s
          | True         = "            " ++ s
        impAlign s
          | null delayedEqualities = s
          | True                   = "     " ++ s
        align n s = replicate n ' ' ++ s
        -- if sat,   we assert cstrs /\ out
        -- if prove, we assert ~(cstrs => out) = cstrs /\ not out
        assertOut
           | null cstrs = o
           | True       = "(and " ++ unwords (map mkConj cstrs ++ [o]) ++ ")"
           where mkConj = cvtSW skolemMap
                 o | isSat =            mkConj out
                   | True  = "(not " ++ mkConj out ++ ")"
        skolemMap = M.fromList [(s, ss) | Right (s, ss) <- skolemInps, not (null ss)]
        tableMap  = IM.fromList $ map mkConstTable constTables ++ map mkSkTable skolemTables
          where mkConstTable (((t, _, _), _), _) = (t, "table" ++ show t)
                mkSkTable    (((t, _, _), _), _) = (t, "table" ++ show t ++ forallArgs)
        asgns = F.toList asgnsSeq
        mkLet (s, e) = "(let ((" ++ show s ++ " " ++ cvtExp rm skolemMap tableMap e ++ "))"
        declConst useDefFun (s, c)
          | useDefFun = ["(define-fun "   ++ varT ++ " " ++ cvtCW rm c ++ ")"]
          | True      = [ "(declare-fun " ++ varT ++ ")"
                        , "(assert (= "   ++ show s ++ " " ++ cvtCW rm c ++ "))"
                        ]
          where varT = show s ++ " " ++ swFunType [] s
        userName s = case s `lookup` map snd inputs of
                        Just u  | show s /= u -> " ; tracks user variable " ++ show u
                        _ -> ""
        -- following sorts are built-in; do not translate them:
        builtInSort = (`elem` ["RoundingMode"])
        declSort (s, _)
          | builtInSort s           = []
        declSort (s, (Left  r,  _)) = ["(declare-sort " ++ s ++ " 0)  ; N.B. Uninterpreted: " ++ r]
        declSort (s, (Right fs, _)) = [ "(declare-datatypes () ((" ++ s ++ " " ++ unwords (map (\c -> "(" ++ c ++ ")") fs) ++ ")))"
                                      , "(define-fun " ++ s ++ "_constrIndex ((x " ++ s ++ ")) Int"
                                      ] ++ ["   " ++ body fs (0::Int)] ++ [")"]
                where body []     _ = ""
                      body [_]    i = show i
                      body (c:cs) i = "(ite (= x " ++ c ++ ") " ++ show i ++ " " ++ body cs (i+1) ++ ")"

declUI :: (String, SBVType) -> [String]
declUI (i, t) = ["(declare-fun " ++ i ++ " " ++ cvtType t ++ ")"]

-- NB. We perform no check to as to whether the axiom is meaningful in any way.
declAx :: (String, [String]) -> String
declAx (nm, ls) = (";; -- user given axiom: " ++ nm ++ "\n") ++ intercalate "\n" ls

constTable :: (((Int, Kind, Kind), [SW]), [String]) -> [String]
constTable (((i, ak, rk), _elts), is) = decl : map wrap is
  where t       = "table" ++ show i
        decl    = "(declare-fun " ++ t ++ " (" ++ smtType ak ++ ") " ++ smtType rk ++ ")"
        wrap  s = "(assert " ++ s ++ ")"

skolemTable :: String -> (((Int, Kind, Kind), [SW]), [String]) -> String
skolemTable qsIn (((i, ak, rk), _elts), _) = decl
  where qs   = if null qsIn then "" else qsIn ++ " "
        t    = "table" ++ show i
        decl = "(declare-fun " ++ t ++ " (" ++ qs ++ smtType ak ++ ") " ++ smtType rk ++ ")"

-- Left if all constants, Right if otherwise
genTableData :: RoundingMode -> SkolemMap -> (Bool, String) -> [SW] -> ((Int, Kind, Kind), [SW]) -> Either [String] [String]
genTableData rm skolemMap (_quantified, args) consts ((i, aknd, _), elts)
  | null post = Left  (map (topLevel . snd) pre)
  | True      = Right (map (nested   . snd) (pre ++ post))
  where ssw = cvtSW skolemMap
        (pre, post) = partition fst (zipWith mkElt elts [(0::Int)..])
        t           = "table" ++ show i
        mkElt x k   = (isReady, (idx, ssw x))
          where idx = cvtCW rm (mkConstCW aknd k)
                isReady = x `elem` consts
        topLevel (idx, v) = "(= (" ++ t ++ " " ++ idx ++ ") " ++ v ++ ")"
        nested   (idx, v) = "(= (" ++ t ++ args ++ " " ++ idx ++ ") " ++ v ++ ")"

-- TODO: We currently do not support non-constant arrays when quantifiers are present, as
-- we might have to skolemize those. Implement this properly.
-- The difficulty is with the ArrayReset/Mutate/Merge: We have to postpone an init if
-- the components are themselves postponed, so this cannot be implemented as a simple map.
declArray :: Bool -> [SW] -> SkolemMap -> (Int, ArrayInfo) -> ([String], [String])
declArray quantified consts skolemMap (i, (_, (aKnd, bKnd), ctx)) = (adecl : map wrap pre, map snd post)
  where topLevel = not quantified || case ctx of
                                       ArrayFree Nothing -> True
                                       ArrayFree (Just sw) -> sw `elem` consts
                                       ArrayReset _ sw     -> sw `elem` consts
                                       ArrayMutate _ a b   -> all (`elem` consts) [a, b]
                                       ArrayMerge c _ _    -> c `elem` consts
        (pre, post) = partition fst ctxInfo
        nm = "array_" ++ show i
        ssw sw
         | topLevel || sw `elem` consts
         = cvtSW skolemMap sw
         | True
         = tbd "Non-constant array initializer in a quantified context"
        adecl = "(declare-fun " ++ nm ++ " () (Array " ++ smtType aKnd ++ " " ++ smtType bKnd ++ "))"
        ctxInfo = case ctx of
                    ArrayFree Nothing   -> []
                    ArrayFree (Just sw) -> declA sw
                    ArrayReset _ sw     -> declA sw
                    ArrayMutate j a b -> [(all (`elem` consts) [a, b], "(= " ++ nm ++ " (store array_" ++ show j ++ " " ++ ssw a ++ " " ++ ssw b ++ "))")]
                    ArrayMerge  t j k -> [(t `elem` consts,            "(= " ++ nm ++ " (ite " ++ ssw t ++ " array_" ++ show j ++ " array_" ++ show k ++ "))")]
        declA sw = let iv = nm ++ "_freeInitializer"
                   in [ (True,             "(declare-fun " ++ iv ++ " () " ++ smtType aKnd ++ ")")
                      , (sw `elem` consts, "(= (select " ++ nm ++ " " ++ iv ++ ") " ++ ssw sw ++ ")")
                      ]
        wrap (False, s) = s
        wrap (True, s)  = "(assert " ++ s ++ ")"

swType :: SW -> String
swType s = smtType (kindOf s)

swFunType :: [SW] -> SW -> String
swFunType ss s = "(" ++ unwords (map swType ss) ++ ") " ++ swType s

smtType :: Kind -> String
smtType KBool           = "Bool"
smtType (KBounded _ sz) = "(_ BitVec " ++ show sz ++ ")"
smtType KUnbounded      = "Int"
smtType KReal           = "Real"
smtType KFloat          = "(_ FloatingPoint  8 24)"
smtType KDouble         = "(_ FloatingPoint 11 53)"
smtType (KUserSort s _) = s

cvtType :: SBVType -> String
cvtType (SBVType []) = error "SBV.SMT.SMTLib2.cvtType: internal: received an empty type!"
cvtType (SBVType xs) = "(" ++ unwords (map smtType body) ++ ") " ++ smtType ret
  where (body, ret) = (init xs, last xs)

type SkolemMap = M.Map  SW [SW]
type TableMap  = IM.IntMap String

cvtSW :: SkolemMap -> SW -> String
cvtSW skolemMap s
  | Just ss <- s `M.lookup` skolemMap
  = "(" ++ show s ++ concatMap ((" " ++) . show) ss ++ ")"
  | True
  = show s

cvtCW :: RoundingMode -> CW -> String
cvtCW = cwToSMTLib

getTable :: TableMap -> Int -> String
getTable m i
  | Just tn <- i `IM.lookup` m = tn
  | True                       = error $ "SBV.SMTLib2: Cannot locate table " ++ show i

cvtExp :: RoundingMode -> SkolemMap -> TableMap -> SBVExpr -> String
cvtExp rm skolemMap tableMap expr@(SBVApp _ arguments) = sh expr
  where ssw = cvtSW skolemMap
        bvOp     = all isBounded       arguments
        intOp    = any isInteger       arguments
        realOp   = any isReal          arguments
        doubleOp = any isDouble        arguments
        floatOp  = any isFloat         arguments
        boolOp   = all isBoolean       arguments
        bad | intOp = error $ "SBV.SMTLib2: Unsupported operation on unbounded integers: " ++ show expr
            | True  = error $ "SBV.SMTLib2: Unsupported operation on real values: " ++ show expr
        ensureBVOrBool = bvOp || boolOp || bad
        ensureBV       = bvOp || bad
        addRM s = s ++ " " ++ smtRoundingMode rm
        lift2  o _ [x, y] = "(" ++ o ++ " " ++ x ++ " " ++ y ++ ")"
        lift2  o _ sbvs   = error $ "SBV.SMTLib2.sh.lift2: Unexpected arguments: "   ++ show (o, sbvs)
        -- lift a binary operation with rounding-mode added; used for floating-point arithmetic
        lift2WM o fo | doubleOp || floatOp = lift2 (addRM fo)
                     | True                = lift2 o
        lift1FP o fo | doubleOp || floatOp = lift1 fo
                     | True                = lift1 o
        liftAbs sgned args | doubleOp || floatOp = lift1 "fp.abs" sgned args
                           | intOp               = lift1 "abs"    sgned args
                           | bvOp, sgned         = mkAbs (head args) "bvslt" "bvneg"
                           | bvOp                = head args
                           | True                = mkAbs (head args) "<"     "-"
          where mkAbs x cmp neg = "(ite " ++ ltz ++ " " ++ nx ++ " " ++ x ++ ")"
                  where ltz = "(" ++ cmp ++ " " ++ x ++ " " ++ z ++ ")"
                        nx  = "(" ++ neg ++ " " ++ x ++ ")"
                        z   = cvtCW rm (mkConstCW (kindOf (head arguments)) (0::Integer))
        lift2B bOp vOp
          | boolOp = lift2 bOp
          | True   = lift2 vOp
        lift1B bOp vOp
          | boolOp = lift1 bOp
          | True   = lift1 vOp
        eqBV sgn sbvs
           | boolOp = lift2 "=" sgn sbvs
           | True   = "(= " ++ lift2 "bvcomp" sgn sbvs ++ " #b1)"
        neqBV sgn sbvs = "(not " ++ eqBV sgn sbvs ++ ")"
        equal sgn sbvs
          | doubleOp = lift2 "fp.eq" sgn sbvs
          | floatOp  = lift2 "fp.eq" sgn sbvs
          | True     = lift2 "=" sgn sbvs
        notEqual sgn sbvs
          | doubleOp = "(not " ++ equal sgn sbvs ++ ")"
          | floatOp  = "(not " ++ equal sgn sbvs ++ ")"
          | True     = lift2 "distinct" sgn sbvs
        lift2S oU oS sgn = lift2 (if sgn then oS else oU) sgn
        lift2Cmp o fo | doubleOp || floatOp = lift2 fo
                      | True                = lift2 o
        unintComp o [a, b]
          | KUserSort s (Right _, _) <- kindOf (head arguments)
          = let idx v = "(" ++ s ++ "_constrIndex " ++ " " ++ v ++ ")" in "(" ++ o ++ " " ++ idx a ++ " " ++ idx b ++ ")"
        unintComp o sbvs = error $ "SBV.SMT.SMTLib2.sh.unintComp: Unexpected arguments: "   ++ show (o, sbvs)
        lift1  o _ [x]    = "(" ++ o ++ " " ++ x ++ ")"
        lift1  o _ sbvs   = error $ "SBV.SMT.SMTLib2.sh.lift1: Unexpected arguments: "   ++ show (o, sbvs)
        sh (SBVApp Ite [a, b, c]) = "(ite " ++ ssw a ++ " " ++ ssw b ++ " " ++ ssw c ++ ")"
        sh (SBVApp (LkUp (t, aKnd, _, l) i e) [])
          | needsCheck = "(ite " ++ cond ++ ssw e ++ " " ++ lkUp ++ ")"
          | True       = lkUp
          where needsCheck = case aKnd of
                              KBool         -> (2::Integer) > fromIntegral l
                              KBounded _ n  -> (2::Integer)^n > fromIntegral l
                              KUnbounded    -> True
                              KReal         -> error "SBV.SMT.SMTLib2.cvtExp: unexpected real valued index"
                              KFloat        -> error "SBV.SMT.SMTLib2.cvtExp: unexpected float valued index"
                              KDouble       -> error "SBV.SMT.SMTLib2.cvtExp: unexpected double valued index"
                              KUserSort s _ -> error $ "SBV.SMT.SMTLib2.cvtExp: unexpected uninterpreted valued index: " ++ s
                lkUp = "(" ++ getTable tableMap t ++ " " ++ ssw i ++ ")"
                cond
                 | hasSign i = "(or " ++ le0 ++ " " ++ gtl ++ ") "
                 | True      = gtl ++ " "
                (less, leq) = case aKnd of
                                KBool         -> error "SBV.SMT.SMTLib2.cvtExp: unexpected boolean valued index"
                                KBounded{}    -> if hasSign i then ("bvslt", "bvsle") else ("bvult", "bvule")
                                KUnbounded    -> ("<", "<=")
                                KReal         -> ("<", "<=")
                                KFloat        -> ("fp.lt", "fp.leq")
                                KDouble       -> ("fp.lt", "fp.geq")
                                KUserSort s _ -> error $ "SBV.SMT.SMTLib2.cvtExp: unexpected uninterpreted valued index: " ++ s
                mkCnst = cvtCW rm . mkConstCW (kindOf i)
                le0  = "(" ++ less ++ " " ++ ssw i ++ " " ++ mkCnst 0 ++ ")"
                gtl  = "(" ++ leq  ++ " " ++ mkCnst l ++ " " ++ ssw i ++ ")"
        sh (SBVApp (ArrEq i j) []) = "(= array_" ++ show i ++ " array_" ++ show j ++")"
        sh (SBVApp (ArrRead i) [a]) = "(select array_" ++ show i ++ " " ++ ssw a ++ ")"
        sh (SBVApp (Uninterpreted nm) [])   = nm
        sh (SBVApp (Uninterpreted nm) args) = "(" ++ nm' ++ " " ++ unwords (map ssw args) ++ ")"
          where -- slight hack needed here to take advantage of custom floating-point functions.. sigh.
                fpSpecials = ["fp.sqrt", "fp.fma"]
                nm' | (floatOp || doubleOp) && (nm `elem` fpSpecials) = addRM nm
                    | True                                            = nm
        sh (SBVApp (Extract i j) [a]) | ensureBV = "((_ extract " ++ show i ++ " " ++ show j ++ ") " ++ ssw a ++ ")"
        sh (SBVApp (Rol i) [a])
           | bvOp  = rot  ssw "rotate_left"  i a
           | intOp = sh (SBVApp (Shl i) [a])       -- Haskell treats rotateL as shiftL for unbounded values
           | True  = bad
        sh (SBVApp (Ror i) [a])
           | bvOp  = rot  ssw "rotate_right" i a
           | intOp = sh (SBVApp (Shr i) [a])     -- Haskell treats rotateR as shiftR for unbounded values
           | True  = bad
        sh (SBVApp (Shl i) [a])
           | bvOp   = shft rm ssw "bvshl"  "bvshl"  i a
           | i < 0  = sh (SBVApp (Shr (-i)) [a])  -- flip sign/direction
           | intOp  = "(* " ++ ssw a ++ " " ++ show (bit i :: Integer) ++ ")"  -- Implement shiftL by multiplication by 2^i
           | True   = bad
        sh (SBVApp (Shr i) [a])
           | bvOp  = shft rm ssw "bvlshr" "bvashr" i a
           | i < 0 = sh (SBVApp (Shl (-i)) [a])  -- flip sign/direction
           | intOp = "(div " ++ ssw a ++ " " ++ show (bit i :: Integer) ++ ")"  -- Implement shiftR by division by 2^i
           | True  = bad
        sh (SBVApp op args)
          | Just f <- lookup op smtBVOpTable, ensureBVOrBool
          = f (any hasSign args) (map ssw args)
          where -- The first 4 operators below do make sense for Integer's in Haskell, but there's
                -- no obvious counterpart for them in the SMTLib translation.
                -- TODO: provide support for these.
                smtBVOpTable = [ (And,  lift2B "and" "bvand")
                               , (Or,   lift2B "or"  "bvor")
                               , (XOr,  lift2B "xor" "bvxor")
                               , (Not,  lift1B "not" "bvnot")
                               , (Join, lift2 "concat")
                               ]
        sh (SBVApp (FPRound w) args)
          = "(" ++ w ++ " " ++ unwords (map ssw args) ++ ")"
        sh inp@(SBVApp op args)
          | intOp, Just f <- lookup op smtOpIntTable
          = f True (map ssw args)
          | boolOp, Just f <- lookup op boolComps
          = f (map ssw args)
          | bvOp, Just f <- lookup op smtOpBVTable
          = f (any hasSign args) (map ssw args)
          | realOp, Just f <- lookup op smtOpRealTable
          = f (any hasSign args) (map ssw args)
          | floatOp || doubleOp, Just f <- lookup op smtOpFloatDoubleTable
          = f (any hasSign args) (map ssw args)
          | Just f <- lookup op uninterpretedTable
          = f (map ssw args)
          | True
          = error $ "SBV.SMT.SMTLib2.cvtExp.sh: impossible happened; can't translate: " ++ show inp
          where smtOpBVTable  = [ (Plus,          lift2   "bvadd")
                                , (Minus,         lift2   "bvsub")
                                , (Times,         lift2   "bvmul")
                                , (UNeg,          lift1B  "not"    "bvneg")
                                , (Abs,           liftAbs)
                                , (Quot,          lift2S  "bvudiv" "bvsdiv")
                                , (Rem,           lift2S  "bvurem" "bvsrem")
                                , (Equal,         eqBV)
                                , (NotEqual,      neqBV)
                                , (LessThan,      lift2S  "bvult" "bvslt")
                                , (GreaterThan,   lift2S  "bvugt" "bvsgt")
                                , (LessEq,        lift2S  "bvule" "bvsle")
                                , (GreaterEq,     lift2S  "bvuge" "bvsge")
                                ]
                -- Boolean comparisons.. SMTLib's bool type doesn't do comparisons, but Haskell does.. Sigh
                boolComps      = [ (LessThan,      blt)
                                 , (GreaterThan,   blt . swp)
                                 , (LessEq,        blq)
                                 , (GreaterEq,     blq . swp)
                                 ]
                               where blt [x, y] = "(and (not " ++ x ++ ") " ++ y ++ ")"
                                     blt xs     = error $ "SBV.SMT.SMTLib2.boolComps.blt: Impossible happened, incorrect arity (expected 2): " ++ show xs
                                     blq [x, y] = "(or (not " ++ x ++ ") " ++ y ++ ")"
                                     blq xs     = error $ "SBV.SMT.SMTLib2.boolComps.blq: Impossible happened, incorrect arity (expected 2): " ++ show xs
                                     swp [x, y] = [y, x]
                                     swp xs     = error $ "SBV.SMT.SMTLib2.boolComps.swp: Impossible happened, incorrect arity (expected 2): " ++ show xs
                smtOpRealTable =  smtIntRealShared
                               ++ [ (Quot,        lift2WM "/" "fp.div")
                                  ]
                smtOpIntTable  = smtIntRealShared
                               ++ [ (Quot,        lift2   "div")
                                  , (Rem,         lift2   "mod")
                                  ]
                smtOpFloatDoubleTable = smtIntRealShared
                                  ++ [(Quot, lift2WM "/" "fp.div")]
                smtIntRealShared  = [ (Plus,          lift2WM "+" "fp.add")
                                    , (Minus,         lift2WM "-" "fp.sub")
                                    , (Times,         lift2WM "*" "fp.mul")
                                    , (UNeg,          lift1FP "-" "fp.neg")
                                    , (Abs,           liftAbs)
                                    , (Equal,         equal)
                                    , (NotEqual,      notEqual)
                                    , (LessThan,      lift2Cmp  "<"  "fp.lt")
                                    , (GreaterThan,   lift2Cmp  ">"  "fp.gt")
                                    , (LessEq,        lift2Cmp  "<=" "fp.leq")
                                    , (GreaterEq,     lift2Cmp  ">=" "fp.geq")
                                    ]
                -- equality and comparisons are the only thing that works on uninterpreted sorts
                uninterpretedTable = [ (Equal,       lift2S "="        "="        True)
                                     , (NotEqual,    lift2S "distinct" "distinct" True)
                                     , (LessThan,    unintComp "<")
                                     , (GreaterThan, unintComp ">")
                                     , (LessEq,      unintComp "<=")
                                     , (GreaterEq,   unintComp ">=")
                                     ]

rot :: (SW -> String) -> String -> Int -> SW -> String
rot ssw o c x = "((_ " ++ o ++ " " ++ show c ++ ") " ++ ssw x ++ ")"

shft :: RoundingMode -> (SW -> String) -> String -> String -> Int -> SW -> String
shft rm ssw oW oS c x = "(" ++ o ++ " " ++ ssw x ++ " " ++ cvtCW rm c' ++ ")"
   where s  = hasSign x
         c' = mkConstCW (kindOf x) c
         o  = if s then oS else oW

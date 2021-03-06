{-# LANGUAGE TemplateHaskell, TypeFamilies, TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Golog.InterpreterTest where

import Data.List (sort)
import Data.Maybe (fromJust)
import Golog.Interpreter
import Golog.Macro
import Golog.Util
import Test.QuickCheck.All
import Test.QuickCheck.Arbitrary
import Test.QuickCheck.Gen
import Test.QuickCheck.Modifiers

newtype Lookahead = Lookahead Int deriving Show

instance Arbitrary Lookahead where
   arbitrary = fmap Lookahead $ oneof $ map return [0..9]

instance BAT Int where
   data Sit Int = S0 | Do Int (Sit Int) deriving (Eq, Ord, Show)
   s0  = S0
   do_ = Do
   poss _ S0       = True
   poss i (Do j s) = even i == odd j

instance DTBAT Int where
   newtype Reward Int = Reward (Int,Int) deriving (Eq, Ord)
   reward S0 = Reward (0,0)
   reward (Do i s) = Reward (i+i',1+l')
      where Reward (i',l') = reward s

instance Monad m => IOBAT Int m where
   -- For our tests, syncA should preserve whether or not a is even or odd.
   -- Reason: dooIO (const Online) performs trans' and then applies sync.
   -- If we have a program 1;2;3, this leads to
   --    1 --trans--> Just 1 --sync--> 2 --trans--> Nothing
   -- because then 2 (even number) is executed in an even situation (due to
   -- sync).
   -- This does of course not occur when we first use dooBFS' and then apply
   -- sync -- the final configuration, because then no preconditions are
   -- checked.
   syncA a s = return $ do_ (a+2) s

data Prim = A | B | C | D deriving (Eq, Ord, Show)

instance BAT Prim where
   data Sit Prim = S0' | Do' Prim (Sit Prim) deriving (Eq, Ord, Show)
   s0  = S0'
   do_ = Do'
   poss _ _ = True

instance DTBAT Prim where
   newtype Reward Prim = Reward' { rew :: Int } deriving (Eq, Ord)
   reward (Do' C s@(Do' A _)) = Reward' $ 1000 + rew (reward s)
   reward (Do' D s@(Do' B _)) = Reward' $ 1000 + rew (reward s)
   reward (Do' _ s)           = Reward' $    0 + rew (reward s)
   reward S0'                 = Reward' $    0

instance Monad m => IOBAT Prim m where
   syncA A s = return $ do_ B s
   syncA B s = return $ do_ A s
   syncA a s = return $ do_ a s

trans'' = head . trans

p :: Int -> Prog Int
p = prim

prop_final1 = final $ treeND (Nil :: Prog Int) s0
prop_final2 = not $ final $ treeND (p 1 `Seq` p 2) s0
prop_final3 = final $ treeND (choice [Nil, p 1 `Seq` p 2]) s0
prop_final4 = final $ treeND (iter (p 1 `Seq` p 2)) s0
prop_final5 = not $ final $ treeND (plus (p 1 `Seq` p 2)) s0
prop_final6 = not $ final $ trans'' $ treeND (p 1 `Seq` p 2) s0
prop_final7 = final $ trans'' $ trans'' $ treeND (p 1 `Seq` p 2) s0
prop_final8 = not $ final $ trans'' $ treeND (iter (p 1 `Seq` p 2)) s0
prop_final9 = final $ trans'' $ trans'' $ treeND (iter (p 1 `Seq` p 2)) s0

prop_final10 (Lookahead l) = not $ final $                     treeDT l (iter (p 1 `Seq` p 2)) s0
prop_final11 (Lookahead l) = not $ final $ trans'' $           treeDT l (iter (p 1 `Seq` p 2)) s0
prop_final12 (Lookahead l) = not $ final $ trans'' $ trans'' $ treeDT l (iter (p 1 `Seq` p 2)) s0
prop_final19 (Lookahead l) =       final $                     treeDT l (iter (p (-1) `Seq` p (-2))) s0
prop_final23 (Lookahead l) =       final $ trans'' $           treeDT l (p 0 `Seq` iter (p (-1) `Seq` p (-2))) s0
prop_final24 (Lookahead l) = (l /= 0 && l /= 2) == (final $ treeDT l (iter (p 1 `Seq` p (-2))) s0)

prop_final25 (Lookahead l) = not $ final $ treeDT l (p 1 `Seq` p 2) s0

prop_trans1 = let t = treeND (choice [p 1, p 3] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5]]) s0
              in (trans' t >>= trans' >>= (return . sit)) == Just (do_ 2 (do_ 1 s0))
prop_trans2 = let t = treeND (choice [p 1, p 3] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5]]) s0
              in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Just (do_ 3 (do_ 2 (do_ 1 s0)))
prop_trans3 = let t = treeND (choice [p 1, p 3] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5]] `Seq` p 2) s0
              in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Just (do_ 3 (do_ 2 (do_ 1 s0)))
prop_trans4 = let t = treeND (choice [p 1, p 3] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5]] `Seq` p 1) s0
              in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Just (do_ 3 (do_ 2 (do_ 1 s0)))

prop_dttrans1 = let t = treeDT 3 (choice [p 1, p 3, p 1] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5,4,3,2,1]]) s0
                in (trans' t >>= trans' >>= (return . sit)) == Just (do_ 4 (do_ 3 s0))
prop_dttrans2 = let t = treeDT 3 (choice [p 1, p 3, p 1] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5,4,3,2,1]]) s0
                in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Just (do_ 5 (do_ 4 (do_ 3 s0)))
prop_dttrans3 = let t = treeDT 3 (choice [p 1, p 3, p 1] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5,4,3,2,1]] `Seq` p 2) s0
                in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Just (do_ 5 (do_ 4 (do_ 3 s0)))
prop_dttrans4 = let t = treeDT 3 (choice [p 1, p 3, p 1] `Seq` choice [p i `Seq` p (i+1) | i <- [1,2,3,4,5,4,3,2,1]] `Seq` p 1) s0
                -- This is a special case: the last action, p 1, is not
                -- executable (because it's executed in an odd situation).
                -- The interpreter assigns the worst-case reward, and because
                -- there is no final point before p 1, it opts for some choice
                -- in the nondet that fails even earlier.
                in (trans' t >>= trans' >>= trans' >>= (return . sit)) == Nothing

prop_doo1 = map sit (dooBFS (treeND (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0)) ==
            map list2sit [[1,2,3], [1,4,5]]
prop_doo2 = sort (map sit (dooBFS (treeND (p 1 `Seq` ((p 10 `Seq` (atomic $ p 11 `Seq` p 12) `Seq` p 13) `Conc` (p 20 `Seq` p 21)) `Seq` p 100) s0))) ==
            sort (map list2sit [[1,10,11,12,13,20,21,100], [1,20,21,10,11,12,13,100]])
prop_doo3 = take 11 (map sit (dooBFS (treeND (p 0 `Seq` (iter (primf (\(Do i _) -> i+1)))) s0))) ==
            [list2sit [0..i] | i <- [0..10]]

prop_doo4 (Lookahead l) =
            map sit (dooBFS (treeDT l (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0)) ==
            map list2sit [[1,4,5]]

prop_sync1 = let t = treeNDIO (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
             in sit (fromJust (sync t)) == s0
prop_sync2 = let t = treeNDIO (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
             in sit (fromJust (trans' (fromJust (sync t)))) == do_ 1 s0
prop_sync3 = let t = treeNDIO (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
             in sit (fromJust (sync (fromJust (trans' t)))) == do_ 3 s0
prop_sync4 = let t = treeNDIO (p 1 `Seq` p 2 `Seq` p 3 `Seq` p 4 `Seq` p 5 `Seq`  Nil) s0
             in fmap sit (dooBFS' t >>= sync) == fmap sit (fromJust (dooIO (const Online) t))
prop_sync5 = let t = treeNDIO (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
             in fmap sit (dooBFS' t >>= sync) == fmap sit (fromJust (dooIO (const Online) t))

prop_dtsync1 = let t = treeDTIO 3 (choice [p 1, p 3, p 1] `Seq` choice [p i | i <- [1,2,3,4,5,4,3,2,1]] `Seq` choice [p i | i <- [1,2,3,4,5,4,3,2,1]]) s0
               -- This tests that nondeterminism in results of sync is resolved.
               -- If it isn't, the interpreter executes 3 in the second nondet.
               in (trans' t >>= sync >>= trans' >>= sync >>= trans' >>= sync >>= (return . sit)) == Just (do_ 7 (do_ 6 (do_ 5 s0)))
prop_dtsync2 = let t = treeDTIO 3 (p 1 `Seq` p 2 `Seq` p 3 `Seq` p 4 `Seq` p 5 `Seq`  Nil) s0
               in fmap sit (dooBFS' t >>= sync) == fmap sit (fromJust (dooIO (const Online) t))
prop_dtsync3 = let t = treeDTIO 3 (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
               in fmap sit (dooBFS' t >>= sync) == Just (do_ 7 (do_ 6 (do_ 3 s0)))
prop_dtsync4 = let t = treeDTIO 3 (p 1 `Seq` choice [p i `Seq` p (i+1) | i <- [1..5]]) s0
               in fmap sit (dooBFS' t >>= sync) == fmap sit (fromJust (dooIO (const Online) t))
prop_dtsync5 = let t = treeDTIO 3 (prim A `Seq` choice [prim C, prim D]) s0
               in fmap sit (fromJust (dooIO (const Online) t)) == Just (do_ D (do_ B s0))
prop_dtsync6 = let t = treeDTIO 3 (prim A `Seq` choice [prim C, prim D]) s0
               in fmap sit (dooBFS' t >>= sync) == Just (do_ C (do_ B s0))

--prop_NondetEmpty1 = map sit (dooBFS (treeND p s0)) == [do_ A s0]
--   where p = prim A `Seq` Nondet []
--
--prop_NondetEmpty2 = map sit (dooBFS (treeND p s0)) == [do_ B (do_ A s0)]
--   where p = prim A `Seq` Nondet [] `Seq` prim B


runTests :: IO Bool
runTests = $quickCheckAll


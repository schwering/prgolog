{-# LANGUAGE GADTs, TypeFamilies #-}

module Golog.Interpreter
  (BAT(..), DTBAT(..), Reward, Depth,
   Atom(..), PseudoAtom(..), Prog(..), Tree, Node, Conf,
   sit, treeND, treeDT, final, trans, doo) where

import Data.List (maximumBy)
import Data.Monoid
import Data.Ord (comparing)

type Reward = Double
type Depth = Int

class BAT a where
   data Sit a :: *
   s0         :: Sit a
   do_        :: a -> Sit a -> Sit a
   poss       :: a -> Sit a -> Bool

class BAT a => DTBAT a where
   reward     :: a -> Sit a -> Reward

class BAT a => IOBAT a where
   sync       :: a -> Sit a -> IO (Sit a)

data Atom a = Prim a | PrimF (Sit a -> a) | Test (Sit a -> Bool)

data PseudoAtom a = Atom (Atom a) | Complex (Prog a)

data Prog a = Seq (Prog a) (Prog a) | Nondet [Prog a] | Conc (Prog a) (Prog a)
            | PseudoAtom (PseudoAtom a) | Nil

data Tree a = Empty | Alt [Tree a] | Val a (Tree a)

instance Monoid (Tree a) where
   mempty                = Empty
   mappend Empty      t2 = t2
   mappend (Alt ts)   t2 = Alt (fmap (\t1 -> mappend t1 t2) ts)
   mappend (Val x t1) t2 = Val x (mappend t1 t2)

instance Functor Tree where
   fmap _ Empty     = Empty
   fmap f (Alt ts)  = Alt (map (fmap f) ts)
   fmap f (Val x t) = Val (f x) (fmap f t)

scan :: (b -> a -> Tree a -> b) -> b -> Tree a -> Tree b
scan f x0 t0 = Val x0 (scan' x0 t0)
   where scan' _ Empty     = Empty
         scan' x (Val y t) = let z = f x y t in Val z (scan' z t)
         scan' x (Alt ts)  = Alt (map (scan' x) ts)

best :: a -> (a -> a -> Ordering) -> (Tree a -> Bool) -> Depth -> Tree a -> a
best def _   _   _ Empty                 = def
best def cmp cut l (Alt ts)              = maximumBy cmp (map (best def cmp cut l) ts)
best def cmp cut l (Val x t) | l == 0    = x
                             | cut t     = maximumBy cmp [x, best def cmp cut (l-1) t]
                             | l > 0     = best def cmp cut (l-1) t
                             | otherwise = error "best: l < 0"

resolve :: ([Tree a] -> Tree a) -> Tree a -> Tree a
resolve _ Empty     = Empty
resolve _ (Alt [])  = Empty
resolve f (Alt ts)  = resolve f (f ts)
resolve f (Val x t) = Val x (resolve f t)

itl :: Tree a -> Tree a -> Tree a
itl Empty          t2             = t2
itl t1             Empty          = t1
itl (Alt ts)       t2             = Alt (map (\t1 -> itl t1 t2) ts)
itl t1             (Alt ts)       = Alt (map (\t2 -> itl t1 t2) ts)
itl t1@(Val x1 r1) t2@(Val x2 r2) = Alt [Val x1 (itl t2 r1), Val x2 (itl t1 r2)]

den :: Prog a -> Tree (Atom a)
den p' = rec (den' p')
   where rec :: Tree (PseudoAtom a) -> Tree (Atom a)
         rec Empty               = Empty
         rec (Alt ts)            = Alt (map rec ts)
         rec (Val (Atom a)    t) = Val a (rec t)
         rec (Val (Complex p) t) = mappend (den p) (rec t)
         den' :: Prog a -> Tree (PseudoAtom a)
         den' (Seq p1 p2)    = mappend (den' p1) (den' p2)
         den' (Nondet ps)    = Alt (map den' ps)
         den' (Conc p1 p2)   = itl (den' p1) (den' p2)
         den' (PseudoAtom a) = Val a Empty
         den' Nil            = Empty

data Node a b = Node (Sit a) b | Flop
type Conf a b = Tree (Node a b)
type ConfND a = Conf a ()
type ConfDT a = Conf a ((Reward, Depth))
--type ConfIO a b = Conf a (IO (

treeND :: BAT a => Prog a -> Sit a -> ConfND a
treeND p sz = scan (exec (\_ _ _ _ -> ())) (Node sz ()) (den p)

treeDT :: DTBAT a => Depth -> Prog a -> Sit a -> ConfDT a
treeDT l p sz = resolve (choiceDT l) (scan (exec f) (Node sz (0,0)) (den p))
   where f (r,d) a s _ = (r + reward a s, d + 1)

{-
treeIO :: IOBAT a => Prog a -> Sit a -> Conf a (NodeIO a)
treeIO p sz = cnf (den p) sz
   where cnf t s = scan (exec f) (Node s (PayloadIO (return (cnf t s)))) t
         f (PayloadIO s') a s t = PayloadIO (do s'' <- s'; s''' <- sync a s''; return (cnf t s'''))
-}

exec :: BAT a => (b -> a -> Sit a -> Tree (Atom a) -> b) ->
                 Node a b -> Atom a -> Tree (Atom a) -> Node a b
exec f (Node s pl)  (Prim a)  t | poss a s = Node (do_ a s) (f pl a s t)
exec f c@(Node s _) (PrimF a) t            = exec f c (Prim (a s)) t
exec _ c@(Node s _) (Test f)  _ | f s      = c
exec _ _            _         _            = Flop

choiceDT :: DTBAT a => Depth -> [ConfDT a] -> ConfDT a
choiceDT l = maximumBy (comparing value)
   where value :: DTBAT a => ConfDT a -> (Reward, Depth)
         value = val . best def cmp final l
            where def             = Node s0 (-1/0, minBound)
                  val (Node _ rd) = rd
                  val Flop        = (-1/0, minBound)
                  cmp x y         = compare (val x) (val y)

final :: Conf a b -> Bool
final Empty     = True
final (Alt [])  = True
final (Alt ts)  = any final ts
final (Val _ _) = False

trans :: Conf a b -> [Conf a b]
trans Empty              = error "trans: invalid conf"
trans (Alt _)            = error "trans: invalid conf"
trans (Val Flop       _) = []
trans (Val (Node _ _) t) = trans' t
   where trans' Empty                 = []
         trans' (Val Flop       _)    = []
         trans' t'@(Val (Node _ _) _) = [t']
         trans' (Alt ts)              = concat (map trans ts)

sit :: Conf a b -> Sit a
sit (Val (Node s _) _) = s
sit _                  = error "sit: invalid conf"

doo :: Conf a b -> [[Conf a b]]
doo c = let cs = trans c in cs : concat (map doo cs)


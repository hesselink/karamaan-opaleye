module Karamaan.Opaleye.QueryArr where

import Prelude hiding ((.), id)
import Database.HaskellDB.PrimQuery (PrimQuery(Empty, Restrict, Project),
                                     PrimExpr(AttrExpr, BinExpr),
                                     BinOp(OpEq), times)
import Karamaan.Opaleye.Wire (Wire, unwire)
import Control.Arrow (Arrow, arr, first, (&&&), (***))
import Control.Category (Category, id, (.), (<<<))
import Control.Applicative (Applicative, pure, (<*>))
import Karamaan.Opaleye.Colspec (runWriter)
import Karamaan.Opaleye.Unpackspec (Unpackspec(Unpackspec))
import Data.Function (on)
import Data.Profunctor (Profunctor, dimap)
import Data.Profunctor.Product (ProductProfunctor, empty, (***!))

-- This is probably too general
-- We want something more like
--   data QueryArr a b = QueryArr ((a, Tag) -> (b, PrimQuery, Tag))
-- but can't get it easily with the AST that HaskellDB gives us, because
-- restrict has to modify the PrimQuery, rather than just doing a product,
-- I think.
data QueryArr a b = QueryArr ((a, PrimQuery, Tag) -> (b, PrimQuery, Tag))

type Query b = QueryArr () b

data Tag = UnsafeTag Int

unsafeUnTag :: Tag -> Int
unsafeUnTag (UnsafeTag i) = i

start :: Tag
start = UnsafeTag 1

next :: Tag -> Tag
next = UnsafeTag . (+1) . unsafeUnTag

appendShow :: Show a => a -> String -> String
appendShow = flip (++) . show

tagWith :: Tag -> (String -> String)
tagWith = appendShow . unsafeUnTag

runQueryArr :: QueryArr a b -> (a, PrimQuery, Tag) -> (b, PrimQuery, Tag)
runQueryArr (QueryArr f) = f

runSimpleQueryArr :: QueryArr a b -> (a, Tag) -> (b, PrimQuery, Tag)
runSimpleQueryArr f (a, t) = runQueryArr f (a, Empty, t)

runQueryArrPrim' :: Unpackspec b -> Query b -> PrimQuery
runQueryArrPrim' (Unpackspec g) f
  =  Project (map (id &&& AttrExpr) cols) primQuery
  where (a, primQuery, _) = runQueryArr f ((), Empty, start)
        cols = runWriter g a

first3 :: (a1 -> b) -> (a1, a2, a3) -> (b, a2, a3)
first3 f (a1, a2, a3) = (f a1, a2, a3)

instance Category QueryArr where
  id = QueryArr id
  QueryArr f . QueryArr g = QueryArr (f . g)

instance Arrow QueryArr where
  arr f   = QueryArr (first3 f)
  first f = QueryArr g
    where g ((b, d), primQ, t0) = ((c, d), primQ', t1)
            where (c, primQ', t1) = runQueryArr f (b, primQ, t0)

instance Functor (QueryArr a) where
  fmap f = (arr f <<<)

instance Applicative (QueryArr a) where
  pure = arr . const
  f <*> g = arr (uncurry ($)) <<< (f &&& g)

instance Profunctor QueryArr where
  dimap f g a = arr g <<< a <<< arr f

instance ProductProfunctor QueryArr where
  empty = id
  (***!) = (***)

simpleQueryArr :: ((a, Tag) -> (b, PrimQuery, Tag)) -> QueryArr a b
simpleQueryArr f = QueryArr g
  where g (a0, primQuery, t0) = (a1, times primQuery primQuery', t1)
          where (a1, primQuery', t1) = f (a0, t0)

-- Is it possible to implement ArrowChoice for QueryArr?
-- The reason I think it might be is that the shape seems
-- statically determined.

-- The return value of predicate should be a PrimExpr representing
-- a boolean expression, but it seems that there is no way to acheieve
-- such type-safety in Haskell DB
restrictWith :: (a -> PrimExpr) -> QueryArr a ()
restrictWith predicate = QueryArr f where
  f (ws, primQ, t0) = ((), Restrict (predicate ws) primQ, t0)

-- FIXME: can I get rid of this
{-# DEPRECATED equals "Use 'Predicates.restrict <<< Operators2.eq' instead" #-}
equals :: QueryArr (Wire a, Wire a) ()
equals = restrictWith (uncurry equalsWire)

{-# DEPRECATED equalsWire "Do not use equalsWire" #-}
equalsWire :: Wire a -> Wire a -> PrimExpr
equalsWire = BinExpr OpEq `on` (AttrExpr . unwire)

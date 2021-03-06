--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

{-# LANGUAGE ExistentialQuantification #-}

module Copilot.Compile.C99.MetaTable
  ( StreamInfo (..)
  , ExternInfo (..)
  , ExternArrayInfo (..)
  , ExternFunInfo (..)
  , StreamInfoMap
  , ExternInfoMap
  , ExternFunInfoMap
  , MetaTable (..)
  , allocMetaTable
  ) where

import Control.Monad (liftM)
import qualified Copilot.Compile.C99.Queue as Q
import qualified Copilot.Compile.C99.Witness as W
import qualified Copilot.Core as C
import Copilot.Core.Error (impossible)

import Copilot.Core.External
import Data.Map (Map)
import qualified Data.Map as M
import Language.Atom (Atom)
import qualified Language.Atom as A
import Prelude hiding (id)

--------------------------------------------------------------------------------

data StreamInfo = forall a . StreamInfo
  { streamInfoQueue   :: Q.Queue a
  , streamInfoTempVar :: A.V a
  , streamInfoType    :: C.Type a }

type StreamInfoMap = Map C.Id StreamInfo

--------------------------------------------------------------------------------

data ExternInfo = forall a . ExternInfo
  { externInfoVar     :: A.V a
  , externInfoType    :: C.Type a }

type ExternInfoMap = Map C.Name ExternInfo

--------------------------------------------------------------------------------

data ExternArrayInfo = forall a b . Integral a => ExternArrayInfo
  { externArrayInfoVar      :: A.V b
  , externArrayInfoIdxExpr  :: C.Expr a
  , externArrayInfoIdxType  :: C.Type a
  , externArrayInfoElemType :: C.Type b }

type ExternArrayInfoMap = Map (C.Name, C.Tag) ExternArrayInfo

--------------------------------------------------------------------------------

data ExternFunInfo = forall a . ExternFunInfo
  { externFunInfoArgs  :: [C.UExpr]
  , externFunInfoVar   :: A.V a
  , externFunInfoType  :: C.Type a }

type ExternFunInfoMap = Map (C.Name, C.Tag) ExternFunInfo

--------------------------------------------------------------------------------

data MetaTable = MetaTable
  { streamInfoMap      :: StreamInfoMap
  , externInfoMap      :: ExternInfoMap
  , externArrayInfoMap :: ExternArrayInfoMap
  , externFunInfoMap   :: ExternFunInfoMap }

--------------------------------------------------------------------------------

allocMetaTable :: C.Spec -> A.Atom MetaTable
allocMetaTable spec =
  do
    streamInfoMap_ <-
      liftM M.fromList $ mapM allocStream (C.specStreams spec)

    externInfoMap_ <-
      liftM M.fromList $ mapM allocExternVar (externVars spec)

    externArrayInfoMap_ <-
      liftM M.fromList $ mapM allocExternArray (externArrays spec)

    externFunInfoMap_ <-
      liftM M.fromList $ mapM allocExternFun (externFuns spec)

    return $
      MetaTable
        streamInfoMap_
        externInfoMap_
        externArrayInfoMap_
        externFunInfoMap_

--------------------------------------------------------------------------------

allocStream :: C.Stream -> Atom (C.Id, StreamInfo)
allocStream
  C.Stream
    { C.streamId       = id
    , C.streamBuffer   = buf
    , C.streamExprType = t
    } =
  do
    W.ExprInst <- return (W.exprInst t)
    que <- Q.queue (mkQueueName   id) buf
    tmp <- A.var   (mkTempVarName id) (C.uninitialized t)
    let
      strmInfo =
        StreamInfo
          { streamInfoQueue       = que
          , streamInfoTempVar     = tmp
          , streamInfoType        = t }
    return (id, strmInfo)

--------------------------------------------------------------------------------

allocExternVar :: ExtVar -> Atom (C.Name, ExternInfo)
allocExternVar (ExtVar name ut) =
  case ut of
    C.UType t ->
      do
        W.ExprInst <- return (W.exprInst t)
        v <- A.var (mkExternName name) (C.uninitialized t)
        return (name, ExternInfo v t)

--------------------------------------------------------------------------------

allocExternArray :: ExtArray -> Atom ((C.Name, C.Tag), ExternArrayInfo)
allocExternArray (ExtArray name elemType idxExpr idxType _ maybeTag) = do
    let tag = case maybeTag of
                Nothing  -> impossible "allocExternArray" "copilot-c99"
                Just tg  -> tg
    W.ExprInst <- return (W.exprInst elemType)
    v <- A.var (mkExternArrayName name tag) (C.uninitialized elemType)
    return ((name, tag), ExternArrayInfo v idxExpr idxType elemType)

--------------------------------------------------------------------------------

allocExternFun :: ExtFun -> Atom ((C.Name, C.Tag), ExternFunInfo)
allocExternFun (ExtFun name t args maybeTag) = do
    let tag = case maybeTag of
                Nothing  -> impossible "allocExternFun" "copilot-c99"
                Just tg  -> tg
    W.ExprInst <- return (W.exprInst t)
    v <- A.var (mkExternFunName name tag) (C.uninitialized t)
    return ((name, tag), ExternFunInfo args v t)
  
--------------------------------------------------------------------------------

mkExternName :: C.Name -> A.Name
mkExternName name = "ext_" ++ name

mkExternArrayName :: C.Name -> C.Tag -> A.Name
mkExternArrayName name tag = "ext_array_" ++ show tag ++ "_" ++ name

mkExternFunName :: C.Name -> C.Tag -> A.Name
mkExternFunName name tag = "ext_fun_" ++ show tag ++ "_" ++ name

mkQueueName :: C.Id -> A.Name
mkQueueName id = "str" ++ show id

mkTempVarName :: C.Id -> A.Name
mkTempVarName id = "tmp" ++ show id

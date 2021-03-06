module Sxhc.Plugin (plugin) where
import GhcPlugins
import CoreToStg
import CorePrep
import StgSyn
import Data.Foldable
import Data.Traversable
import Outputable

plugin :: Plugin
plugin = defaultPlugin {
  installCoreToDos = install
}

-- ifPprDebug
foofoo :: SDoc -> SDoc
foofoo = id -- Outputable.ifPprDebug


printStgExpr :: StgExpr -> SDoc
printStgExpr (StgLit lit)     = ppr lit

-- general case
printStgExpr (StgApp func args)
  = hang (ppr func) 4 (sep (map (ppr) args))

printStgExpr (StgConApp con args _)
  = hsep [ ppr con, brackets (interppSP args) ]

printStgExpr (StgOpApp op args _)
  = hsep [ printStgOp op, brackets (interppSP args)]

printStgExpr (StgLam bndrs body)
  = sep [ char '\\' <+> ppr_list (map (pprBndr LambdaBind) bndrs)
            <+> text "->",
         printStgExpr body ]
  where ppr_list = brackets . fsep . punctuate comma


printStgExpr (StgLet bind expr@(StgLet _ _))
  = ($$)
      (sep [hang (text "let {")
                2 (hsep [printStgBinding bind, text "} in"])])
      (ppr expr)

-- general case
printStgExpr (StgLet bind expr)
  = sep [hang (text "let {") 2 (printStgBinding bind),
           hang (text "} in ") 2 (ppr expr)]

printStgExpr (StgLetNoEscape bind expr)
  = sep [hang (text "let-no-escape {")
                2 (printStgBinding bind),
           hang (text "} in ")
                2 (ppr expr)]

printStgExpr (StgTick tickish expr)
  = sdocWithDynFlags $ \dflags ->
    if gopt Opt_SuppressTicks dflags
    then printStgExpr expr
    else sep [ ppr tickish, printStgExpr expr ]


printStgExpr (StgCase expr bndr alt_type alts)
  = sep [sep [text "case",
          nest 4 (hsep [printStgExpr expr,
            (foofoo (dcolon <+> ppr alt_type))]),
          text "of", pprBndr CaseBind bndr, char '{'],
          nest 2 (vcat (map printStgAlt alts)),
          char '}']
printStgExpr _ = text "expr"

printStgAlt :: (OutputableBndr bndr, Outputable occ, Ord occ)
          => GenStgAlt bndr occ -> SDoc
printStgAlt (con, params, expr)
  = hang (hsep [ppr con, sep (map (pprBndr CasePatBind) params), text "->"])
         4 (ppr expr Outputable.<> semi)

printStgOp :: StgOp -> SDoc
printStgOp (StgPrimOp  op)   = ppr op
printStgOp (StgPrimCallOp op)= ppr op
printStgOp (StgFCallOp op _) = ppr op



-- Not yet done.
printStgRhs :: StgRhs -> SDoc
printStgRhs (StgRhsClosure ccs binderInfo occs updatable bndrs expr) =  printStgExpr expr 
printStgRhs (StgRhsCon ccs dataConstructor args) = hcat [ppr dataConstructor, brackets (interppSP args)]

printStgRhs rhs = text "rhs"

printGenStgBinding :: (OutputableBndr bndr, Outputable bdee, Ord bdee)
                 => GenStgBinding bndr bdee -> SDoc

printGenStgBinding (StgNonRec bndr rhs)
  = hang (hsep [pprBndr LetBind bndr, equals])
        4 (ppr rhs Outputable.<> semi)

printGenStgBinding (StgRec pairs)
  = vcat $ foofoo (text "{- StgRec (begin) -}") :
           map (ppr_bind) pairs ++ [foofoo (text "{- StgRec (end) -}")]
  where
    ppr_bind (bndr, expr)
      = hang (hsep [pprBndr LetBind bndr, equals])
             4 (ppr expr Outputable.<> semi)


printStgBinding :: StgBinding -> SDoc
printStgBinding  = printGenStgBinding

printStgTopBinding :: StgTopBinding -> SDoc
printStgTopBinding (StgTopStringLit bndr str)
  = hang (hsep [pprBndr LetBind bndr, equals])
          4 (pprHsBytes str Outputable.<> semi)
printStgTopBinding (StgTopLifted top) = printStgBinding top


printStgProgram :: DynFlags -> [StgTopBinding] -> CoreM ()
printStgProgram flags binds = forM_ binds (putMsgS . showSDoc flags . printStgTopBinding) 

-- bindsOnlyPass :: (CoreProgram -> CoreM CoreProgram) -> ModGuts -> CoreM ModGuts
-- coreToStg :: coreToStg :: DynFlags -> Module -> CoreProgram -> [StgTopBinding] 
pass :: ModGuts -> CoreM ModGuts
pass guts = do
  flags <- getDynFlags
  mod <- getModule
  env <- getHscEnv

  let coreProgram = mg_binds guts
  let tycons = mg_tcs guts
  let modloc = ModLocation {
    ml_hs_file  = Nothing,
    ml_hi_file  = "Example.hi",
     ml_obj_file = "Example.o"
   }
  preppedProgram <- liftIO $ corePrepPgm env mod modloc coreProgram  tycons

  let stgProgram = coreToStg flags mod preppedProgram
  printStgProgram flags stgProgram

  putMsgS "Hello!Hello!"
  return guts

coreToDoFromPass :: CoreToDo
coreToDoFromPass = CoreDoPluginPass "DumpSxhcStg" pass


install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install _ todo = do
  return $ todo ++ [coreToDoFromPass]

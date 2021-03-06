{-# LANGUAGE RecordWildCards #-}

module Main where

import           Data.Text.Conversions      (convertText)

import           Hasura.App
import           Hasura.Logging             (Hasura)
import           Hasura.Prelude
import           Hasura.RQL.DDL.Metadata    (fetchMetadata)
import           Hasura.RQL.DDL.Schema
import           Hasura.RQL.Types
import           Hasura.Server.Init
import           Hasura.Server.Migrate      (dropCatalog)
import           Hasura.Server.Version

import qualified Data.ByteString.Lazy       as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Database.PG.Query          as Q

main :: IO ()
main = parseArgs >>= unAppM . runApp

runApp :: HGEOptions Hasura -> AppM ()
runApp (HGEOptionsG rci hgeCmd) =
  withVersion $$(getVersionFromEnvironment) case hgeCmd of
    HCServe serveOptions -> do
      (initCtx, initTime) <- initialiseCtx hgeCmd rci
      runHGEServer serveOptions initCtx initTime
    HCExport -> do
      (initCtx, _) <- initialiseCtx hgeCmd rci
      res <- runTx' initCtx fetchMetadata
      either printErrJExit printJSON res

    HCClean -> do
      (initCtx, _) <- initialiseCtx hgeCmd rci
      res <- runTx' initCtx dropCatalog
      either printErrJExit (const cleanSuccess) res

    HCExecute -> do
      (InitCtx{..}, _) <- initialiseCtx hgeCmd rci
      queryBs <- liftIO BL.getContents
      let sqlGenCtx = SQLGenCtx False
      res <- runAsAdmin _icPgPool sqlGenCtx _icHttpManager do
        schemaCache <- buildRebuildableSchemaCache
        execQuery queryBs
          & runHasSystemDefinedT (SystemDefined False)
          & runCacheRWT schemaCache
          & fmap fst
      either printErrJExit (liftIO . BLC.putStrLn) res

    HCVersion -> liftIO $ putStrLn $ "Hasura GraphQL Engine: " ++ convertText currentVersion
  where
    runTx' initCtx tx =
      liftIO $ runExceptT $ Q.runTx (_icPgPool initCtx) (Q.Serializable, Nothing) tx

    cleanSuccess = liftIO $ putStrLn "successfully cleaned graphql-engine related data"

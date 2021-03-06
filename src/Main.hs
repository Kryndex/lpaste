{-# OPTIONS -Wall #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Main entry point.

module Main (main) where

import qualified Data.ByteString.Char8 as S8
import           Data.List
import           Hpaste.Config
import           Hpaste.Controller.Activity as Activity
import           Hpaste.Controller.Browse as Browse
import           Hpaste.Controller.Diff as Diff
import           Hpaste.Controller.Home as Home
import           Hpaste.Controller.New as New
import           Hpaste.Controller.Paste as Paste
import           Hpaste.Controller.Raw as Raw
import           Hpaste.Controller.Report as Report
import           Hpaste.Controller.Reported as Reported
import           Hpaste.Controller.Rss as Rss
import           Hpaste.Controller.Script as Script
import           Hpaste.Model.Announcer (newAnnouncer)
import           Hpaste.Model.Spam (generateSpamDB,analyzeSuspicious)
import           Hpaste.Types
import           Hpaste.Types.Announcer
import           Snap.App
import           Snap.Http.Server hiding (Config)
import           Snap.Util.FileServe
import           Spam
import           System.Environment
import           Text.Printf

-- | Main entry point.
main :: IO ()
main = do
  args <- getArgs
  case args of
    [cpath, "spam", "analyze"] -> do
      config <- getConfig cpath
      pool <- newPool (configPostgres config)
      setUnicodeLocale "en_US"
      db <- readDB "spam.db"
      runDB () () pool (analyzeSuspicious db)
    [cpath, "spam", "generate"] -> do
      config <- getConfig cpath
      pool <- newPool (configPostgres config)
      setUnicodeLocale "en_US"
      runDB () () pool generateSpamDB
    [_, "spam", "summary"] -> do
      setUnicodeLocale "en_US"
      db <- readDB "spam.db"
      summarizeDB db
    [_, "spam", "classify"] -> do
      setUnicodeLocale "en_US"
      db <- readDB "spam.db"
      input <- getContents
      let tokens = significantTokens db (nub (listTokens 112 (S8.pack input)))
      print tokens
      printf "%f\n" (classify db tokens)
    (cpath:_) -> do
      config <- getConfig cpath
      announces <- newAnnouncer (configAnnounce config)
      pool <- newPool (configPostgres config)
      setUnicodeLocale "en_US"
      spamDB <-  (readDB "spam.db")
      httpServe server (serve spamDB config pool announces)
    _ -> error "args: /path/to/config.ini [spam generate]"
  where
    server = setPort 10000 defaultConfig

-- | Serve the controllers.
serve :: SpamDB -> Config -> Pool -> Announcer -> Snap ()
serve spamDB config pool ans = route routes where
  routes = [("/css/",serveDirectory "static/css")
           ,("/js/amelie.hs.js",run Script.handle)
           ,("/js/",serveDirectory "static/js")
           ,("/hs/",serveDirectory "static/hs")
           ,("",run (Home.handle False))
           ,("/spam",run (Home.handle True))
           ,("/:id",run (Paste.handle False))
           ,("/raw/:id",run Raw.handle)
           ,("/revision/:id",run (Paste.handle True))
           ,("/report/:id",run Report.handle)
           ,("/reported",run Reported.handle)
           ,("/new",run (New.handle spamDB New.NewPaste))
           ,("/annotate/:id",run (New.handle spamDB New.AnnotatePaste))
           ,("/edit/:id",run (New.handle spamDB New.EditPaste))
           ,("/new/:channel",run (New.handle spamDB New.NewPaste))
           ,("/browse",run Browse.handle)
           ,("/activity",run Activity.handle)
           ,("/diff/:this/:that",run Diff.handle)
           ,("/delete",run Report.handleDelete)
           ,("/disregard",run Report.handleDisregard)
           ,("/mark-spam",run Report.handleReportSpam)
           ,("/channel/:channel/rss",run Rss.handle)
           ]
  run = runHandler ans config pool

{- SPDX-FileCopyrightText: 2018-2019 Serokell <https://serokell.io>
 -
 - SPDX-License-Identifier: MPL-2.0
 -}

-- | Generalised repo scanner and analyser.

module Xrefcheck.Scan
  ( TraversalConfig (..)
  , Extension
  , ScanAction
  , FormatsSupport
  , RepoInfo (..)

  , gatherRepoInfo
  , specificFormatsSupport
  ) where

import Universum

import Data.Aeson.TH (deriveFromJSON)
import Data.Foldable qualified as F
import Data.Map qualified as M
import GHC.Err (errorWithoutStackTrace)
import System.Directory.Tree qualified as Tree
import System.FilePath (dropTrailingPathSeparator, takeDirectory, takeExtension, (</>))

import Xrefcheck.Core
import Xrefcheck.Progress
import Xrefcheck.Util (aesonConfigOption)

-- | Config of repositry traversal.
data TraversalConfig = TraversalConfig
  { tcIgnored   :: [FilePath]
    -- ^ Files and folders, files in which we completely ignore.
  }

deriveFromJSON aesonConfigOption ''TraversalConfig

-- | File extension, dot included.
type Extension = String

-- | Way to parse a file.
type ScanAction = FilePath -> IO FileInfo

-- | All supported ways to parse a file.
type FormatsSupport = Extension -> Maybe ScanAction

specificFormatsSupport :: [([Extension], ScanAction)] -> FormatsSupport
specificFormatsSupport formats = \ext -> M.lookup ext formatsMap
  where
    formatsMap = M.fromList
        [ (extension, parser)
        | (extensions, parser) <- formats
        , extension <- extensions
        ]

-- | Returns the context location of the given path.
-- This is done by removing the last component from the path.
--
-- > locationOf "./folder/file.md"  == "./folder"
-- > locationOf "./folder/subfolder"  == "./folder"
-- > locationOf "./folder/subfolder/"  == "./folder"
-- > locationOf "./folder/subfolder/./"  == "./folder/subfolder"
-- > locationOf "."  == ""
-- > locationOf "/absolute/path"  == "/absolute"
-- > locationOf "/"  == "/"
locationOf :: FilePath -> FilePath
locationOf fp
  | fp == "" || fp == "." = ""
  | otherwise = takeDirectory $ dropTrailingPathSeparator fp

gatherRepoInfo
  :: MonadIO m
  => Rewrite -> FormatsSupport -> TraversalConfig -> FilePath -> m RepoInfo
gatherRepoInfo rw formatsSupport config root = do
  putTextRewrite rw "Scanning repository..."
  _ Tree.:/ repoTree <- liftIO $ Tree.readDirectoryWithL processFile rootNE
  let fileInfos = filter (\(path, _) -> not $ isIgnored path)
        $ dropSndMaybes . F.toList
        $ Tree.zipPaths . (locationOf root Tree.:/)
        $ filterExcludedDirs root repoTree
  return $ RepoInfo (M.fromList fileInfos)
  where
    rootNE = if null root then "." else root
    processFile file = do
      let ext = takeExtension file
      let mscanner = formatsSupport ext
      forM mscanner $ \scanFile -> scanFile file
    dropSndMaybes l = [(a, b) | (a, Just b) <- l]

    ignored = map (root </>) (tcIgnored config)
    isIgnored path = path `elem` ignored
    filterExcludedDirs cur = \case
      Tree.Dir name subfiles ->
        let subfiles' =
              if isIgnored cur
              then []
              else map visitRec subfiles
            visitRec sub = filterExcludedDirs (cur </> Tree.name sub) sub
        in Tree.Dir name subfiles'
      file@Tree.File{} -> file
      Tree.Failed _name err ->
        errorWithoutStackTrace $ "Repository traversal failed: " <> show err

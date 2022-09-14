{- SPDX-FileCopyrightText: 2019 Serokell <https://serokell.io>
 -
 - SPDX-License-Identifier: MPL-2.0
 -}

module Test.Xrefcheck.AnchorsInHeadersSpec where

import Universum

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Test.Xrefcheck.Util
import Xrefcheck.Core

test_anchorsInHeaders :: TestTree
test_anchorsInHeaders = testGroup "Anchors in headers"
  [ testCase "Check if anchors in headers are recognized" $ do
      fi <- getFI  GitHub "tests/markdowns/without-annotations/anchors_in_headers.md"
      getAnchors fi @?= ["some-stuff", "stuff-section"]
  , testCase "Check if anchors with id attributes are recognized" $ do
      fi <- getFI GitHub "tests/markdowns/without-annotations/anchors_in_headers_with_id_attribute.md"
      getAnchors fi @?= ["some-stuff-with-id-attribute", "stuff-section-with-id-attribute"]
  ]
  where
    getAnchors :: FileInfo -> [Text]
    getAnchors fi = map aName $ fi ^. fiAnchors

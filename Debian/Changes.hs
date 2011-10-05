-- |Changelog and changes file support.
module Debian.Changes
    ( ChangesFile(..)
    , ChangedFileSpec(..)
    , changesFileName
    , ChangeLogEntry(..)
    , parseLog
    , parseEntry
    , parseChanges
    , prettyChanges
    , prettyChangesFile
    , prettyEntry
    ) where

import Data.List (intercalate)
import qualified Debian.Control.String as S
import Debian.Release
import Debian.URI()
import Debian.Version
import System.Posix.Types
import Text.Regex.TDFA
import Text.PrettyPrint.HughesPJ

-- |A file generated by dpkg-buildpackage describing the result of a
-- package build
data ChangesFile =
    Changes { changeDir :: FilePath		-- ^ The full pathname of the directory holding the .changes file.
            , changePackage :: String		-- ^ The package name parsed from the .changes file name
            , changeVersion :: DebianVersion	-- ^ The version number parsed from the .changes file name
            , changeRelease :: ReleaseName	-- ^ The Distribution field of the .changes file
            , changeArch :: Arch		-- ^ The architecture parsed from the .changes file name
            , changeInfo :: S.Paragraph		-- ^ The contents of the .changes file
            , changeEntry :: ChangeLogEntry	-- ^ The value of the Changes field of the .changes file
            , changeFiles :: [ChangedFileSpec]	-- ^ The parsed value of the Files attribute
            } deriving (Eq)

-- |An entry in the list of files generated by the build.
data ChangedFileSpec =
    ChangedFileSpec { changedFileMD5sum :: String
                    , changedFileSHA1sum :: String
                    , changedFileSHA256sum :: String
                    , changedFileSize :: FileOffset
                    , changedFileSection :: SubSection
                    , changedFilePriority :: String
                    , changedFileName :: FilePath
                    } deriving (Eq, Show)

-- |A changelog is a series of ChangeLogEntries
data ChangeLogEntry =
    Entry { logPackage :: String
          , logVersion :: DebianVersion
          , logDists :: [ReleaseName]
          , logUrgency :: String
          , logComments :: String
          , logWho :: String
          , logDate :: String
          }
  | WhiteSpace String
  deriving (Eq)

{-
instance Show ChangesFile where
    show = changesFileName
-}

changesFileName :: ChangesFile -> String
changesFileName changes =
    changePackage changes ++ "_" ++ show (prettyDebianVersion (changeVersion changes)) ++ "_" ++ archName (changeArch changes) ++ ".changes"

prettyChangesFile :: ChangesFile -> Doc
prettyChangesFile = text . changesFileName

prettyChanges :: ChangedFileSpec -> Doc
prettyChanges file =
    text (changedFileMD5sum file ++ " " ++
          show (changedFileSize file) ++ " " ++
          sectionName (changedFileSection file) ++ " " ++
          changedFilePriority file ++ " " ++
          changedFileName file)

prettyEntry (Entry package version dists urgency details who date) =
    text (package ++ " (" ++ show (prettyDebianVersion version) ++ ") " ++ intercalate " " (map releaseName' dists) ++ "; urgency=" ++ urgency ++ "\n\n" ++
          details ++ " -- " ++ who ++ "  " ++ date ++ "\n\n")

-- |Show just the top line of a changelog entry (for debugging output.)
showHeader :: ChangeLogEntry -> Doc
showHeader (Entry package version dists urgency _ _ _) =
    text (package ++ " (" ++ show (prettyDebianVersion version) ++ ") " ++ intercalate " " (map releaseName' dists) ++ "; urgency=" ++ urgency ++ "...")

{-
format is a series of entries like this:

     package (version) distribution(s); urgency=urgency
    [optional blank line(s), stripped]
       * change details
         more change details
    [blank line(s), included in output of dpkg-parsechangelog]
       * even more change details
    [optional blank line(s), stripped]
      -- maintainer name <email address>[two spaces]  date

package and version are the source package name and version number.

distribution(s) lists the distributions where this version should be
installed when it is uploaded - it is copied to the Distribution field
in the .changes file. See Distribution, Section 5.6.14.

urgency is the value for the Urgency field in the .changes file for
the upload (see Urgency, Section 5.6.17). It is not possible to
specify an urgency containing commas; commas are used to separate
keyword=value settings in the dpkg changelog format (though there is
currently only one useful keyword, urgency).

The change details may in fact be any series of lines starting with at
least two spaces, but conventionally each change starts with an
asterisk and a separating space and continuation lines are indented so
as to bring them in line with the start of the text above. Blank lines
may be used here to separate groups of changes, if desired.

If this upload resolves bugs recorded in the Bug Tracking System
(BTS), they may be automatically closed on the inclusion of this
package into the Debian archive by including the string: closes:
Bug#nnnnn in the change details.[16] This information is conveyed via
the Closes field in the .changes file (see Closes, Section 5.6.22).

The maintainer name and email address used in the changelog should be
the details of the person uploading this version. They are not
necessarily those of the usual package maintainer. The information
here will be copied to the Changed-By field in the .changes file (see
Changed-By, Section 5.6.4), and then later used to send an
acknowledgement when the upload has been installed.

The date must be in RFC822 format[17]; it must include the time zone
specified numerically, with the time zone name or abbreviation
optionally present as a comment in parentheses.

The first "title" line with the package name must start at the left
hand margin. The "trailer" line with the maintainer and date details
must be preceded by exactly one space. The maintainer details and the
date must be separated by exactly two spaces.

The entire changelog must be encoded in UTF-8. 
-}

-- |Parse a Debian Changelog and return a lazy list of entries
parseLog :: String -> [Either [String] ChangeLogEntry]
parseLog "" = []
parseLog text =
    case parseEntry text of
      Left messages -> [Left messages]
      Right (entry, text') -> Right entry : parseLog text'

-- |Parse a single changelog entry, returning the entry and the remaining text.
{-
parseEntry :: String -> Failing (ChangeLogEntry, String)
parseEntry text =
    case span (\ x -> elem x " \t\n") text of
      ("", _) ->
          case matchRegexAll entryRE text of
            Nothing -> Failure ["Parse error in changelog:\n" ++ show text]
            Just ("", _, remaining, [_, name, version, dists, urgency, _, details, _, _, _, _, _, who, date, _]) ->
                Success (Entry name 
                               (parseDebianVersion version)
                               (map parseReleaseName . words $ dists)
                               urgency
			       details
                               who
                               date,
                         remaining)
            Just (before, _, remaining, submatches) ->
                Failure ["Internal error:\n  text=" ++ show text ++ "\n before=" ++ show before ++ "\n  remaining=" ++ show remaining ++ ", submatches=" ++ show submatches]
      (w, text') -> Success (WhiteSpace (trace ("whitespace: " ++ show w) w), text')
-}

parseEntry :: String -> Either [String] (ChangeLogEntry, String)
parseEntry text =
    case text =~ entryRE :: MatchResult String of
      x | mrSubList x == [] -> Left ["Parse error in " ++ show text]
      x@MR {mrAfter = after, mrSubList = [_, name, version, dists, urgency, _, details, _, _, who, _, date, _]} ->
          Right (Entry name 
                         (parseDebianVersion version)
                         (map parseReleaseName . words $ dists)
                         urgency
			 details
                         (take (length who - 2) who)
                         date,
                   after)
      x@MR {mrBefore = before, mrMatch = matched, mrAfter = after, mrSubList = matches} ->
          Left ["Internal error\n after=" ++ show after ++ "\n " ++ show (length matches) ++ " matches: " ++ show matches]
{-
parseREs :: [Regex] -> String -> Failing ([String], String)
parseREs res text =
    foldr f (Success ([], text)) entryREs
    where
      f _ (Failure msgs) = Failure msgs
      f re (Success (oldMatches, text)) =
          case matchRegexAll re text of
            Nothing -> Failure ["Parse error at " ++ show text]
            Just (before, matched, after, newMatches) ->
                Success (oldMatches ++ trace ("newMatches=" ++ show newMatches) newMatches, after)
-}

entryRE = bol ++ blankLines ++ headerRE ++ changeDetails ++ signature ++ blankLines
changeDetails = "((\n| \n| -\n|([^ ]| [^--]| -[^--])[^\n]*\n)*)"
signature = " -- ([ ]*([^ ]+ )* )([^\n]*)\n"

{-
entryRE = mkRegexWithOpts (bol ++ blankLines ++ headerRE ++ nonSigLines ++ blankLines ++ signature ++ blankLines) False True
nonSigLines = "(((  .*|\t.*| \t.*)|([ \t]*)\n)+)"
-- In the debian repository, sometimes the extra space in front of the
-- day-of-month is missing, sometimes an extra one is added.
signature = "( -- ([^\n]*)  (..., ? ?.. ... .... ........ .....))[ \t]*\n"
-}

-- |Parse the changelog information that shows up in the .changes
-- file, i.e. a changelog entry with no signature.
parseChanges :: String -> Maybe ChangeLogEntry
parseChanges text =
    case text =~ changesRE :: MatchResult String of
      MR {mrSubList = []} -> Nothing
      MR {mrSubList = [_, name, version, dists, urgency, _, details]} ->
          Just $ Entry name 
                       (parseDebianVersion version)
                       (map parseReleaseName . words $ dists)
                       urgency
		       details
                       "" ""
      MR {mrSubList = x} -> error $ "Unexpected match: " ++ show x
    where
      changesRE = bol ++ blankLines ++ optWhite ++ headerRE ++ "(.*)$"

headerRE =
    package ++ version ++ dists ++ urgency
    where
      package = "([^ \t(]*)" ++ optWhite
      version = "\\(([^)]*)\\)" ++ optWhite
      dists = "([^;]*);" ++ optWhite
      urgency = "urgency=([^\n]*)\n" ++ blankLines

blankLines = blankLine ++ "*"
blankLine = "(" ++ optWhite ++ "\n)"
optWhite = "[ \t]*"
bol = "^"

s1 = intercalate "\n" 
     ["haskell-regex-compat (0.92-3+seereason1~jaunty4) jaunty-seereason; urgency=low",
      "",
      "  [ Joachim Breitner ]",
      "  * Adjust priority according to override file",
      "  * Depend on hscolour (Closes: #550769)",
      "",
      "  [ Marco Túlio Gontijo e Silva ]",
      "  * debian/control: Use more sintetic name for Vcs-Darcs.",
      "  * Built from sid apt pool",
      "  * Build dependency changes:",
      "     cpphs:                    1.9-1+seereason1~jaunty5     -> 1.9-1+seereason1~jaunty6",
      "     ghc6:                     6.10.4-1+seereason5~jaunty1  -> 6.12.1-0+seereason1~jaunty1",
      "     ghc6-doc:                 6.10.4-1+seereason5~jaunty1  -> 6.12.1-0+seereason1~jaunty1",
      "     ghc6-prof:                6.10.4-1+seereason5~jaunty1  -> 6.12.1-0+seereason1~jaunty1",
      "     haddock:                  2.4.2-3+seereason3~jaunty1   -> 6.12.1-0+seereason1~jaunty1",
      "     haskell-devscripts:       0.6.18-21+seereason1~jaunty1 -> 0.6.18-23+seereason1~jaunty1",
      "     haskell-regex-base-doc:   0.93.1-5+seereason1~jaunty1  -> 0.93.1-5++1+seereason1~jaunty1",
      "     haskell-regex-posix-doc:  0.93.2-4+seereason1~jaunty1  -> 0.93.2-4+seereason1~jaunty2",
      "     libghc6-regex-base-dev:   0.93.1-5+seereason1~jaunty1  -> 0.93.1-5++1+seereason1~jaunty1",
      "     libghc6-regex-base-prof:  0.93.1-5+seereason1~jaunty1  -> 0.93.1-5++1+seereason1~jaunty1",
      "     libghc6-regex-posix-dev:  0.93.2-4+seereason1~jaunty1  -> 0.93.2-4+seereason1~jaunty2",
      "     libghc6-regex-posix-prof: 0.93.2-4+seereason1~jaunty1  -> 0.93.2-4+seereason1~jaunty2",
      "",
      " -- SeeReason Autobuilder <autobuilder@seereason.org>  Fri, 25 Dec 2009 01:55:37 -0800",
      "",
      "haskell-regex-compat (0.92-3) unstable; urgency=low",
      "",
      "  [ Joachim Breitner ]",
      "  * Adjust priority according to override file",
      "  * Depend on hscolour (Closes: #550769)",
      "",
      "  [ Marco Túlio Gontijo e Silva ]",
      "  * debian/control: Use more sintetic name for Vcs-Darcs.",
      "",
      " -- Joachim Breitner <nomeata@debian.org>  Mon, 20 Jul 2009 13:05:35 +0200",
      "",
      "haskell-regex-compat (0.92-2) unstable; urgency=low",
      "",
      "  * Adopt package for the Debian Haskell Group",
      "  * Fix \"FTBFS with new dpkg-dev\" by adding comma to debian/control",
      "    (Closes: #536473)",
      "",
      " -- Joachim Breitner <nomeata@debian.org>  Mon, 20 Jul 2009 12:05:40 +0200",
      "",
      "haskell-regex-compat (0.92-1.1) unstable; urgency=low",
      "",
      "  * Rebuild for GHC 6.10.",
      "  * NMU with permission of the author.",
      "",
      " -- John Goerzen <jgoerzen@complete.org>  Mon, 16 Mar 2009 10:12:04 -0500",
      "",
      "haskell-regex-compat (0.92-1) unstable; urgency=low",
      "",
      "  * New upstream release",
      "  * debian/control:",
      "    - Bump Standards-Version. No changes needed.",
      "",
      " -- Arjan Oosting <arjan@debian.org>  Sun, 18 Jan 2009 00:05:02 +0100",
      "",
      "haskell-regex-compat (0.91-1) unstable; urgency=low",
      "",
      "  * Take over package from Ian, as I already maintain haskell-regex-base,",
      "    and move Ian to the Uploaders field.",
      "  * Packaging complete redone (based on my haskell-regex-base package).",
      "",
      " -- Arjan Oosting <arjan@debian.org>  Sat, 19 Jan 2008 16:48:39 +0100",
      "",
      "haskell-regex-compat (0.71.0.1-1) unstable; urgency=low",
      " ",
      "  * Initial release (used to be part of ghc6).",
      "  * Using \"Generic Haskell cabal library packaging files v9\".",
      "  ",
      " -- Ian Lynagh (wibble) <igloo@debian.org>  Wed, 21 Nov 2007 01:26:57 +0000",
      "  ",
      ""]

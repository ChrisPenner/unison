{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Unison.Test.GitSimple where

import Data.String.Here (iTrim)
import qualified Data.Text as Text
import EasyTest
import Shellmet ()
import System.Directory (removeDirectoryRecursive)
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import Unison.Codebase (Codebase, CodebasePath)
import qualified Unison.Codebase.FileCodebase as FC
import qualified Unison.Codebase.TranscriptParser as TR
import Unison.Parser (Ann)
import Unison.Prelude
import Unison.Symbol (Symbol)
import qualified Unison.Parser as Parser
import qualified Unison.Codebase as Codebase
import qualified Unison.Codebase.SqliteCodebase as SC

writeTranscriptOutput :: Bool
writeTranscriptOutput = True

test :: Test ()
test = scope "git-simple" . tests $ flip map [(FC.init, "fc")]--, (SC.init, "fc")]
  \(cbInit, name) -> scope name $ tests [
  pushPullTest cbInit "one-term"
-- simplest-author
    (\repo -> [iTrim|
```unison
c = 3
```
```ucm
.> debug.file
.> add
.> push ${repo}
```
|])
-- simplest-user
    (\repo -> [iTrim|
```ucm
.> pull ${repo}
.> alias.term ##Nat.+ +
```
```unison
> #msp7bv40rv + 1
```
|])
  ,
  pushPullTest cbInit "one-term2"
-- simplest-author
    (\repo -> [iTrim|
```unison
c = 3
```
```ucm
.> debug.file
.myLib> add
.myLib> push ${repo}
```
|])
-- simplest-user
    (\repo -> [iTrim|
```ucm
.yourLib> pull ${repo}
```
```unison
> c
```
|])
  ,
  pushPullTest cbInit "one-type"
-- simplest-author
    (\repo -> [iTrim|
```unison
type Foo = Foo
```
```ucm
.myLib> debug.file
.myLib> add
.myLib> push ${repo}
```
|])
-- simplest-user
    (\repo -> [iTrim|
```ucm
.yourLib> pull ${repo}
```
```unison
> Foo.Foo
```
|])
  ,
  pushPullTest cbInit "patching"
    (\repo -> [iTrim|
```ucm
.myLib> alias.term ##Nat.+ +
```
```unison
improveNat x = x + 3
```
```ucm
.myLib> add
.myLib> ls
.myLib> move.namespace .myLib .workaround1552.myLib.v1
.workaround1552.myLib> ls
.workaround1552.myLib> fork v1 v2
.workaround1552.myLib.v2>
```
```unison
improveNat x = x + 100
```
```ucm
.workaround1552.myLib.v2> update
.workaround1552.myLib> push ${repo}
```
    |])
    (\repo -> [iTrim|
```ucm
.myApp> pull ${repo}:.v1 external.yourLib
.myApp> alias.term ##Nat.* *
````
```unison
> greatApp = improveNat 5 * improveNat 6
```
```ucm
.myApp> add
.myApp> pull ${repo}:.v2 external.yourLib
```
```unison
> greatApp = improveNat 5 * improveNat 6
```
```ucm
.myApp> patch external.yourLib.patch
```
```unison
> greatApp = improveNat 5 * improveNat 6
```
    |])
-- ,

--   pushPullTest "regular"
--     (\repo -> [iTrim|
-- ```ucm:hide
-- .builtin> alias.type ##Nat Nat
-- .builtin> alias.term ##Nat.+ Nat.+
-- ```
-- ```unison
-- unique type outside.A = A Nat
-- unique type outside.B = B Nat Nat
-- outside.c = 3
-- outside.d = 4

-- unique type inside.X = X outside.A
-- inside.y = c + c
-- ```
-- ```ucm
-- .myLib> debug.file
-- .myLib> add
-- .myLib> push ${repo}
-- ```|])

--     (\repo -> [iTrim|
-- ```ucm:hide
-- .builtin> alias.type ##Nat Nat
-- .builtin> alias.term ##Nat.+ Nat.+
-- ```
-- ```ucm
-- .yourLib> pull ${repo}:.inside
-- ```
-- ```unison
-- > y + #msp7bv40rv + 1
-- ```
--  |])

  ]


-- type inside.X#skinr6rvg7
-- type outside.A#l2fmn9sdbk
-- type outside.B#nsgsq4ot5u
-- inside.y#omqnfettvj
-- outside.c#msp7bv40rv
-- outside.d#52addbrohu
-- .myLib> #6l0nd3i15e
-- .myLib.inside> #5regvciils
-- .myLib.inside.X> #kvcjrmgki6
-- .myLib.outside> #uq1mkkhlf1
-- .myLib.outside.A> #0e3g041m56
-- .myLib.outside.B> #j57m94daqi


pushPullTest :: Codebase.Init IO Symbol Parser.Ann -> String -> (FilePath -> String) -> (FilePath -> String) -> Test ()
pushPullTest cbInit name authorScript userScript = scope name $ do
  -- put all our junk into here
  tmp <- io $ Temp.getCanonicalTemporaryDirectory >>= flip Temp.createTempDirectory ("git-simple-" ++ name)

  -- initialize author and user codebases
  (_authorDir, closeAuthor, authorCodebase) <- io $ initCodebase cbInit tmp "author"
  (_userDir, closeUser, userCodebase) <- io $ initCodebase cbInit tmp "user"

  -- initialize git repo
  let repo = tmp </> "repo.git"
  io $ "git" ["init", "--bare", Text.pack repo]

  -- run author/push transcript
  authorOutput <- runTranscript tmp authorCodebase (authorScript repo)

  -- check out the resulting repo so we can inspect it
  io $ "git" ["clone", Text.pack repo, Text.pack $ tmp </> "repo" ]

  -- run user/pull transcript
  userOutput <- runTranscript tmp userCodebase (userScript repo)

  io do
    closeAuthor
    closeUser

    when writeTranscriptOutput $ writeFile
      ("unison-src"</>"transcripts"</>("GitSimple." ++ name ++ ".output.md"))
      (authorOutput <> "\n-------\n" <> userOutput)

    -- if we haven't crashed, clean up!
    removeDirectoryRecursive repo
    removeDirectoryRecursive tmp
  ok

-- initialize a fresh codebase
initCodebase :: Monad m => Codebase.Init m v a -> FilePath -> String -> m (CodebasePath, m (), Codebase m v a)
initCodebase cbInit tmpDir name = do
  let codebaseDir = tmpDir </> name
  (close, c) <- Codebase.initCodebase cbInit codebaseDir
  pure (codebaseDir, close, c)

-- run a transcript on an existing codebase
runTranscript :: MonadIO m => FilePath -> Codebase IO Symbol Ann -> String -> m String
runTranscript tmpDir c transcript = do
  let configFile = tmpDir </> ".unisonConfig"
  -- transcript runner wants a "current directory" for I guess writing scratch files?
  let cwd = tmpDir </> "cwd"
  let err err = error $ "Parse error: \n" <> show err

  -- parse and run the transcript
  flip (either err) (TR.parse "transcript" (Text.pack transcript)) $ \stanzas ->
    liftIO . fmap Text.unpack $ TR.run Nothing cwd configFile stanzas c
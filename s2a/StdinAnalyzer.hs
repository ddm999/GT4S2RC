{-# OPTIONS_GHC -Wno-incomplete-patterns #-}

module Main where

import Control.Monad
import Data.Array
import Data.Char
import Data.IORef
import Data.List
import Data.Word
import System.Environment
import System.IO
import S2RA.Bruteforce
import S2RA.Concurrent
import S2RA.S2Data

main :: IO ()
main = do
  putStrLn "Gran Turismo 4 Spec II v1.06.X Prize Car Randomizer Viability Stdin Analyzer"
  putStrLn "Viability value per car provided by TeaKanji\n"

  args <- getArgs
  let divByMissing = foldr (\ x -> (((fmap toLower x == "-m") || (fmap toLower x == "--missing")) ||)) False args

  when divByMissing $ putStrLn "Dividing by missing cars for 100%.\n"

  sp2Data@(_, _, necessities) <- loadData

  currentMaxViability1 <- newIORef ("", 0, 0)
  currentMaxViability2 <- newIORef ("", 0, 0)
  currentMaxViability3 <- newIORef ("", 0, 0)
  currentMaxViability4 <- newIORef ("", 0, 0)

  shouldContinue <- newMVar True

  d1 <- newTBQueueIO @Username 5
  d2 <- newTBQueueIO @Username 5
  d3 <- newTBQueueIO @Username 5
  d4 <- newTBQueueIO @Username 5

  sequence
    [ workerSTM "Searcher #1" (>) currentMaxViability1 divByMissing necessities d1 shouldContinue sp2Data
    , workerSTM "Searcher #2" (>) currentMaxViability2 divByMissing necessities d2 shouldContinue sp2Data
    , workerSTM "Searcher #3" (>) currentMaxViability3 divByMissing necessities d3 shouldContinue sp2Data
    , workerSTM "Searcher #4" (>) currentMaxViability4 divByMissing necessities d4 shouldContinue sp2Data
    ] >>= \ ts -> do
      let readLoop 1 = isEOF >>= (`unless` ((getLine >>= atomically . writeTBQueue d1) <* readLoop 2))
          readLoop 2 = isEOF >>= (`unless` ((getLine >>= atomically . writeTBQueue d2) <* readLoop 3))
          readLoop 3 = isEOF >>= (`unless` ((getLine >>= atomically . writeTBQueue d3) <* readLoop 4))
          readLoop 4 = isEOF >>= (`unless` ((getLine >>= atomically . writeTBQueue d4) <* readLoop 1))

      readLoop (1 :: Word8)
      modifyMVar_ shouldContinue (pure . const False)

      mapM_ joinHandle_ ts

  results <- traverse readIORef
    [ currentMaxViability1
    , currentMaxViability2
    , currentMaxViability3
    , currentMaxViability4
    ]

  putStrLn $ formatWinner "Overall" $ maximumBy (\ (_, a, _) (_, b, _) -> compare a b) results

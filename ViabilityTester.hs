{-# LANGUAGE OverloadedStrings, LambdaCase #-}

module ViabilityTester where

import Control.Concurrent
import Control.Monad.ST
import Control.Monad
import Data.Foldable
import Data.IORef
import Data.Text ( Text )
import qualified Data.Text as T
import qualified Data.Text.IO as TI
import GenerateCombinedList hiding ( main )
import GHC.Exception
import SpecIIData hiding ( main )
import System.IO

type Evaluation = (Username, Double)
type Cmp p      = p -> p -> Bool
newtype JoinHandle a = JH (ThreadId, MVar a)

-- WARNING: In GHC, holding onto the ThreadID after a thread has finished
--          running causes a memory leak.
forkJoinable :: IO a -> IO (JoinHandle a)
forkJoinable action = do
  lock <- newEmptyMVar :: IO (MVar a)
  tid  <- forkFinally action (\ case
    Right x -> putMVar lock x
    Left e  -> throw e)

  return $ JH (tid, lock)

joinHandle :: JoinHandle a -> IO a
joinHandle (JH (_, lock)) = takeMVar lock

joinHandle_ :: JoinHandle a -> IO ()
joinHandle_ = void . joinHandle

joinTid :: JoinHandle a -> ThreadId
joinTid (JH (tid, _)) = tid

charset :: String
charset = ['A'..'Z'] ++ ['a'..'z'] ++ " 0123456789`'\\;,.[]/-=!@#$^&*()~|:<>?_+{}"

determineViability :: Username -> SP2Data -> Evaluation
determineViability username sp2Data =
  let vs = bruteForce username sp2Data (const viability)
  in  (username, fromIntegral (sum vs) / fromIntegral (length vs))

formatWinner :: Text -> Evaluation -> Text
formatWinner tn (u, v) = T.concat ["[", tn, "]: New best for criteria ", T.pack (show v), " from username \"", u, "\"."]

isWinner :: Cmp Double -> IORef Evaluation -> Evaluation -> IO (Maybe Evaluation)
isWinner p mx c@(_, v) = do
  (_, v') <- readIORef mx
  return $ if p v v' then Just c else Nothing

determine :: Cmp Double -> IORef Evaluation -> Username -> SP2Data -> IO (Maybe Evaluation)
determine p mx un sp2Data =
  let vd = determineViability un sp2Data
  in  do
    w <- isWinner p mx vd
    forM_ w (writeIORef mx)
    return w

worker :: Text -> Cmp Double -> IORef Evaluation -> [Username] -> SP2Data -> IO (JoinHandle ())
worker name p mx uns sp2Data = forkJoinable $ forM_ uns $ \ un -> do
  result <- determine p mx un sp2Data
  forM_ result $ \ vs -> TI.putStrLn (formatWinner name vs)

generateDatasets :: Int -> ([Username], [Username], [Username], [Username], [Username], [Username])
generateDatasets n
  | n <= 1    = ( fmap T.singleton ['A'..'M']
                , fmap T.singleton ['N'..'Z']
                , fmap T.singleton ['a'..'m']
                , fmap T.singleton ['n'..'z']
                , fmap T.singleton " 0123456789`'\\;,.[]/"
                , fmap T.singleton "-=!@#$^&*()~|:<>?_+{}"
                )
  | otherwise = let (d1, d2, d3, d4, d5, d6) = generateDatasets (n - 1)
                in  ( d1 ++ (T.cons <$> charset <*> d1)
                    , d2 ++ (T.cons <$> charset <*> d2)
                    , d3 ++ (T.cons <$> charset <*> d3)
                    , d4 ++ (T.cons <$> charset <*> d4)
                    , d5 ++ (T.cons <$> charset <*> d5)
                    , d6 ++ (T.cons <$> charset <*> d6)
                    )

main :: IO ()
main = do
  putStrLn "Gran Turismo 4 Spec II v1.06.X Prize Car Randomizer Viability Brute-Forcer"
  putStrLn "Viability value per car provided by TeaKanji\n"

  sp2Data <- loadData

  currentMaxViability1 <- newIORef ("", 0)
  currentMaxViability2 <- newIORef ("", 0)
  currentMaxViability3 <- newIORef ("", 0)
  currentMaxViability4 <- newIORef ("", 0)
  currentMaxViability5 <- newIORef ("", 0)
  currentMaxViability6 <- newIORef ("", 0)

  TI.putStr "Enter a max username length: " >> hFlush stdout
  maxLen :: Int <- read <$> getLine

  let (d1, d2, d3, d4, d5, d6) = generateDatasets maxLen

  sequence
    [ worker "Searcher #1" (>) currentMaxViability1 d1 sp2Data
    , worker "Searcher #2" (>) currentMaxViability2 d2 sp2Data
    , worker "Searcher #3" (>) currentMaxViability3 d3 sp2Data
    , worker "Searcher #4" (>) currentMaxViability4 d4 sp2Data
    , worker "Searcher #5" (>) currentMaxViability5 d5 sp2Data
    , worker "Searcher #6" (>) currentMaxViability6 d6 sp2Data
    ] >>= mapM_ joinHandle

  results <- traverse readIORef
    [ currentMaxViability1
    , currentMaxViability2
    , currentMaxViability3
    , currentMaxViability4
    , currentMaxViability5
    , currentMaxViability6
    ]

  TI.putStrLn $ formatWinner "Overall" $ maximumBy (\ (_, a) (_, b) -> compare a b) results

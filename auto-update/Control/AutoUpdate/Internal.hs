{-# LANGUAGE RecordWildCards #-}

module Control.AutoUpdate.Internal (
    -- * Debugging
    mkClosableAutoUpdate,
    mkClosableAutoUpdate',
    UpdateState (..),
)
where

import Control.Concurrent.STM
import Control.Monad
import Data.IORef
import GHC.Event (getSystemTimerManager, registerTimeout, unregisterTimeout)

import Control.AutoUpdate.Types

-- $setup
-- >>> :set -XNumericUnderscores
-- >>> import Control.Concurrent

-- |
-- >>> iref <- newIORef (0 :: Int)
-- >>> action = modifyIORef iref (+ 1) >> readIORef iref
-- >>> (getValue, closeState) <- mkClosableAutoUpdate $ defaultUpdateSettings { updateFreq = 200_000, updateAction = action }
-- >>> getValue
-- 1
-- >>> threadDelay 100_000 >> getValue
-- 1
-- >>> threadDelay 200_000 >> getValue
-- 2
-- >>> closeState
mkClosableAutoUpdate :: UpdateSettings a -> IO (IO a, IO ())
mkClosableAutoUpdate = mkAutoUpdateThings $ \g c _ -> (g, c)

-- | provide `UpdateState` for debugging
mkClosableAutoUpdate' :: UpdateSettings a -> IO (IO a, IO (), UpdateState a)
mkClosableAutoUpdate' = mkAutoUpdateThings (,,)

mkAutoUpdateThings
    :: (IO a -> IO () -> UpdateState a -> b) -> UpdateSettings a -> IO b
mkAutoUpdateThings mk settings@UpdateSettings{..} =
    mkAutoUpdateThingsWithModify mk settings (const updateAction)

mkAutoUpdateThingsWithModify
    :: (IO a -> IO () -> UpdateState a -> b) -> UpdateSettings a -> (a -> IO a) -> IO b
mkAutoUpdateThingsWithModify mk settings update1 = do
    us <- openUpdateState settings update1
    pure $ mk (getUpdateResult us) (closeUpdateState us) us

--------------------------------------------------------------------------------

{- FOURMOLU_DISABLE -}
data UpdateState a =
    UpdateState
    { usUpdateAction_   :: a -> IO a
    , usLastResult_     :: IORef a
    , usIntervalMicro_  :: Int
    , usTimeHasCome_    :: TVar Bool
    , usDeleteTimeout_  :: IORef (IO ())
    }
{- FOURMOLU_ENABLE -}

mkDeleteTimeout :: TVar Bool -> Int -> IO (IO ())
mkDeleteTimeout thc micro = do
    mgr <- getSystemTimerManager
    key <- registerTimeout mgr micro (atomically $ writeTVar thc True)
    pure $ unregisterTimeout mgr key

openUpdateState :: UpdateSettings a -> (a -> IO a) -> IO (UpdateState a)
openUpdateState UpdateSettings{..} update1 = do
    thc <- newTVarIO False
    UpdateState update1
        <$> (newIORef =<< updateAction)
        <*> pure updateFreq
        <*> pure thc
        <*> (newIORef =<< mkDeleteTimeout thc updateFreq)

closeUpdateState :: UpdateState a -> IO ()
closeUpdateState UpdateState{..} = do
    delete <- readIORef usDeleteTimeout_
    delete

onceOnTimeHasCome :: UpdateState a -> IO () -> IO ()
onceOnTimeHasCome UpdateState{..} action = do
    action' <- atomically $ do
        timeHasCome <- readTVar usTimeHasCome_
        when timeHasCome $ writeTVar usTimeHasCome_ False
        pure $ when timeHasCome action
    action'

getUpdateResult :: UpdateState a -> IO a
getUpdateResult us@UpdateState{..} = do
    onceOnTimeHasCome us $ do
        writeIORef usLastResult_ =<< usUpdateAction_ =<< readIORef usLastResult_
        writeIORef usDeleteTimeout_ =<< mkDeleteTimeout usTimeHasCome_ usIntervalMicro_
    readIORef usLastResult_

-- | Observation interface.

{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module RSTC.Obs where

import RSTC.Car
import RSTC.Theorems

import Foreign.C


class RealFloat a => Obs a b | b -> a where
   next :: b -> Maybe b
   time :: b -> Time a
   ntg  :: b -> Car -> Car -> NTG a
   ttc  :: b -> Car -> Car -> TTC a
   lane :: b -> Car -> Lane


type ObsId = Int


instance Obs Double ObsId where
   next e     = getObs (succ e)
   time e     = realToFrac (c_time (e2c e))
   ntg  e b c = realToFrac (c_ntg (e2c e) (c2c b) (c2c c))
   ttc  e b c = realToFrac (c_ttc (e2c e) (c2c b) (c2c c))
   lane e b   = case c_lane (e2c e) (c2c b) of -1 -> LeftLane
                                               1  -> RightLane
                                               _  -> RightLane


e2c :: Int -> CInt
e2c = fromIntegral

c2c :: Car -> CInt
c2c = fromIntegral . fromEnum


observations :: [Maybe ObsId]
observations = map getObs [0..]


getObs :: ObsId -> Maybe ObsId
getObs e = case c_next_obs (e2c e) of 1 -> Just e
                                      _ -> Nothing


foreign import ccall unsafe "obs_next"
   c_next_obs :: CInt -> CInt -- obs_id -> success

foreign import ccall unsafe "obs_time"
   c_time :: CInt -> CDouble -- obs_id -> time

foreign import ccall unsafe "obs_lane"
   c_lane :: CInt -> CInt -> CInt -- obs_id -> -1=left, +1=right, 0=error

foreign import ccall unsafe "obs_ntg"
   c_ntg :: CInt -> CInt -> CInt -> CDouble -- obs_id -> b -> c -> NTG or NaN

foreign import ccall unsafe "obs_ttc"
   c_ttc :: CInt -> CInt -> CInt -> CDouble -- obs_id -> b -> c -> TTC or NaN

{-
c_next_obs = undefined
c_time = undefined
c_lane = undefined
c_ntg = undefined
c_ttc = undefined
-}


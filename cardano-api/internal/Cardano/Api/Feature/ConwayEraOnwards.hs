{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Cardano.Api.Feature.ConwayEraOnwards
  ( ConwayEraOnwards(..)
  , AnyConwayEraOnwards(..)
  , conwayEraOnwardsConstraints
  , conwayEraOnwardsToCardanoEra
  , conwayEraOnwardsToShelleyBasedEra
  ) where

import           Cardano.Api.Eras
import           Cardano.Api.Query.Types

import           Cardano.Binary
import           Cardano.Crypto.Hash.Class (HashAlgorithm)
import qualified Cardano.Ledger.Api as L

import           Data.Aeson

data ConwayEraOnwards era where
  ConwayEraOnwardsConway :: ConwayEraOnwards ConwayEra

deriving instance Show (ConwayEraOnwards era)
deriving instance Eq (ConwayEraOnwards era)

instance FeatureInEra ConwayEraOnwards where
  featureInEra no yes = \case
    ByronEra    -> no
    ShelleyEra  -> no
    AllegraEra  -> no
    MaryEra     -> no
    AlonzoEra   -> no
    BabbageEra  -> no
    ConwayEra   -> yes ConwayEraOnwardsConway

data AnyConwayEraOnwards where
  AnyConwayEraOnwards :: ConwayEraOnwards era -> AnyConwayEraOnwards

deriving instance Show AnyConwayEraOnwards

type ConwayEraOnwardsConstraints era =
  ( FromCBOR (DebugLedgerState era)
  , HashAlgorithm (L.HASH (L.EraCrypto (ShelleyLedgerEra era)))
  , IsShelleyBasedEra era
  , L.ConwayEraTxBody (ShelleyLedgerEra era)
  , L.Era (ShelleyLedgerEra era)
  , L.EraCrypto (ShelleyLedgerEra era) ~ L.StandardCrypto
  , ToJSON (DebugLedgerState era)
  )

conwayEraOnwardsConstraints
  :: ConwayEraOnwards era
  -> (ConwayEraOnwardsConstraints era => a)
  -> a
conwayEraOnwardsConstraints = \case
  ConwayEraOnwardsConway -> id

conwayEraOnwardsToCardanoEra :: ConwayEraOnwards era -> CardanoEra era
conwayEraOnwardsToCardanoEra = shelleyBasedToCardanoEra . conwayEraOnwardsToShelleyBasedEra

conwayEraOnwardsToShelleyBasedEra :: ConwayEraOnwards era -> ShelleyBasedEra era
conwayEraOnwardsToShelleyBasedEra = \case
  ConwayEraOnwardsConway -> ShelleyBasedEraConway

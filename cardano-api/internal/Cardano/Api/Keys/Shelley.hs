{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

-- The Shelley ledger uses promoted data kinds which we have to use, but we do
-- not export any from this API. We also use them unticked as nature intended.
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}

-- | Shelley key types and their 'Key' class instances
--
module Cardano.Api.Keys.Shelley (

    -- * Key types
    CommitteeColdKey,
    CommitteeHotKey,
    DRepKey,
    PaymentKey,
    PaymentExtendedKey,
    StakeKey,
    StakeExtendedKey,
    StakePoolKey,
    GenesisKey,
    GenesisExtendedKey,
    GenesisDelegateKey,
    GenesisDelegateExtendedKey,
    GenesisUTxOKey,

    -- * Data family instances
    AsType(..),
    VerificationKey(..),
    SigningKey(..),
    Hash(..),
  ) where

import           Cardano.Api.Error
import           Cardano.Api.Hash
import           Cardano.Api.HasTypeProxy
import           Cardano.Api.Keys.Class
import           Cardano.Api.SerialiseBech32
import           Cardano.Api.SerialiseCBOR
import           Cardano.Api.SerialiseJSON
import           Cardano.Api.SerialiseRaw
import           Cardano.Api.SerialiseTextEnvelope
import           Cardano.Api.SerialiseUsing

import qualified Cardano.Crypto.DSIGN.Class as Crypto
import qualified Cardano.Crypto.Hash.Class as Crypto
import qualified Cardano.Crypto.Seed as Crypto
import qualified Cardano.Crypto.Wallet as Crypto.HD
import           Cardano.Ledger.Crypto (StandardCrypto)
import qualified Cardano.Ledger.Crypto as Shelley (DSIGN)
import qualified Cardano.Ledger.Keys as Shelley

import           Data.Aeson.Types (ToJSONKey (..), toJSONKeyText, withText)
import           Data.Bifunctor (first)
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.Either.Combinators (maybeToRight)
import           Data.Maybe
import           Data.String (IsString (..))
import qualified Data.Text as Text

--
-- Shelley payment keys
--

-- | Shelley-era payment keys. Used for Shelley payment addresses and witnessing
-- transactions that spend from these addresses.
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data PaymentKey

instance HasTypeProxy PaymentKey where
    data AsType PaymentKey = AsPaymentKey
    proxyToAsType _ = AsPaymentKey

instance Key PaymentKey where

    newtype VerificationKey PaymentKey =
        PaymentVerificationKey (Shelley.VKey Shelley.Payment StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey PaymentKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey PaymentKey =
        PaymentSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey PaymentKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType PaymentKey -> Crypto.Seed -> SigningKey PaymentKey
    deterministicSigningKey AsPaymentKey seed =
        PaymentSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType PaymentKey -> Word
    deterministicSigningKeySeedSize AsPaymentKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey PaymentKey -> VerificationKey PaymentKey
    getVerificationKey (PaymentSigningKey sk) =
        PaymentVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey PaymentKey -> Hash PaymentKey
    verificationKeyHash (PaymentVerificationKey vkey) =
        PaymentKeyHash (Shelley.hashKey vkey)

instance SerialiseAsRawBytes (VerificationKey PaymentKey) where
    serialiseToRawBytes (PaymentVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsPaymentKey) bs =
      maybe
        (Left (SerialiseAsRawBytesError "Unable to deserialise VerificationKey PaymentKey"))
        (Right . PaymentVerificationKey . Shelley.VKey)
        (Crypto.rawDeserialiseVerKeyDSIGN bs)

instance SerialiseAsRawBytes (SigningKey PaymentKey) where
    serialiseToRawBytes (PaymentSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsPaymentKey) bs =
      maybe
        (Left (SerialiseAsRawBytesError "Unable to serialise AsSigningKey AsPaymentKey"))
        (Right . PaymentSigningKey)
        (Crypto.rawDeserialiseSignKeyDSIGN bs)

instance SerialiseAsBech32 (VerificationKey PaymentKey) where
    bech32PrefixFor         _ =  "addr_vk"
    bech32PrefixesPermitted _ = ["addr_vk"]

instance SerialiseAsBech32 (SigningKey PaymentKey) where
    bech32PrefixFor         _ =  "addr_sk"
    bech32PrefixesPermitted _ = ["addr_sk"]

newtype instance Hash PaymentKey =
    PaymentKeyHash (Shelley.KeyHash Shelley.Payment StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash PaymentKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash PaymentKey)
  deriving (ToJSONKey, ToJSON, FromJSON) via UsingRawBytesHex (Hash PaymentKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash PaymentKey) where
    serialiseToRawBytes (PaymentKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsPaymentKey) bs =
      maybeToRight
        (SerialiseAsRawBytesError "Unable to deserialise Hash PaymentKey")
        (PaymentKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs)

instance HasTextEnvelope (VerificationKey PaymentKey) where
    textEnvelopeType _ = "PaymentVerificationKeyShelley_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey PaymentKey) where
    textEnvelopeType _ = "PaymentSigningKeyShelley_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy


--
-- Shelley payment extended ed25519 keys
--

-- | Shelley-era payment keys using extended ed25519 cryptographic keys.
--
-- They can be used for Shelley payment addresses and witnessing
-- transactions that spend from these addresses.
--
-- These extended keys are used by HD wallets. So this type provides
-- interoperability with HD wallets. The ITN CLI also supported this key type.
--
-- The extended verification keys can be converted (via 'castVerificationKey')
-- to ordinary keys (i.e. 'VerificationKey' 'PaymentKey') but this is /not/ the
-- case for the signing keys. The signing keys can be used to witness
-- transactions directly, with verification via their non-extended verification
-- key ('VerificationKey' 'PaymentKey').
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data PaymentExtendedKey

instance HasTypeProxy PaymentExtendedKey where
    data AsType PaymentExtendedKey = AsPaymentExtendedKey
    proxyToAsType _ = AsPaymentExtendedKey

instance Key PaymentExtendedKey where

    newtype VerificationKey PaymentExtendedKey =
        PaymentExtendedVerificationKey Crypto.HD.XPub
      deriving stock (Eq)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey PaymentExtendedKey)

    newtype SigningKey PaymentExtendedKey =
        PaymentExtendedSigningKey Crypto.HD.XPrv
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey PaymentExtendedKey)

    deterministicSigningKey :: AsType PaymentExtendedKey
                            -> Crypto.Seed
                            -> SigningKey PaymentExtendedKey
    deterministicSigningKey AsPaymentExtendedKey seed =
        PaymentExtendedSigningKey
          (Crypto.HD.generate seedbs BS.empty)
      where
       (seedbs, _) = Crypto.getBytesFromSeedT 32 seed

    deterministicSigningKeySeedSize :: AsType PaymentExtendedKey -> Word
    deterministicSigningKeySeedSize AsPaymentExtendedKey = 32

    getVerificationKey :: SigningKey PaymentExtendedKey
                       -> VerificationKey PaymentExtendedKey
    getVerificationKey (PaymentExtendedSigningKey sk) =
        PaymentExtendedVerificationKey (Crypto.HD.toXPub sk)

    -- | We use the hash of the normal non-extended pub key so that it is
    -- consistent with the one used in addresses and signatures.
    --
    verificationKeyHash :: VerificationKey PaymentExtendedKey
                        -> Hash PaymentExtendedKey
    verificationKeyHash (PaymentExtendedVerificationKey vk) =
        PaymentExtendedKeyHash
      . Shelley.KeyHash
      . Crypto.castHash
      $ Crypto.hashWith Crypto.HD.xpubPublicKey vk


instance ToCBOR (VerificationKey PaymentExtendedKey) where
    toCBOR (PaymentExtendedVerificationKey xpub) =
      toCBOR (Crypto.HD.unXPub xpub)

instance FromCBOR (VerificationKey PaymentExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . PaymentExtendedVerificationKey)
             (Crypto.HD.xpub (bs :: ByteString))

instance ToCBOR (SigningKey PaymentExtendedKey) where
    toCBOR (PaymentExtendedSigningKey xprv) =
      toCBOR (Crypto.HD.unXPrv xprv)

instance FromCBOR (SigningKey PaymentExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . PaymentExtendedSigningKey)
             (Crypto.HD.xprv (bs :: ByteString))

instance SerialiseAsRawBytes (VerificationKey PaymentExtendedKey) where
    serialiseToRawBytes (PaymentExtendedVerificationKey xpub) =
      Crypto.HD.unXPub xpub

    deserialiseFromRawBytes (AsVerificationKey AsPaymentExtendedKey) bs =
      first
        (const (SerialiseAsRawBytesError "Unable to deserialise VerificationKey PaymentExtendedKey"))
        (PaymentExtendedVerificationKey <$> Crypto.HD.xpub bs)

instance SerialiseAsRawBytes (SigningKey PaymentExtendedKey) where
    serialiseToRawBytes (PaymentExtendedSigningKey xprv) =
      Crypto.HD.unXPrv xprv

    deserialiseFromRawBytes (AsSigningKey AsPaymentExtendedKey) bs =
      first
        (const (SerialiseAsRawBytesError "Unable to deserialise SigningKey PaymentExtendedKey"))
        (PaymentExtendedSigningKey <$> Crypto.HD.xprv bs)

instance SerialiseAsBech32 (VerificationKey PaymentExtendedKey) where
    bech32PrefixFor         _ =  "addr_xvk"
    bech32PrefixesPermitted _ = ["addr_xvk"]

instance SerialiseAsBech32 (SigningKey PaymentExtendedKey) where
    bech32PrefixFor         _ =  "addr_xsk"
    bech32PrefixesPermitted _ = ["addr_xsk"]


newtype instance Hash PaymentExtendedKey =
    PaymentExtendedKeyHash (Shelley.KeyHash Shelley.Payment StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash PaymentExtendedKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash PaymentExtendedKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash PaymentExtendedKey) where
    serialiseToRawBytes (PaymentExtendedKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsPaymentExtendedKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash PaymentExtendedKey") $
        PaymentExtendedKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey PaymentExtendedKey) where
    textEnvelopeType _ = "PaymentExtendedVerificationKeyShelley_ed25519_bip32"

instance HasTextEnvelope (SigningKey PaymentExtendedKey) where
    textEnvelopeType _ = "PaymentExtendedSigningKeyShelley_ed25519_bip32"

instance CastVerificationKeyRole PaymentExtendedKey PaymentKey where
    castVerificationKey (PaymentExtendedVerificationKey vk) =
        PaymentVerificationKey
      . Shelley.VKey
      . fromMaybe impossible
      . Crypto.rawDeserialiseVerKeyDSIGN
      . Crypto.HD.xpubPublicKey
      $ vk
      where
        impossible =
          error "castVerificationKey: byron and shelley key sizes do not match!"


--
-- Stake keys
--

data StakeKey

instance HasTypeProxy StakeKey where
    data AsType StakeKey = AsStakeKey
    proxyToAsType _ = AsStakeKey

instance Key StakeKey where

    newtype VerificationKey StakeKey = StakeVerificationKey
      { unStakeVerificationKey :: Shelley.VKey Shelley.Staking StandardCrypto
      }
      deriving stock (Eq)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey StakeKey)

    newtype SigningKey StakeKey =
        StakeSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey StakeKey)

    deterministicSigningKey :: AsType StakeKey -> Crypto.Seed -> SigningKey StakeKey
    deterministicSigningKey AsStakeKey seed =
        StakeSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType StakeKey -> Word
    deterministicSigningKeySeedSize AsStakeKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey StakeKey -> VerificationKey StakeKey
    getVerificationKey (StakeSigningKey sk) =
        StakeVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey StakeKey -> Hash StakeKey
    verificationKeyHash (StakeVerificationKey vkey) =
        StakeKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey StakeKey) where
    serialiseToRawBytes (StakeVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsStakeKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey StakeKey") $
        StakeVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey StakeKey) where
    serialiseToRawBytes (StakeSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsStakeKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey StakeKey") $
        StakeSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs

instance SerialiseAsBech32 (VerificationKey StakeKey) where
    bech32PrefixFor         _ =  "stake_vk"
    bech32PrefixesPermitted _ = ["stake_vk"]

instance SerialiseAsBech32 (SigningKey StakeKey) where
    bech32PrefixFor         _ =  "stake_sk"
    bech32PrefixesPermitted _ = ["stake_sk"]


newtype instance Hash StakeKey =
    StakeKeyHash (Shelley.KeyHash Shelley.Staking StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash StakeKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash StakeKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash StakeKey) where
    serialiseToRawBytes (StakeKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsStakeKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash StakeKey") $
        StakeKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey StakeKey) where
    textEnvelopeType _ = "StakeVerificationKeyShelley_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey StakeKey) where
    textEnvelopeType _ = "StakeSigningKeyShelley_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy


--
-- Shelley stake extended ed25519 keys
--

-- | Shelley-era stake keys using extended ed25519 cryptographic keys.
--
-- They can be used for Shelley stake addresses and witnessing transactions
-- that use stake addresses.
--
-- These extended keys are used by HD wallets. So this type provides
-- interoperability with HD wallets. The ITN CLI also supported this key type.
--
-- The extended verification keys can be converted (via 'castVerificationKey')
-- to ordinary keys (i.e. 'VerificationKey' 'StakeKey') but this is /not/ the
-- case for the signing keys. The signing keys can be used to witness
-- transactions directly, with verification via their non-extended verification
-- key ('VerificationKey' 'StakeKey').
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data StakeExtendedKey

instance HasTypeProxy StakeExtendedKey where
    data AsType StakeExtendedKey = AsStakeExtendedKey
    proxyToAsType _ = AsStakeExtendedKey

instance Key StakeExtendedKey where

    newtype VerificationKey StakeExtendedKey =
        StakeExtendedVerificationKey Crypto.HD.XPub
      deriving stock (Eq)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey StakeExtendedKey)

    newtype SigningKey StakeExtendedKey =
        StakeExtendedSigningKey Crypto.HD.XPrv
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey StakeExtendedKey)

    deterministicSigningKey :: AsType StakeExtendedKey
                            -> Crypto.Seed
                            -> SigningKey StakeExtendedKey
    deterministicSigningKey AsStakeExtendedKey seed =
        StakeExtendedSigningKey
          (Crypto.HD.generate seedbs BS.empty)
      where
       (seedbs, _) = Crypto.getBytesFromSeedT 32 seed

    deterministicSigningKeySeedSize :: AsType StakeExtendedKey -> Word
    deterministicSigningKeySeedSize AsStakeExtendedKey = 32

    getVerificationKey :: SigningKey StakeExtendedKey
                       -> VerificationKey StakeExtendedKey
    getVerificationKey (StakeExtendedSigningKey sk) =
        StakeExtendedVerificationKey (Crypto.HD.toXPub sk)

    -- | We use the hash of the normal non-extended pub key so that it is
    -- consistent with the one used in addresses and signatures.
    --
    verificationKeyHash :: VerificationKey StakeExtendedKey
                        -> Hash StakeExtendedKey
    verificationKeyHash (StakeExtendedVerificationKey vk) =
        StakeExtendedKeyHash
      . Shelley.KeyHash
      . Crypto.castHash
      $ Crypto.hashWith Crypto.HD.xpubPublicKey vk


instance ToCBOR (VerificationKey StakeExtendedKey) where
    toCBOR (StakeExtendedVerificationKey xpub) =
      toCBOR (Crypto.HD.unXPub xpub)

instance FromCBOR (VerificationKey StakeExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . StakeExtendedVerificationKey)
             (Crypto.HD.xpub (bs :: ByteString))

instance ToCBOR (SigningKey StakeExtendedKey) where
    toCBOR (StakeExtendedSigningKey xprv) =
      toCBOR (Crypto.HD.unXPrv xprv)

instance FromCBOR (SigningKey StakeExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . StakeExtendedSigningKey)
             (Crypto.HD.xprv (bs :: ByteString))

instance SerialiseAsRawBytes (VerificationKey StakeExtendedKey) where
    serialiseToRawBytes (StakeExtendedVerificationKey xpub) =
      Crypto.HD.unXPub xpub

    deserialiseFromRawBytes (AsVerificationKey AsStakeExtendedKey) bs =
      first (\msg -> SerialiseAsRawBytesError ("Unable to deserialise VerificationKey StakeExtendedKey: " ++ msg)) $
        StakeExtendedVerificationKey <$> Crypto.HD.xpub bs

instance SerialiseAsRawBytes (SigningKey StakeExtendedKey) where
    serialiseToRawBytes (StakeExtendedSigningKey xprv) =
      Crypto.HD.unXPrv xprv

    deserialiseFromRawBytes (AsSigningKey AsStakeExtendedKey) bs =
      first (\msg -> SerialiseAsRawBytesError ("Unable to deserialise SigningKey StakeExtendedKey: " ++ msg)) $
        StakeExtendedSigningKey <$> Crypto.HD.xprv bs

instance SerialiseAsBech32 (VerificationKey StakeExtendedKey) where
    bech32PrefixFor         _ =  "stake_xvk"
    bech32PrefixesPermitted _ = ["stake_xvk"]

instance SerialiseAsBech32 (SigningKey StakeExtendedKey) where
    bech32PrefixFor         _ =  "stake_xsk"
    bech32PrefixesPermitted _ = ["stake_xsk"]


newtype instance Hash StakeExtendedKey =
    StakeExtendedKeyHash (Shelley.KeyHash Shelley.Staking StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash StakeExtendedKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash StakeExtendedKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash StakeExtendedKey) where
    serialiseToRawBytes (StakeExtendedKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsStakeExtendedKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash StakeExtendedKey") $
        StakeExtendedKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey StakeExtendedKey) where
    textEnvelopeType _ = "StakeExtendedVerificationKeyShelley_ed25519_bip32"

instance HasTextEnvelope (SigningKey StakeExtendedKey) where
    textEnvelopeType _ = "StakeExtendedSigningKeyShelley_ed25519_bip32"

instance CastVerificationKeyRole StakeExtendedKey StakeKey where
    castVerificationKey (StakeExtendedVerificationKey vk) =
        StakeVerificationKey
      . Shelley.VKey
      . fromMaybe impossible
      . Crypto.rawDeserialiseVerKeyDSIGN
      . Crypto.HD.xpubPublicKey
      $ vk
      where
        impossible =
          error "castVerificationKey: byron and shelley key sizes do not match!"


--
-- Genesis keys
--

data GenesisKey

instance HasTypeProxy GenesisKey where
    data AsType GenesisKey = AsGenesisKey
    proxyToAsType _ = AsGenesisKey

instance Key GenesisKey where

    newtype VerificationKey GenesisKey =
        GenesisVerificationKey (Shelley.VKey Shelley.Genesis StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey GenesisKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey GenesisKey =
        GenesisSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey GenesisKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType GenesisKey -> Crypto.Seed -> SigningKey GenesisKey
    deterministicSigningKey AsGenesisKey seed =
        GenesisSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType GenesisKey -> Word
    deterministicSigningKeySeedSize AsGenesisKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey GenesisKey -> VerificationKey GenesisKey
    getVerificationKey (GenesisSigningKey sk) =
        GenesisVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey GenesisKey -> Hash GenesisKey
    verificationKeyHash (GenesisVerificationKey vkey) =
        GenesisKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey GenesisKey) where
    serialiseToRawBytes (GenesisVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsGenesisKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey GenesisKey") $
        GenesisVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey GenesisKey) where
    serialiseToRawBytes (GenesisSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsGenesisKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey GenesisKey") $
        GenesisSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs


newtype instance Hash GenesisKey =
    GenesisKeyHash (Shelley.KeyHash Shelley.Genesis StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash GenesisKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash GenesisKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash GenesisKey) where
    serialiseToRawBytes (GenesisKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsGenesisKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash GenesisKey") $
        GenesisKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey GenesisKey) where
    textEnvelopeType _ = "GenesisVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey GenesisKey) where
    textEnvelopeType _ = "GenesisSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance CastVerificationKeyRole GenesisKey PaymentKey where
    castVerificationKey (GenesisVerificationKey (Shelley.VKey vk)) =
      PaymentVerificationKey (Shelley.VKey vk)


--
-- Constitutional Committee Hot Keys
--

type KeyRoleCommitteeHotKey = Shelley.Genesis -- TODO CIP-1694 this should be a newtype Shelley.CommitteeHotKey

data CommitteeHotKey

instance HasTypeProxy CommitteeHotKey where
    data AsType CommitteeHotKey = AsCommitteeHotKey
    proxyToAsType _ = AsCommitteeHotKey

instance Key CommitteeHotKey where

    newtype VerificationKey CommitteeHotKey =
        CommitteeHotVerificationKey (Shelley.VKey KeyRoleCommitteeHotKey StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey CommitteeHotKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey CommitteeHotKey =
        CommitteeHotSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey CommitteeHotKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType CommitteeHotKey -> Crypto.Seed -> SigningKey CommitteeHotKey
    deterministicSigningKey AsCommitteeHotKey seed =
        CommitteeHotSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType CommitteeHotKey -> Word
    deterministicSigningKeySeedSize AsCommitteeHotKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey CommitteeHotKey -> VerificationKey CommitteeHotKey
    getVerificationKey (CommitteeHotSigningKey sk) =
        CommitteeHotVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey CommitteeHotKey -> Hash CommitteeHotKey
    verificationKeyHash (CommitteeHotVerificationKey vkey) =
        CommitteeHotKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey CommitteeHotKey) where
    serialiseToRawBytes (CommitteeHotVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsCommitteeHotKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey Constitutional Committee Hot Key") $
        CommitteeHotVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey CommitteeHotKey) where
    serialiseToRawBytes (CommitteeHotSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsCommitteeHotKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey Constitutional Committee Hot Key") $
        CommitteeHotSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs


newtype instance Hash CommitteeHotKey =
    CommitteeHotKeyHash (Shelley.KeyHash KeyRoleCommitteeHotKey StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash CommitteeHotKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash CommitteeHotKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash CommitteeHotKey) where
    serialiseToRawBytes (CommitteeHotKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsCommitteeHotKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash Constitutional Committee Hot Key") $
        CommitteeHotKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey CommitteeHotKey) where
    textEnvelopeType _ = "ConstitutionalCommitteeHotVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey CommitteeHotKey) where
    textEnvelopeType _ = "ConstitutionalCommitteeHotSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance CastVerificationKeyRole CommitteeHotKey PaymentKey where
    castVerificationKey (CommitteeHotVerificationKey (Shelley.VKey vk)) =
      PaymentVerificationKey (Shelley.VKey vk)

instance SerialiseAsBech32 (Hash CommitteeHotKey) where
    bech32PrefixFor         _ =  "committee_hot"
    bech32PrefixesPermitted _ = ["committee_hot"]

instance SerialiseAsBech32 (VerificationKey CommitteeHotKey) where
    bech32PrefixFor         _ =  "drep_vk"
    bech32PrefixesPermitted _ = ["drep_vk"]

instance SerialiseAsBech32 (SigningKey CommitteeHotKey) where
    bech32PrefixFor         _ =  "drep_sk"
    bech32PrefixesPermitted _ = ["drep_sk"]

--
-- Constitutional Committee Cold Keys
--

data CommitteeColdKey

instance HasTypeProxy CommitteeColdKey where
    data AsType CommitteeColdKey = AsCommitteeColdKey
    proxyToAsType _ = AsCommitteeColdKey

instance Key CommitteeColdKey where

    newtype VerificationKey CommitteeColdKey =
        CommitteeColdVerificationKey (Shelley.VKey Shelley.CommitteeColdKey StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey CommitteeColdKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey CommitteeColdKey =
        CommitteeColdSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey CommitteeColdKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType CommitteeColdKey -> Crypto.Seed -> SigningKey CommitteeColdKey
    deterministicSigningKey AsCommitteeColdKey seed =
        CommitteeColdSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType CommitteeColdKey -> Word
    deterministicSigningKeySeedSize AsCommitteeColdKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey CommitteeColdKey -> VerificationKey CommitteeColdKey
    getVerificationKey (CommitteeColdSigningKey sk) =
        CommitteeColdVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey CommitteeColdKey -> Hash CommitteeColdKey
    verificationKeyHash (CommitteeColdVerificationKey vkey) =
        CommitteeColdKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey CommitteeColdKey) where
    serialiseToRawBytes (CommitteeColdVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsCommitteeColdKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey Constitutional Committee Cold Key") $
        CommitteeColdVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey CommitteeColdKey) where
    serialiseToRawBytes (CommitteeColdSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsCommitteeColdKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey Constitutional Committee Cold Key") $
        CommitteeColdSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs


newtype instance Hash CommitteeColdKey =
    CommitteeColdKeyHash (Shelley.KeyHash Shelley.CommitteeColdKey StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash CommitteeColdKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash CommitteeColdKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash CommitteeColdKey) where
    serialiseToRawBytes (CommitteeColdKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsCommitteeColdKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash Constitutional Committee Cold Key") $
        CommitteeColdKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey CommitteeColdKey) where
    textEnvelopeType _ = "ConstitutionalCommitteeColdVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey CommitteeColdKey) where
    textEnvelopeType _ = "ConstitutionalCommitteeColdSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance CastVerificationKeyRole CommitteeColdKey PaymentKey where
    castVerificationKey (CommitteeColdVerificationKey (Shelley.VKey vk)) =
      PaymentVerificationKey (Shelley.VKey vk)

instance SerialiseAsBech32 (Hash CommitteeColdKey) where
    bech32PrefixFor         _ =  "committee_cold"
    bech32PrefixesPermitted _ = ["committee_cold"]

instance SerialiseAsBech32 (VerificationKey CommitteeColdKey) where
    bech32PrefixFor         _ =  "drep_vk"
    bech32PrefixesPermitted _ = ["drep_vk"]

instance SerialiseAsBech32 (SigningKey CommitteeColdKey) where
    bech32PrefixFor         _ =  "drep_sk"
    bech32PrefixesPermitted _ = ["drep_sk"]

--
-- Shelley genesis extended ed25519 keys
--

-- | Shelley-era genesis keys using extended ed25519 cryptographic keys.
--
-- These serve the same role as normal genesis keys, but are here to support
-- legacy Byron genesis keys which used extended keys.
--
-- The extended verification keys can be converted (via 'castVerificationKey')
-- to ordinary keys (i.e. 'VerificationKey' 'GenesisKey') but this is /not/ the
-- case for the signing keys. The signing keys can be used to witness
-- transactions directly, with verification via their non-extended verification
-- key ('VerificationKey' 'GenesisKey').
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data GenesisExtendedKey

instance HasTypeProxy GenesisExtendedKey where
    data AsType GenesisExtendedKey = AsGenesisExtendedKey
    proxyToAsType _ = AsGenesisExtendedKey

instance Key GenesisExtendedKey where

    newtype VerificationKey GenesisExtendedKey =
        GenesisExtendedVerificationKey Crypto.HD.XPub
      deriving stock (Eq)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey GenesisExtendedKey)

    newtype SigningKey GenesisExtendedKey =
        GenesisExtendedSigningKey Crypto.HD.XPrv
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey GenesisExtendedKey)

    deterministicSigningKey :: AsType GenesisExtendedKey
                            -> Crypto.Seed
                            -> SigningKey GenesisExtendedKey
    deterministicSigningKey AsGenesisExtendedKey seed =
        GenesisExtendedSigningKey
          (Crypto.HD.generate seedbs BS.empty)
      where
       (seedbs, _) = Crypto.getBytesFromSeedT 32 seed

    deterministicSigningKeySeedSize :: AsType GenesisExtendedKey -> Word
    deterministicSigningKeySeedSize AsGenesisExtendedKey = 32

    getVerificationKey :: SigningKey GenesisExtendedKey
                       -> VerificationKey GenesisExtendedKey
    getVerificationKey (GenesisExtendedSigningKey sk) =
        GenesisExtendedVerificationKey (Crypto.HD.toXPub sk)

    -- | We use the hash of the normal non-extended pub key so that it is
    -- consistent with the one used in addresses and signatures.
    --
    verificationKeyHash :: VerificationKey GenesisExtendedKey
                        -> Hash GenesisExtendedKey
    verificationKeyHash (GenesisExtendedVerificationKey vk) =
        GenesisExtendedKeyHash
      . Shelley.KeyHash
      . Crypto.castHash
      $ Crypto.hashWith Crypto.HD.xpubPublicKey vk


instance ToCBOR (VerificationKey GenesisExtendedKey) where
    toCBOR (GenesisExtendedVerificationKey xpub) =
      toCBOR (Crypto.HD.unXPub xpub)

instance FromCBOR (VerificationKey GenesisExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . GenesisExtendedVerificationKey)
             (Crypto.HD.xpub (bs :: ByteString))

instance ToCBOR (SigningKey GenesisExtendedKey) where
    toCBOR (GenesisExtendedSigningKey xprv) =
      toCBOR (Crypto.HD.unXPrv xprv)

instance FromCBOR (SigningKey GenesisExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . GenesisExtendedSigningKey)
             (Crypto.HD.xprv (bs :: ByteString))

instance SerialiseAsRawBytes (VerificationKey GenesisExtendedKey) where
    serialiseToRawBytes (GenesisExtendedVerificationKey xpub) =
      Crypto.HD.unXPub xpub

    deserialiseFromRawBytes (AsVerificationKey AsGenesisExtendedKey) bs =
      first (const (SerialiseAsRawBytesError "Unable to deserialise VerificationKey GenesisExtendedKey")) $
        GenesisExtendedVerificationKey<$> Crypto.HD.xpub bs

instance SerialiseAsRawBytes (SigningKey GenesisExtendedKey) where
    serialiseToRawBytes (GenesisExtendedSigningKey xprv) =
      Crypto.HD.unXPrv xprv

    deserialiseFromRawBytes (AsSigningKey AsGenesisExtendedKey) bs =
      first (\msg -> SerialiseAsRawBytesError ("Unable to deserialise SigningKey GenesisExtendedKey" ++ msg)) $
        GenesisExtendedSigningKey <$> Crypto.HD.xprv bs


newtype instance Hash GenesisExtendedKey =
    GenesisExtendedKeyHash (Shelley.KeyHash Shelley.Staking StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash GenesisExtendedKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash GenesisExtendedKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash GenesisExtendedKey) where
    serialiseToRawBytes (GenesisExtendedKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsGenesisExtendedKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash GenesisExtendedKey") $
        GenesisExtendedKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey GenesisExtendedKey) where
    textEnvelopeType _ = "GenesisExtendedVerificationKey_ed25519_bip32"

instance HasTextEnvelope (SigningKey GenesisExtendedKey) where
    textEnvelopeType _ = "GenesisExtendedSigningKey_ed25519_bip32"

instance CastVerificationKeyRole GenesisExtendedKey GenesisKey where
    castVerificationKey (GenesisExtendedVerificationKey vk) =
        GenesisVerificationKey
      . Shelley.VKey
      . fromMaybe impossible
      . Crypto.rawDeserialiseVerKeyDSIGN
      . Crypto.HD.xpubPublicKey
      $ vk
      where
        impossible =
          error "castVerificationKey: byron and shelley key sizes do not match!"


--
-- Genesis delegate keys
--

data GenesisDelegateKey

instance HasTypeProxy GenesisDelegateKey where
    data AsType GenesisDelegateKey = AsGenesisDelegateKey
    proxyToAsType _ = AsGenesisDelegateKey


instance Key GenesisDelegateKey where

    newtype VerificationKey GenesisDelegateKey =
        GenesisDelegateVerificationKey (Shelley.VKey Shelley.GenesisDelegate StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey GenesisDelegateKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey GenesisDelegateKey =
        GenesisDelegateSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey GenesisDelegateKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType GenesisDelegateKey -> Crypto.Seed -> SigningKey GenesisDelegateKey
    deterministicSigningKey AsGenesisDelegateKey seed =
        GenesisDelegateSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType GenesisDelegateKey -> Word
    deterministicSigningKeySeedSize AsGenesisDelegateKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey GenesisDelegateKey -> VerificationKey GenesisDelegateKey
    getVerificationKey (GenesisDelegateSigningKey sk) =
        GenesisDelegateVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey GenesisDelegateKey -> Hash GenesisDelegateKey
    verificationKeyHash (GenesisDelegateVerificationKey vkey) =
        GenesisDelegateKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey GenesisDelegateKey) where
    serialiseToRawBytes (GenesisDelegateVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsGenesisDelegateKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey GenesisDelegateKey") $
      GenesisDelegateVerificationKey . Shelley.VKey <$>
        Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey GenesisDelegateKey) where
    serialiseToRawBytes (GenesisDelegateSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsGenesisDelegateKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey GenesisDelegateKey") $
        GenesisDelegateSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs


newtype instance Hash GenesisDelegateKey =
    GenesisDelegateKeyHash (Shelley.KeyHash Shelley.GenesisDelegate StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash GenesisDelegateKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash GenesisDelegateKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash GenesisDelegateKey) where
    serialiseToRawBytes (GenesisDelegateKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsGenesisDelegateKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash GenesisDelegateKey") $
        GenesisDelegateKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey GenesisDelegateKey) where
    textEnvelopeType _ = "GenesisDelegateVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey GenesisDelegateKey) where
    textEnvelopeType _ = "GenesisDelegateSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance CastVerificationKeyRole GenesisDelegateKey StakePoolKey where
    castVerificationKey (GenesisDelegateVerificationKey (Shelley.VKey vkey)) =
      StakePoolVerificationKey (Shelley.VKey vkey)

instance CastSigningKeyRole GenesisDelegateKey StakePoolKey where
    castSigningKey (GenesisDelegateSigningKey skey) =
      StakePoolSigningKey skey

instance CastVerificationKeyRole StakePoolKey StakeKey where
    castVerificationKey (StakePoolVerificationKey (Shelley.VKey vkey)) =
      StakeVerificationKey (Shelley.VKey vkey)

--
-- Shelley genesis delegate extended ed25519 keys
--

-- | Shelley-era genesis keys using extended ed25519 cryptographic keys.
--
-- These serve the same role as normal genesis keys, but are here to support
-- legacy Byron genesis keys which used extended keys.
--
-- The extended verification keys can be converted (via 'castVerificationKey')
-- to ordinary keys (i.e. 'VerificationKey' 'GenesisKey') but this is /not/ the
-- case for the signing keys. The signing keys can be used to witness
-- transactions directly, with verification via their non-extended verification
-- key ('VerificationKey' 'GenesisKey').
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data GenesisDelegateExtendedKey

instance HasTypeProxy GenesisDelegateExtendedKey where
    data AsType GenesisDelegateExtendedKey = AsGenesisDelegateExtendedKey
    proxyToAsType _ = AsGenesisDelegateExtendedKey

instance Key GenesisDelegateExtendedKey where

    newtype VerificationKey GenesisDelegateExtendedKey =
        GenesisDelegateExtendedVerificationKey Crypto.HD.XPub
      deriving stock (Eq)
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey GenesisDelegateExtendedKey)

    newtype SigningKey GenesisDelegateExtendedKey =
        GenesisDelegateExtendedSigningKey Crypto.HD.XPrv
      deriving anyclass SerialiseAsCBOR
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey GenesisDelegateExtendedKey)

    deterministicSigningKey :: AsType GenesisDelegateExtendedKey
                            -> Crypto.Seed
                            -> SigningKey GenesisDelegateExtendedKey
    deterministicSigningKey AsGenesisDelegateExtendedKey seed =
        GenesisDelegateExtendedSigningKey
          (Crypto.HD.generate seedbs BS.empty)
      where
       (seedbs, _) = Crypto.getBytesFromSeedT 32 seed

    deterministicSigningKeySeedSize :: AsType GenesisDelegateExtendedKey -> Word
    deterministicSigningKeySeedSize AsGenesisDelegateExtendedKey = 32

    getVerificationKey :: SigningKey GenesisDelegateExtendedKey
                       -> VerificationKey GenesisDelegateExtendedKey
    getVerificationKey (GenesisDelegateExtendedSigningKey sk) =
        GenesisDelegateExtendedVerificationKey (Crypto.HD.toXPub sk)

    -- | We use the hash of the normal non-extended pub key so that it is
    -- consistent with the one used in addresses and signatures.
    --
    verificationKeyHash :: VerificationKey GenesisDelegateExtendedKey
                        -> Hash GenesisDelegateExtendedKey
    verificationKeyHash (GenesisDelegateExtendedVerificationKey vk) =
        GenesisDelegateExtendedKeyHash
      . Shelley.KeyHash
      . Crypto.castHash
      $ Crypto.hashWith Crypto.HD.xpubPublicKey vk


instance ToCBOR (VerificationKey GenesisDelegateExtendedKey) where
    toCBOR (GenesisDelegateExtendedVerificationKey xpub) =
      toCBOR (Crypto.HD.unXPub xpub)

instance FromCBOR (VerificationKey GenesisDelegateExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . GenesisDelegateExtendedVerificationKey)
             (Crypto.HD.xpub (bs :: ByteString))

instance ToCBOR (SigningKey GenesisDelegateExtendedKey) where
    toCBOR (GenesisDelegateExtendedSigningKey xprv) =
      toCBOR (Crypto.HD.unXPrv xprv)

instance FromCBOR (SigningKey GenesisDelegateExtendedKey) where
    fromCBOR = do
      bs <- fromCBOR
      either fail (return . GenesisDelegateExtendedSigningKey)
             (Crypto.HD.xprv (bs :: ByteString))

instance SerialiseAsRawBytes (VerificationKey GenesisDelegateExtendedKey) where
    serialiseToRawBytes (GenesisDelegateExtendedVerificationKey xpub) =
      Crypto.HD.unXPub xpub

    deserialiseFromRawBytes (AsVerificationKey AsGenesisDelegateExtendedKey) bs =
      first (\msg -> SerialiseAsRawBytesError ("Unable to deserialise VerificationKey GenesisDelegateExtendedKey: " ++ msg)) $
        GenesisDelegateExtendedVerificationKey <$> Crypto.HD.xpub bs

instance SerialiseAsRawBytes (SigningKey GenesisDelegateExtendedKey) where
    serialiseToRawBytes (GenesisDelegateExtendedSigningKey xprv) =
      Crypto.HD.unXPrv xprv

    deserialiseFromRawBytes (AsSigningKey AsGenesisDelegateExtendedKey) bs =
      first (\msg -> SerialiseAsRawBytesError ("Unable to deserialise SigningKey GenesisDelegateExtendedKey: " ++ msg)) $
        GenesisDelegateExtendedSigningKey <$> Crypto.HD.xprv bs


newtype instance Hash GenesisDelegateExtendedKey =
    GenesisDelegateExtendedKeyHash (Shelley.KeyHash Shelley.Staking StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash GenesisDelegateExtendedKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash GenesisDelegateExtendedKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash GenesisDelegateExtendedKey) where
    serialiseToRawBytes (GenesisDelegateExtendedKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsGenesisDelegateExtendedKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash GenesisDelegateExtendedKey: ") $
        GenesisDelegateExtendedKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey GenesisDelegateExtendedKey) where
    textEnvelopeType _ = "GenesisDelegateExtendedVerificationKey_ed25519_bip32"

instance HasTextEnvelope (SigningKey GenesisDelegateExtendedKey) where
    textEnvelopeType _ = "GenesisDelegateExtendedSigningKey_ed25519_bip32"

instance CastVerificationKeyRole GenesisDelegateExtendedKey GenesisDelegateKey where
    castVerificationKey (GenesisDelegateExtendedVerificationKey vk) =
        GenesisDelegateVerificationKey
      . Shelley.VKey
      . fromMaybe impossible
      . Crypto.rawDeserialiseVerKeyDSIGN
      . Crypto.HD.xpubPublicKey
      $ vk
      where
        impossible =
          error "castVerificationKey: byron and shelley key sizes do not match!"


--
-- Genesis UTxO keys
--

data GenesisUTxOKey

instance HasTypeProxy GenesisUTxOKey where
    data AsType GenesisUTxOKey = AsGenesisUTxOKey
    proxyToAsType _ = AsGenesisUTxOKey


instance Key GenesisUTxOKey where

    newtype VerificationKey GenesisUTxOKey =
        GenesisUTxOVerificationKey (Shelley.VKey Shelley.Payment StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey GenesisUTxOKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey GenesisUTxOKey =
        GenesisUTxOSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey GenesisUTxOKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType GenesisUTxOKey -> Crypto.Seed -> SigningKey GenesisUTxOKey
    deterministicSigningKey AsGenesisUTxOKey seed =
        GenesisUTxOSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType GenesisUTxOKey -> Word
    deterministicSigningKeySeedSize AsGenesisUTxOKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey GenesisUTxOKey -> VerificationKey GenesisUTxOKey
    getVerificationKey (GenesisUTxOSigningKey sk) =
        GenesisUTxOVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey GenesisUTxOKey -> Hash GenesisUTxOKey
    verificationKeyHash (GenesisUTxOVerificationKey vkey) =
        GenesisUTxOKeyHash (Shelley.hashKey vkey)


instance SerialiseAsRawBytes (VerificationKey GenesisUTxOKey) where
    serialiseToRawBytes (GenesisUTxOVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsGenesisUTxOKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Enable to deserialise VerificationKey GenesisUTxOKey") $
        GenesisUTxOVerificationKey . Shelley.VKey <$> Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey GenesisUTxOKey) where
    serialiseToRawBytes (GenesisUTxOSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsGenesisUTxOKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise SigningKey GenesisUTxOKey") $
        GenesisUTxOSigningKey <$> Crypto.rawDeserialiseSignKeyDSIGN bs


newtype instance Hash GenesisUTxOKey =
    GenesisUTxOKeyHash (Shelley.KeyHash Shelley.Payment StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash GenesisUTxOKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash GenesisUTxOKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash GenesisUTxOKey) where
    serialiseToRawBytes (GenesisUTxOKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsGenesisUTxOKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise Hash GenesisUTxOKey") $
        GenesisUTxOKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs

instance HasTextEnvelope (VerificationKey GenesisUTxOKey) where
    textEnvelopeType _ = "GenesisUTxOVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey GenesisUTxOKey) where
    textEnvelopeType _ = "GenesisUTxOSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy
    -- TODO: use a different type from the stake pool key, since some operations
    -- need a genesis key specifically

instance CastVerificationKeyRole GenesisUTxOKey PaymentKey where
    castVerificationKey (GenesisUTxOVerificationKey (Shelley.VKey vkey)) =
      PaymentVerificationKey (Shelley.VKey vkey)

instance CastSigningKeyRole GenesisUTxOKey PaymentKey where
    castSigningKey (GenesisUTxOSigningKey skey) =
      PaymentSigningKey skey


--
-- stake pool keys
--

data StakePoolKey

instance HasTypeProxy StakePoolKey where
    data AsType StakePoolKey = AsStakePoolKey
    proxyToAsType _ = AsStakePoolKey

instance Key StakePoolKey where

    newtype VerificationKey StakePoolKey =
        StakePoolVerificationKey (Shelley.VKey Shelley.StakePool StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey StakePoolKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey StakePoolKey =
        StakePoolSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey StakePoolKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType StakePoolKey -> Crypto.Seed -> SigningKey StakePoolKey
    deterministicSigningKey AsStakePoolKey seed =
        StakePoolSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType StakePoolKey -> Word
    deterministicSigningKeySeedSize AsStakePoolKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey StakePoolKey -> VerificationKey StakePoolKey
    getVerificationKey (StakePoolSigningKey sk) =
        StakePoolVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey StakePoolKey -> Hash StakePoolKey
    verificationKeyHash (StakePoolVerificationKey vkey) =
        StakePoolKeyHash (Shelley.hashKey vkey)

instance SerialiseAsRawBytes (VerificationKey StakePoolKey) where
    serialiseToRawBytes (StakePoolVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsStakePoolKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey StakePoolKey") $
        StakePoolVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey StakePoolKey) where
    serialiseToRawBytes (StakePoolSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsStakePoolKey) bs =
      maybe
        (Left (SerialiseAsRawBytesError "Unable to deserialise SigningKey StakePoolKey"))
        (Right . StakePoolSigningKey)
        (Crypto.rawDeserialiseSignKeyDSIGN bs)

instance SerialiseAsBech32 (VerificationKey StakePoolKey) where
    bech32PrefixFor         _ =  "pool_vk"
    bech32PrefixesPermitted _ = ["pool_vk"]

instance SerialiseAsBech32 (SigningKey StakePoolKey) where
    bech32PrefixFor         _ =  "pool_sk"
    bech32PrefixesPermitted _ = ["pool_sk"]

newtype instance Hash StakePoolKey =
    StakePoolKeyHash { unStakePoolKeyHash :: Shelley.KeyHash Shelley.StakePool StandardCrypto }
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash StakePoolKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash StakePoolKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash StakePoolKey) where
    serialiseToRawBytes (StakePoolKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsStakePoolKey) bs =
      maybeToRight
        (SerialiseAsRawBytesError "Unable to deserialise Hash StakePoolKey")
        (StakePoolKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs)

instance SerialiseAsBech32 (Hash StakePoolKey) where
    bech32PrefixFor         _ =  "pool"
    bech32PrefixesPermitted _ = ["pool"]

instance ToJSON (Hash StakePoolKey) where
    toJSON = toJSON . serialiseToBech32

instance ToJSONKey (Hash StakePoolKey) where
  toJSONKey = toJSONKeyText serialiseToBech32

instance FromJSON (Hash StakePoolKey) where
  parseJSON = withText "PoolId" $ \str ->
    case deserialiseFromBech32 (AsHash AsStakePoolKey) str of
      Left err ->
        fail $ "Error deserialising Hash StakePoolKey: " <> Text.unpack str <>
               " Error: " <> displayError err
      Right h -> pure h

instance HasTextEnvelope (VerificationKey StakePoolKey) where
    textEnvelopeType _ = "StakePoolVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey StakePoolKey) where
    textEnvelopeType _ = "StakePoolSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

--
-- DRep keys
--

data DRepKey

instance HasTypeProxy DRepKey where
    data AsType DRepKey = AsDRepKey
    proxyToAsType _ = AsDRepKey

instance Key DRepKey where

    newtype VerificationKey DRepKey =
        DRepVerificationKey (Shelley.VKey Shelley.Voting StandardCrypto)
      deriving stock (Eq)
      deriving (Show, IsString) via UsingRawBytesHex (VerificationKey DRepKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    newtype SigningKey DRepKey =
        DRepSigningKey (Shelley.SignKeyDSIGN StandardCrypto)
      deriving (Show, IsString) via UsingRawBytesHex (SigningKey DRepKey)
      deriving newtype (ToCBOR, FromCBOR)
      deriving anyclass SerialiseAsCBOR

    deterministicSigningKey :: AsType DRepKey -> Crypto.Seed -> SigningKey DRepKey
    deterministicSigningKey AsDRepKey seed =
        DRepSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType DRepKey -> Word
    deterministicSigningKeySeedSize AsDRepKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey DRepKey -> VerificationKey DRepKey
    getVerificationKey (DRepSigningKey sk) =
        DRepVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

    verificationKeyHash :: VerificationKey DRepKey -> Hash DRepKey
    verificationKeyHash (DRepVerificationKey vkey) =
        DRepKeyHash (Shelley.hashKey vkey)

instance SerialiseAsRawBytes (VerificationKey DRepKey) where
    serialiseToRawBytes (DRepVerificationKey (Shelley.VKey vk)) =
      Crypto.rawSerialiseVerKeyDSIGN vk

    deserialiseFromRawBytes (AsVerificationKey AsDRepKey) bs =
      maybeToRight (SerialiseAsRawBytesError "Unable to deserialise VerificationKey DRepKey") $
        DRepVerificationKey . Shelley.VKey <$>
          Crypto.rawDeserialiseVerKeyDSIGN bs

instance SerialiseAsRawBytes (SigningKey DRepKey) where
    serialiseToRawBytes (DRepSigningKey sk) =
      Crypto.rawSerialiseSignKeyDSIGN sk

    deserialiseFromRawBytes (AsSigningKey AsDRepKey) bs =
      maybe
        (Left (SerialiseAsRawBytesError "Unable to deserialise SigningKey DRepKey"))
        (Right . DRepSigningKey)
        (Crypto.rawDeserialiseSignKeyDSIGN bs)

instance SerialiseAsBech32 (VerificationKey DRepKey) where
    bech32PrefixFor         _ =  "drep_vk"
    bech32PrefixesPermitted _ = ["drep_vk"]

instance SerialiseAsBech32 (SigningKey DRepKey) where
    bech32PrefixFor         _ =  "drep_sk"
    bech32PrefixesPermitted _ = ["drep_sk"]

newtype instance Hash DRepKey =
    DRepKeyHash { unDRepKeyHash :: Shelley.KeyHash Shelley.Voting StandardCrypto }
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex (Hash DRepKey)
  deriving (ToCBOR, FromCBOR) via UsingRawBytes (Hash DRepKey)
  deriving anyclass SerialiseAsCBOR

instance SerialiseAsRawBytes (Hash DRepKey) where
    serialiseToRawBytes (DRepKeyHash (Shelley.KeyHash vkh)) =
      Crypto.hashToBytes vkh

    deserialiseFromRawBytes (AsHash AsDRepKey) bs =
      maybeToRight
        (SerialiseAsRawBytesError "Unable to deserialise Hash DRepKey")
        (DRepKeyHash . Shelley.KeyHash <$> Crypto.hashFromBytes bs)

instance SerialiseAsBech32 (Hash DRepKey) where
    bech32PrefixFor         _ =  "drep"
    bech32PrefixesPermitted _ = ["drep"]

instance ToJSON (Hash DRepKey) where
    toJSON = toJSON . serialiseToBech32

instance ToJSONKey (Hash DRepKey) where
  toJSONKey = toJSONKeyText serialiseToBech32

instance FromJSON (Hash DRepKey) where
  parseJSON = withText "DRepId" $ \str ->
    case deserialiseFromBech32 (AsHash AsDRepKey) str of
      Left err ->
        fail $ "Error deserialising Hash DRepKey: " <> Text.unpack str <>
               " Error: " <> displayError err
      Right h -> pure h

instance HasTextEnvelope (VerificationKey DRepKey) where
    textEnvelopeType _ = "DRepVerificationKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey DRepKey) where
    textEnvelopeType _ = "DRepSigningKey_"
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN StandardCrypto)
        proxy = Proxy

--
-- Committee keys
--


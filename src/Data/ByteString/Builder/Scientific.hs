{-# LANGUAGE CPP, MagicHash, OverloadedStrings #-}

module Data.ByteString.Builder.Scientific
    ( scientificBuilder
    , formatScientificBuilder
    , FPFormat(..)
    ) where

import           Data.Scientific   (Scientific,SciencificDisplay(..))
import qualified Data.Scientific as Scientific

import Data.Text.Lazy.Builder.RealFloat (FPFormat(..))

import qualified Data.ByteString.Char8 as BC8

#if !MIN_VERSION_bytestring(0,10,2)
import           Data.ByteString.Lazy.Builder (Builder, string8, char8)
import           Data.ByteString.Lazy.Builder.ASCII (intDec)
import           Data.ByteString.Lazy.Builder.Extras (byteStringCopy)
#else
import           Data.ByteString.Builder (Builder, string8, char8, intDec)
import           Data.ByteString.Builder.Extra (byteStringCopy)
#endif

import GHC.Base                     (Int(I#), Char(C#), chr#, ord#, (+#))
import Data.Monoid                  (mempty)
#if MIN_VERSION_base(4,5,0)
import Data.Monoid                  ((<>))
#else
import Data.Monoid                  (Monoid, mappend)
(<>) :: Monoid a => a -> a -> a
(<>) = mappend
infixr 6 <>
#endif

-- | A @ByteString@ @Builder@ which renders a scientific number to full
-- precision, using standard decimal notation for arguments whose
-- absolute value lies between @0.1@ and @9,999,999@, and scientific
-- notation otherwise.
scientificBuilder :: Scientific -> Builder
scientificBuilder scntfc
  | Scientific.displayMode scntfc == ScDisplayInt = formatIntBuilder scntfc
  | otherwise   = formatScientificBuilder (mode $ Scientific.displayMode scntfc) Nothing scntfc
    where mode ScDisplayInt = Fixed -- not used for completeness
          mode ScDisplayFixed = Fixed
          mode ScDisplayGeneric = Generic
          mode ScDisplayExponent = Exponent

formatIntBuilder :: Scientific
  -> Builder
formatIntBuilder scntfc
   | scntfc < 0 = char8 '-' <> doFmt (Scientific.toDecimalDigits (-scntfc))
   | otherwise  =              doFmt (Scientific.toDecimalDigits   scntfc )
  where
    doFmt :: ([Int], Int) -> Builder
    doFmt (is, e)
      | e <= 0  = char8 '0'
      | otherwise = string8 (map i2d $ take e is) <> string8 (replicate (e - length is) '0')

-- | Like 'scientificBuilder' but provides rendering options.
formatScientificBuilder :: FPFormat
                        -> Maybe Int  -- ^ Number of decimal places to render.
                        -> Scientific
                        -> Builder
formatScientificBuilder fmt decs scntfc
   | scntfc < 0 = char8 '-' <> doFmt fmt (Scientific.toDecimalDigits (-scntfc))
   | otherwise  =              doFmt fmt (Scientific.toDecimalDigits   scntfc)
 where
  doFmt format (is, e) =
    let ds = map i2d is in
    case format of
     Generic ->
      doFmt (if e < 0 || e > 7 then Exponent else Fixed)
            (is,e)
     Exponent ->
      case decs of
       Nothing ->
        let show_e' = intDec (e-1) in
        case ds of
          "0"     -> byteStringCopy "0.0e0"
          [d]     -> char8 d <> byteStringCopy ".0e" <> show_e'
          (d:ds') -> char8 d <> char8 '.' <> string8 ds' <> char8 'e' <> show_e'
          []      -> error $ "Data.ByteString.Builder.Scientific.formatScientificBuilder" ++
                             "/doFmt/Exponent: []"
       Just dec ->
        let dec' = max dec 1 in
        case is of
         [0] -> byteStringCopy "0." <>
                byteStringCopy (BC8.replicate dec' '0') <>
                byteStringCopy "e0"
         _ ->
          let
           (ei,is') = roundTo (dec'+1) is
           (d:ds') = map i2d (if ei > 0 then init is' else is')
          in
          char8 d <> char8 '.' <> string8 ds' <> char8 'e' <> intDec (e-1+ei)
     Fixed ->
      let
       mk0 ls = case ls of { "" -> char8 '0' ; _ -> string8 ls}
      in
      case decs of
       Nothing
          | e <= 0    -> byteStringCopy "0." <>
                         byteStringCopy (BC8.replicate (-e) '0') <>
                         string8 ds
          | otherwise ->
             let
                f 0 s    rs  = mk0 (reverse s) <> char8 '.' <> mk0 rs
                f n s    ""  = f (n-1) ('0':s) ""
                f n s (r:rs) = f (n-1) (r:s) rs
             in
                f e "" ds
       Just dec ->
        let dec' = max dec 0 in
        if e >= 0 then
         let
          (ei,is') = roundTo (dec' + e) is
          (ls,rs)  = splitAt (e+ei) (map i2d is')
         in
         mk0 ls <> (if null rs then mempty else char8 '.' <> string8 rs)
        else
         let
          (ei,is') = roundTo dec' (replicate (-e) 0 ++ is)
          d:ds' = map i2d (if ei > 0 then is' else 0:is')
         in
         char8 d <> (if null ds' then mempty else char8 '.' <> string8 ds')

-- | Unsafe conversion for decimal digits.
{-# INLINE i2d #-}
i2d :: Int -> Char
i2d (I# i#) = C# (chr# (ord# '0'# +# i#))

roundTo :: Int -> [Int] -> (Int,[Int])
roundTo d is =
  case f d True is of
    x@(0,_) -> x
    (1,xs)  -> (1, 1:xs)
    _       -> error "roundTo: bad Value"
 where
  base = 10

  b2 = base `quot` 2

  f n _ []     = (0, replicate n 0)
  f 0 e (x:xs) | x == b2 && e && all (== 0) xs = (0, [])   -- Round to even when at exactly half the base
               | otherwise = (if x >= b2 then 1 else 0, [])
  f n _ (i:xs)
     | i' == base = (1,0:ds)
     | otherwise  = (0,i':ds)
      where
       (c,ds) = f (n-1) (even i) xs
       i'     = c + i

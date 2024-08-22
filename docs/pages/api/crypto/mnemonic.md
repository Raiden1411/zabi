## english
Wordlist of valid english mnemonic words.

## EntropyArray
The array of entropy bytes of an mnemonic passphrase
Compilation will fail if the count is not 12/15/18/21/24

## MnemonicToSeed
Converts a mnemonic passphrase into a hashed seed that
can be used later for HDWallets.\
Uses `pbkdf2` for the hashing with `HmacSha512` for the
pseudo random function to use

## ToEntropy
Converts the mnemonic phrase into it's entropy representation.

## FromEntropy

## Wordlist
The word lists that are valid for mnemonic passphrases.

## LoadRawList
Loads word in it's raw format and parses it.\
It expects that the string is seperated by "\n"

## GetIndex
Performs binary search on the word list
as we assume that the list is alphabetically ordered.\
Returns null if the word isn't on the list


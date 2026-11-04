`hardnested-filtering.bin` contains 1,772 synthetic encrypted nonces that
reproduce the filtering failure observed with sector 13 Key A of an EV1 card.
It uses the recovery engine's format: a four-byte UID, target block and key
type, followed by nine-byte records containing two encrypted nonces and their
packed parity bits. It contains no real card credentials or memory blocks.

The synthetic key is `405044544951` (initial Crypto1 registers: odd `000040`,
even `13579B`), with UID `11223344`. Nonces use successive 32-bit outputs from
Python's `random.Random(0xC1A551C)`, stopping after a pair covers the last unseen
encrypted first byte. Each plaintext byte is encrypted using Crypto1 with the
corresponding UID byte XORed into its input; parity is plaintext odd parity
XOR the next keystream bit, without advancing the cipher for parity.

The unmodified engine returns zero because it applies nearly full bitflip
tables that should be ignored: it uses the decompressed byte length instead
of the state count in the first word. The corrected engine recovers the key.

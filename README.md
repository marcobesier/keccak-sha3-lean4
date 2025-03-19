# Keccak/SHA3 Implementation in Lean 4

This repository contains a Lean 4 implementation of the Keccak and SHA3 hash functions. The implementation is based on the following [Lean 3 implementation](https://github.com/argumentcomputer/Ipld.lean/blob/main/Ipld/Keccak.lean).

## Available Functions

- `keccak224`, `keccak256`, `keccak384`, `keccak512`
- `sha3_224`, `sha3_256`, `sha3_384`, `sha3_512`
- `shake128`, `shake256`

## Testing

Since the "Ethereum-like" `keccak256` was the main motivation for creating this repo, it is the only hash function that comes with some tests.
After cloning the repo, you can run these tests via:

```bash
lake build
lake env lean TestKeccak256.lean
```

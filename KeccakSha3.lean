/-
Keccak/SHA3 hash functions in Lean 4, based on the following Lean 3 implementation:
https://github.com/argumentcomputer/Ipld.lean/blob/main/Ipld/Keccak.lean
-/

namespace UInt64

def rotateLOnce (word : UInt64) : UInt64 :=
  (word <<< 1) ||| (word >>> 63)

def rotateL : UInt64 → Nat → UInt64
  | word, n + 1 => (rotateLOnce word).rotateL n
  | word, 0     => word

end UInt64

namespace ByteArray

def toArrayUInt64LE (bytes : ByteArray) : Array UInt64 :=
  let push_word := fun (pos, word, arr) byte =>
    if pos < 7
    then
      let word := word + (byte.toUInt64 <<< (8*pos))
      (pos + 1, word, arr)
    else
      let word := word + (byte.toUInt64 <<< (8*pos))
      let arr := arr.push word
      (0, 0, arr)
  let pos : UInt64 := 0
  let word : UInt64 := 0
  let (pos, word, arr) := bytes.foldl push_word (pos, word, #[])
  if pos == 0
  then arr
  else arr.push word

def fromArrayUInt64LE (arr : Array UInt64) : ByteArray :=
  let push_word := fun bytes word =>
    let bytes := bytes.push $ UInt64.toUInt8 word
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x8
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x10
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x18
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x20
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x28
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x30
    let bytes := bytes.push $ UInt64.toUInt8 $ word >>> 0x38
    bytes
  arr.foldl push_word ByteArray.empty

end ByteArray

namespace Keccak

def rounds : Nat :=
  24

def numLanes : Nat :=
  25

def laneWidth : Nat :=
  64

def emptyState : Array UInt64 :=
  mkArray numLanes 0

----------------------------------------------------
-- Constants used in KeccakF[1600] permutation
----------------------------------------------------

def roundConstants : Array UInt64 :=
  #[0x0000000000000001, 0x0000000000008082, 0x800000000000808A,
    0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009, 0x000000000000008A,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
    0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
    0x000000000000800A, 0x800000008000000A, 0x8000000080008081,
    0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

def rotationConstants : Array Nat :=
  #[0, 36,  3, 41, 18,
    1, 44, 10, 45,  2,
    62,  6, 43, 15, 61,
    28, 55, 25, 21, 56,
    27, 20, 39,  8, 14]

def piConstants : Array Nat :=
  #[0, 15, 5, 20, 10,
    6, 21, 11, 1, 16,
    12, 2, 17, 7, 22,
    18, 8, 23, 13, 3,
    24, 14, 4, 19, 9]

def theta (state : Array UInt64) : Array UInt64 :=
  let b : Array UInt64 := Array.mkArray 5 0
  let c := b.mapIdx fun i _ =>
    state[i * 5]!.xor $
      state[i * 5 + 1]!.xor $
        state[i * 5 + 2]!.xor $
          state[i * 5 + 3]!.xor state[i * 5 + 4]!
  let d := b.mapIdx fun i _ => (i, c[Nat.mod (i + 4) 5]!.xor (c[Nat.mod (i + 1) 5]!.rotateL 1))
  d.flatMap fun (i, e) =>
    #[e.xor state[i * 5]!,
      e.xor state[i * 5 + 1]!,
      e.xor state[i * 5 + 2]!,
      e.xor state[i * 5 + 3]!,
      e.xor state[i * 5 + 4]!]

def rho (state : Array UInt64) : Array UInt64 :=
  state.mapIdx fun i val =>
    UInt64.rotateL val rotationConstants[i]!

def pi (state : Array UInt64) : Array UInt64 :=
  piConstants.map fun i => state[i]!

def chi (b : Array UInt64) : Array UInt64 :=
  b.mapIdx fun z el => UInt64.xor el (UInt64.land (UInt64.complement b[Nat.mod (z + 5) 25]!) b[Nat.mod (z + 10) 25]!)

def iota (roundNumber : Nat) (state : Array UInt64) : Array UInt64 :=
  state.modify 0 (fun val => UInt64.xor roundConstants[roundNumber]! val)

def keccakFAux : Nat → Nat → Array UInt64 → (Nat × Array UInt64)
| 0,     r, s => (r, s)
| n + 1, r, s => keccakFAux n (r + 1) (iota r $ chi $ pi $ rho $ theta s)

def keccakF (state : Array UInt64) : Array UInt64 :=
  let (_, state') := keccakFAux rounds 0 state
  state'

def squeeze (rate : Nat) (l : Nat) (state : Array UInt64) : ByteArray :=
  let lanesToExtract := Nat.div l (Nat.div laneWidth 8)
  let threshold := Nat.div rate laneWidth
  let rec stateToBytes : Nat → Nat → Nat → Array UInt64 → List UInt64
  | 0,     _,    _, _ => []
  | n + 1, rate, x, s =>
    if x < threshold
    then s[(x / 5) + (x % 5) * 5]! :: stateToBytes n rate (x + 1) s
    else stateToBytes n rate 0 (keccakF s)
  ByteArray.fromArrayUInt64LE (Array.mk (stateToBytes lanesToExtract threshold 0 state))

partial def absorbBlock (rate : Nat) (state : Array UInt64) (input : Array UInt64) : Array UInt64 :=
  if input.isEmpty
  then state
  else
    let threshold := Nat.div rate laneWidth
    let state' := state.mapIdx fun z el =>
      if (z / 5) + 5*(z % 5) < threshold
      then UInt64.xor el input[(z / 5) + 5*(z % 5)]!
      else el
    let input' := input.extract threshold input.size
    absorbBlock rate (keccakF state') input'

def absorb (rate : Nat) (bytes : ByteArray) : Array UInt64 :=
  absorbBlock rate emptyState (ByteArray.toArrayUInt64LE bytes)

-- | Multi-rate padding appends at least 2 bits and at most the number of bits
-- in a block plus one.
def multiratePadding (bitrateBytes : Nat) (padByte : UInt8) (input : ByteArray) : ByteArray :=
  let msglen := input.size
  let padlen := bitrateBytes - Nat.mod input.size bitrateBytes
  let totalLength := padlen + msglen

  let data := Array.mkArray totalLength 0
  let data := data.mapIdx fun idx _ =>
    if idx < msglen then input[idx]!
    else if (idx + 1) == totalLength && padlen == 1 then 0x80 ||| padByte
    else if (idx + 1) == totalLength then 0x80
    else if idx == msglen then padByte
    else 0x00

  ByteArray.mk data

def paddingKeccak (bitrateBytes : Nat) : ByteArray → ByteArray :=
  multiratePadding bitrateBytes 0x01

def paddingSha3 (bitrateBytes : Nat) : ByteArray → ByteArray :=
  multiratePadding bitrateBytes 0x06

def paddingShake (bitrateBytes : Nat) : ByteArray → ByteArray :=
  multiratePadding bitrateBytes 0x1F

def shakeFunction (paddingFunction : Nat → ByteArray → ByteArray) (rate : Nat) (outputBytes : Nat) : ByteArray → ByteArray :=
  squeeze rate outputBytes ∘ absorb rate ∘ paddingFunction (Nat.div rate 8)

-- | SHAKE128 (128 bit security level) cryptographic extendable-output function
def shake128 (outputBits : Nat) : ByteArray → ByteArray :=
  shakeFunction paddingShake 1344 (Nat.div outputBits 8)

-- | SHAKE256 (256 bit security level) cryptographic extendable-output function
def shake256 (outputBits : Nat) : ByteArray → ByteArray :=
  shakeFunction paddingShake 1088 (Nat.div outputBits 8)

def hashFunction (paddingFunction : Nat → ByteArray → ByteArray) (rate : Nat) : ByteArray → ByteArray :=
  let outputBytes := Nat.div (1600 - rate) 16
  squeeze rate outputBytes ∘ absorb rate ∘ paddingFunction (Nat.div rate 8)

-- | Given a bitrate @r@, returns a standard Keccak hash with state width @w@ = 1600 and
-- capacity = 1600 - @r@
def keccakHash : Nat → ByteArray → ByteArray :=
  hashFunction paddingKeccak

-- | Given a bitrate @r@, returns a standard SHA3 hash with state width @w@ = 1600 and
-- capacity = 1600 - @r@
def sha3Hash : Nat → ByteArray → ByteArray :=
  hashFunction paddingSha3

-- | Keccak (512 bits) cryptographic hash algorithm
def keccak512 : ByteArray → ByteArray :=
  keccakHash 576

-- | Keccak (384 bits) cryptographic hash algorithm
def keccak384 : ByteArray → ByteArray :=
  keccakHash 832

-- | Keccak (256 bits) cryptographic hash algorithm
def keccak256 : ByteArray → ByteArray :=
  keccakHash 1088

-- | Keccak (224 bits) cryptographic hash algorithm
def keccak224 : ByteArray → ByteArray :=
  keccakHash 1152

-- | SHA3 (512 bits) cryptographic hash algorithm
def sha3_512 : ByteArray → ByteArray :=
  sha3Hash 576

-- | SHA3 (384 bits) cryptographic hash algorithm
def sha3_384 : ByteArray → ByteArray :=
  sha3Hash 832

-- | SHA3 (256 bits) cryptographic hash algorithm
def sha3_256 : ByteArray → ByteArray :=
  sha3Hash 1088

-- | SHA3 (224 bits) cryptographic hash algorithm
def sha3_224 : ByteArray → ByteArray :=
  sha3Hash 1152

end Keccak

import KeccakSha3

def byteToHex (b : UInt8) : String :=
  let digits := "0123456789abcdef"
  let hi := (b.toNat >>> 4) % 16
  let lo := b.toNat % 16
  String.mk [digits.get! ⟨hi⟩, digits.get! ⟨lo⟩]

def ByteArray.toHex (ba : ByteArray) : String :=
  String.intercalate "" ((ba.data.map byteToHex).toList)

def testCase (name : String) (input : String) (expected : String) : IO Unit := do
  let inputBytes := input.toUTF8
  let hash := Keccak.keccak256 inputBytes
  let hashHex := hash.toHex

  IO.println s!"Test: {name}"
  IO.println s!"Input: \"{input}\""
  IO.println s!"Computed hash: {hashHex}"
  IO.println s!"Expected hash: {expected}"

  if hashHex == expected then
    IO.println "✅ PASS"
  else
    IO.println "❌ FAIL"

  IO.println ""

def runTests : IO Unit := do

  IO.println ""

  -- Test with empty string
  testCase "Empty string" "" "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

  -- Test with "hello world"
  testCase "hello world" "hello world" "47173285a8d7341e5e972fc677286384f802f8ef42a5ec5f03bbfa254cb01fad"

  -- Test with "abc"
  testCase "abc" "abc" "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"

  -- Test with The Dude
  testCase "The Dude" "Obviously you're not a golfer" "c825e610508c2ea76fb4c7f33db82b1b381b81b14a5ee7157dd4c005d657fa89"

def main : IO Unit :=
  runTests

#eval main

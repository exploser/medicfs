binary = {}

-- convert a 32-bit two's complement integer into a four bytes (network order)
function binary.int2bytes(n)
  if n > 2147483647 then error(n.." is too large",2) end
  if n < -2147483648 then error(n.." is too small",2) end
  -- adjust for 2's complement
  n = (n < 0) and (4294967296 + n) or n
  return (math.modf(n/16777216))%256, (math.modf(n/65536))%256, (math.modf(n/256))%256, n%256
end

-- convert bytes (network order) to a 32-bit two's complement integer
function binary.bytes2int(b1, b2, b3, b4)
  if not b4 then error("need four bytes to convert to int",2) end
  local n = b1*16777216 + b2*65536 + b3*256 + b4
  n = (n > 2147483647) and (n - 4294967296) or n
  return n
end

function binary.readBinaryInt(address)
  local b1 = string.byte(component.invoke(address, "read", 1))
  local b2 = string.byte(component.invoke(address, "read", 1))
  local b3 = string.byte(component.invoke(address, "read", 1))
  local b4 = string.byte(component.invoke(address, "read", 1))
  return bytes_to_int(b1, b2, b3, b4)
end

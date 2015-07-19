local binary = require("binarytape")
formatter = {}



function formatter.format(address)
  local offset = 0
  -- rewind
  component.invoke(address, "seek", -math.huge)
  -- write header start
  component.invoke(address, "write", "M001")
  offset = offset + 4
  
  -- write hello world file
  -- file name length
  component.invoke(address, "write", string.char(12))
  offset = offset + 1
  -- file name
  component.invoke(address, "write", "hello world!")
  offset = offset + 12
  -- file offset
  local b1, b2, b3, b4 = binary.int2bytes(offset+13)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file length
  local b1, b2, b3, b4 = binary.int2bytes(11)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file type
  component.invoke(address, "write", "\3")
  
  -- write second hello world file
  -- file name length
  component.invoke(address, "write", string.char(9))
  offset = offset + 1
  -- file name
  component.invoke(address, "write", "testfile2")
  offset = offset + 12
  -- file offset
  local b1, b2, b3, b4 = binary.int2bytes(256)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file length
  local b1, b2, b3, b4 = binary.int2bytes(17)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file type
  component.invoke(address, "write", "\3")
  
  -- write end of directory
  component.invoke(address, "write", "\0")
  offset = offset + 1
  -- write end of filesystem
  component.invoke(address, "write", "BYE")
  offset = offset + 3
  -- file contents
  component.invoke(address, "write", "sosi chlen!")
  -- rewind
  component.invoke(address, "seek", -math.huge)
  
  
  -- rewind
  component.invoke(address, "seek", -math.huge)
  component.invoke(address, "seek", 256)
  -- file contents
  component.invoke(address, "write", "second test file!")
  -- rewind
  component.invoke(address, "seek", -math.huge)
end

-- MEDIC: a multiMEdia DIgital Cassette file system
local medic = {}
local proxy = {}
local filedescr = {}
local filetable = {}
local component = require("component")
local fs = require("filesystem")
local io = require("io")
local term = require("term")

-- convert a 32-bit two's complement integer into a four bytes (network order)
local function int_to_bytes(n)
  if n > 2147483647 then error(n.." is too large",2) end
  if n < -2147483648 then error(n.." is too small",2) end
  -- adjust for 2's complement
  n = (n < 0) and (4294967296 + n) or n
  return (math.modf(n/16777216))%256, (math.modf(n/65536))%256, (math.modf(n/256))%256, n%256
end

-- convert bytes (network order) to a 32-bit two's complement integer
local function bytes_to_int(b1, b2, b3, b4)
  if not b4 then error("need four bytes to convert to int",2) end
  local n = b1*16777216 + b2*65536 + b3*256 + b4
  n = (n > 2147483647) and (n - 4294967296) or n
  return n
end

local function readBinaryInt(address)
  local b1 = string.byte(component.invoke(address, "read", 1))
  local b2 = string.byte(component.invoke(address, "read", 1))
  local b3 = string.byte(component.invoke(address, "read", 1))
  local b4 = string.byte(component.invoke(address, "read", 1))
  return bytes_to_int(b1, b2, b3, b4)
end

local fileTypes = {
  "music", -- 1
  "rawdata", -- 2
  "text", -- 3
  "special" -- 4
}

-- get proxy
function medic.proxy(address)
  
  component.invoke(address, "seek", -math.huge)
  
  local signature = component.invoke(address, "read", 4)
  if signature ~= "M001" then
    return nil, "unformatted media"
  end
  
  term.write("reading medicfs...\n")
  
  repeat
    local namelen = string.byte(component.invoke(address, "read", 1))
    
    term.write("found file with name length of "..namelen.."\n")
    if namelen>0 then
      local filename = component.invoke(address, "read", namelen)
      local filestart = readBinaryInt(address)
      local filesize = readBinaryInt(address)
      local filetype = string.byte(component.invoke(address, "read", 1))
      
      filetable[filename] = {}
      filetable[filename].offset = filestart
      filetable[filename].size = filesize
      filetable[filename].type = fileTypes[filetype]
      
      term.write("file "..filename.." added to medicfs!\n")
      --component.invoke(address, "seek", filestart + filesize)
    else
      break
    end
  until namelen==0
  
  term.write("reading done!\n")
  
  -- fields
  proxy.type = "filesystem"
  proxy.address = "medic-" .. address
  
  -- members
  proxy.isReadOnly = function() return false end
  
  proxy.list = function()
    index = {}
    n = 0
    for k, v in pairs(filetable) do
      n = n+1
      index[n] = k
    end
    return index
  end
  
  proxy.lastModified = function(path)
    checkArg(1, path, "string")
    -- unsupported
    return 0
  end
  
  proxy.spaceTotal = function()
    return component.invoke(address, "getSize")
  end
  
  proxy.size = function(path)
    if filetable[path] then
      return filetable[path].size
    end
    return 0
  end
  
  proxy.rename = function(path, newpath)
    checkArg(1,path,"string")
    checkArg(1,newpath,"string")
    if not filetable[path] then 
      return false
    end
    filetable[newpath] = filetable[path]
    filetable[path] = nil
    return true
  end
  
  proxy.remove = function(path)
    checkArg(1,path,"string")
    if not path or not filetable[path] then
      return false
    end
    filetable[path] = nil
    return true
  end
  
  proxy.open = function(path, mode)
    checkArg(1,path,"string")
    checkArg(2,mode,"string")
    if not filetable[path] or not component.invoke(address, "isReady") then
      return nil, "file not found"
    end
    if mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "wb" and mode ~= "a" and mode ~= "ab" then
      error("unsupported mode",2)
    end
    
    while true do
      local descriptor = math.random(1000000000,9999999999)
      if filedescr[descriptor] == nil then
        filedescr[descriptor] = {
          seek = 0,
          mode = mode:sub(1,1) == "r" and "r" or "w",
          offset = filetable[path].offset,
          size = filetable[path].size,
          path = path
        }
        return descriptor
      else
        return nil, "file occupied"
      end
    end
  end
  
  proxy.read = function(handle, count)
    count = count or 1
    checkArg(1,handle,"number")
    checkArg(2,count,"number")
    if filedescr[handle] == nil or filedescr[handle].mode ~= "r" then
      return nil, "bad file descriptor"
    end
    
    component.invoke(address, "seek", -math.huge)
    component.invoke(address, "seek", filedescr[handle].offset + filedescr[handle].seek)
    if count>(filedescr[handle].size-filedescr[handle].seek) then
      count = filedescr[handle].size-filedescr[handle].seek
    end
    local data = component.invoke(address, "read", count)
    filedescr[handle].seek = filedescr[handle].seek + #data
    if #data > 0 then 
      return data
    else
      return nil
    end
  end
  
  proxy.close = function(handle)
    checkArg(1,handle,"number")
    if filedescr[handle] == nil then
      return nil, "bad file descriptor"
    end
    
    filedescr[handle] = nil
  end
  
  proxy.seek = function(handle,type,shift)
    checkArg(1,handle,"number")
    checkArg(2,type,"string")
    checkArg(3,shift,"number")
    if filedescr[handle] == nil then
      return nil, "bad file descriptor"
    end
    if type ~= "set" and type ~= "cur" and type ~= "end" then
      error("invalid mode",2)
    end
    if shift < 0 then
      return nil, "Negative seek offset"
    end
    local newpos
    if type == "set" then
      newpos = shift
    elseif type == "cur" then
      newpos = filedescr[handle].offset + filedescr[handle].seek + shift
    elseif type == "end" then
      newpos = filedescr[handle].offset + filedescr[handle].size + shift - 1
    end
    filedescr[handle].seek = math.min(math.max(newpos, 0), filedescr[handle].size - 1)
    return filedescr[handle].seek
  end
  
  proxy.write = function(handle,data)
    checkArg(1,handle,"number")
    checkArg(2,data,"string")
    if filedescr[handle] == nil or filedescr[handle].mode ~= "w" then
      return nil, "bad file descriptor"
    end
  
    component.invoke(address, "seek", -math.huge)
    component.invoke(address, "seek", filedescr[handle].offset + filedescr[handle].seek)
  
    component.invoke(address, "write", data)
    filedescr[handle].seek = filedescr[handle].seek + #data
    filedescr[handle].size = filedescr[handle].seek
    return true
  end
  
  proxy.close = function(handle)
    checkArg(1,handle,"number")
    filetable[filedescr[handle].path].size = filedescr[handle].size
    filedescr[handle] = nil
  end
  
  proxy.exists = function(path)
    checkArg(1, path, "string")
    if not filetable[path] then
      return false
    else
      return true
    end
  end
  
  proxy.isDirectory = function(path)
    -- TODO: implement directories (or no)
    return false
  end
  
  proxy.makeDirectory = function(path)
    -- TODO: implement directories (or no)
    return false, "not implemented"
  end

  return proxy
end

function format(address)
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
  local b1, b2, b3, b4 = int_to_bytes(offset+13)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file length
  local b1, b2, b3, b4 = int_to_bytes(11)
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
  local b1, b2, b3, b4 = int_to_bytes(256)
  component.invoke(address, "write", string.char(b1)..string.char(b2)..string.char(b3)..string.char(b4))
  offset = offset + 4
  -- file length
  local b1, b2, b3, b4 = int_to_bytes(17)
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

for k,v in component.list() do
  if v=="tape_drive" then
    format(k)
    term.write("format succeeded\n")
    fs.mount(medic.proxy(k),"/medic")
    term.write("mount succeeded\n")
  end
end


fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
load     = require './load'

{diff_match_patch; DIFF_DELETE, DIFF_INSERT, DIFF_EQUAL} =
    require '../vendor/diff_match_patch.js'
DIFF_BASE = 2

maxSizeIndexBuf =  18 * 256
maxSizeDatBuf   = 256 * 256

curPath = ''
curText = ''
indexBuf    = dataBuf     = null
indexBufLen = dataBufLen  = 0

ensureBufSpace = (len, extra, buf, ofs) ->
  if not buf then buf = new buffer len + extra
  else
    if not ofs then ofs = buf.length
    if ofs + len > buf.length then
      buf = buf.concat [buf, new Buffer(ofs + len - buf.length + extra)]
  buf

writeUInt48 = (num, buf, ofs) ->
  buf = ensureBufSpace 6, 0, buf, ofs
  ms16 = (num / 0x100000000) & 0xffff
  ls32 = num & 0xffffffff
  buf.writeUInt16BE ms16, ofs,   yes
  buf.writeUInt32BE ls32, ofs+2, yes
  buf

writeFlag48 = (buf, ofs) ->
  buf = ensureBufSpace 6, 25, buf, ofs
  buf.fill 0xff, ofs, 6
  buf

writeHdr = (time, fileBegPos, fileEndPos, buf, ofs) ->
  buf = ensureBufSpace 18, 18 * 32, buf, ofs
  buf = writeUInt48 time,       buf, ofs
  buf = writeUInt48 fileBegPos, buf, ofs +  6
  buf = writeUInt48 fileEndPos, buf, ofs + 12
  buf

getFileLen = (path) ->
  try
    stats = fs.statSync path
  catch e
    mkdirp.sync pathUtil.dirname path
    fs.closeSync fs.openSync path, 'a'
    return 0
  stats.size

appendBufToFile = (path, buf, bufLen, maxBufLen) ->
    if bufLen > maxBufLen
      fs.appendFile path, buf.slice 0, buflen
      buf = new Buffer 1e4
      bufLen = 0

appendDiffs = (diffList, path) ->
  indexPath = pathUtil.join path, 'index'
  dataPath  = pathUtil.join path, 'data'

  len = 24
  for diff in diffList
    len += 7
    if diff[0] not in [DIFF_DELETE, DIFF_EQUAL]
      strBytesLen = Buffer.byteLength diff[1]
      diff[2] = strBytesLen
      len += strBytesLen

  dataFileLen = getFileLen dataPath
  indexBuf = writeHdr Date.now(), dataFileLen, dataFileLen + len, indexBuf
  indexBufLen += 18

  dataPos = dataBufLen
  dataBuf = ensureBufSpace len, 128*1024, dataBuf, dataPos
  indexBuf.copy dataBuf, dataPos, indexBufLen-18, indexBufLen
  dataPos += 18
  for diff in diffList
    [type, difStr, difLen] = diff
    dataBuf.writeInt8 type, dataPos++
    noStr = type in [DIFF_DELETE, DIFF_EQUAL]
    len = 7 + (if noStr then difStr.length else difLen)
    writeUInt48 len, dataBuf, dataPos; dataPos += 6
    if not noStr
      dataBuf.write difStr, dataPos, difLen
      dataPos += difLen
  writeFlag48 dataBuf, dataPos; dataPos += 6
  dataBufLen = dataPos

  appendBufToFile indexPath, indexBuf, indexBufLen, 1e5
  appendBufToFile  dataPath,  dataBuf,  dataBufLen, 1e6

  null

setPath = (path) ->
  if path isnt curPath
    indexPath = pathUtil.join curPath, 'index'
    dataPath  = pathUtil.join curPath, 'data'
    {indexBuf, indexBufLen} =
        appendBufToFile indexPath, indexBuf, indexBufLen, 0
    {dataBuf,  dataBufLen}
        appendBufToFile  dataPath,  dataBuf,  dataBufLen, 0
    curPath = path
    curText = load.text path

save = exports

save.text = (path, text, base = no) ->
  setPath path
  if base or curText is ''
    diffList = [[DIFF_BASE, text]]
  else
    diffList = diff_match_patch.diff_main curText, text
  appendDiffs diffList, path, indexBuf, indexBufLen, dataBuf, dataBufLen
  curText = text

save.flush = -> setPath ''

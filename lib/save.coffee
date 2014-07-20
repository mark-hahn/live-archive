
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
load     = require './load'

DIFF_BASE = 2
checkFiles     = require './checkFiles'
{diff_match_patch, DIFF_DELETE, DIFF_INSERT, DIFF_EQUAL} =
                      require '../vendor/diff_match_patch.js'
diffMatchPatch = new diff_match_patch

diff_match = new diff_match_patch

maxSizeIndexBuf =  18 * 256
maxSizeDatBuf   = 256 * 256

curPath = indexPath = dataPath = ''
curText = ''
indexBuf    = dataBuf     = null
indexBufLen = dataBufLen  = 0

ensureBufSpace = (len, extra, buf, ofs) ->
  if not buf then buf = new Buffer len + extra
  else
    if not ofs then ofs = buf.length
    if ofs + len > buf.length
      buf = Buffer.concat [buf, new Buffer(ofs + len - buf.length + extra)]
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
  buf.fill 0xff, ofs, ofs+6
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

appendBufsToFiles = (maxData, maxIndex)->
  if dataBufLen > maxData
      fs.appendFileSync  dataPath,  dataBuf.slice 0,  dataBufLen
      dataBuf = null
      dataBufLen = 0

  if indexBufLen > maxIndex
      fs.appendFileSync indexPath, indexBuf.slice 0, indexBufLen
      indexBuf = null
      indexBufLen = 0

appendDiffs = (diffList) ->
  len = 24
  for diff in diffList
    len += 7
    if diff[0] not in [DIFF_DELETE, DIFF_EQUAL]
      strBytesLen = Buffer.byteLength diff[1]
      diff[2] = strBytesLen
      len += strBytesLen

  dataFileLen = getFileLen dataPath
  indexBuf = writeHdr Date.now(), dataFileLen, dataFileLen + len, indexBuf, indexBufLen
  indexBufLen += 18

  dataPos = dataBufLen
  dataBuf = ensureBufSpace len, 512, dataBuf, dataPos
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

  appendBufsToFiles 1e6, 1e5

  null

setPath = (path) ->
  if path isnt curPath
    if curPath then appendBufsToFiles 0, 0
    curPath = path
    curText = ''
    if path
      indexPath = pathUtil.join path, 'index'
      dataPath  = pathUtil.join path, 'data'
      curText = load.text curPath
      indexBuf = dataBuf = null
      indexBufLen = dataBufLen = 0

save = exports

save.text = (path, text, base = no) ->
  setPath path
  if base or curText is ''
    diffList = [[DIFF_BASE, text]]
  else
    diffList = diffMatchPatch.diff_main curText, text
    if diffList.length is 1 and diffList[0][0] is DIFF_EQUAL
      return
  appendDiffs diffList
  curText = text

save.flush = -> setPath ''

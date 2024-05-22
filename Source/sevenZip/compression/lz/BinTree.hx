package sevenZip.compression.lz;

class BinTree extends InWindow {
    var _cyclicBufferPos:Int;
    var _cyclicBufferSize:Int = 0;
    var _matchMaxLen:Int;
	
    var _son:Array<Int>;
    var _hash:Array<Int>;
	
    var _cutValue:Int = 0xFF;
    var _hashMask:Int;
    var _hashSizeSum:Int = 0;
    
    static var HASH_ARRAY:Bool = true;
	
	static final kHash2Size:Int = 1 << 10;
	static final kHash3Size:Int = 1 << 16;
	static final kBT2HashSize:Int = 1 << 16;
	static final kStartMaxLen:Int = 1;
	static final kHash3Offset:Int = kHash2Size;
	static final kEmptyHashValue:Int = 0;
	static final kMaxValForNormalize:Int = (1 << 30) - 1;
	
	var kNumHashDirectBytes:Int = 0;
	var kMinMatchCheck:Int = 4;
	var kFixHashSize:Int = kHash2Size + kHash3Size;

    public function new() {
        super();
    }

    public function setType(numHashBytes:Int):Void {
        HASH_ARRAY = (numHashBytes > 2);
        if (HASH_ARRAY) {
            kNumHashDirectBytes = 0;
            kMinMatchCheck = 4;
            kFixHashSize = kHash2Size + kHash3Size;
        } else {
            kNumHashDirectBytes = 2;
            kMinMatchCheck = 2 + 1;
            kFixHashSize = 0;
        }
    }

    public override function init():Void {
        super.init();
        //_hashSizeSum = _hashSizeSum;
        for (i in 0..._hashSizeSum) _hash[i] = kEmptyHashValue;
        _cyclicBufferPos = 0;
        reduceOffsets(-1);
    }

    public override function movePos():Void {
        if (++_cyclicBufferPos >= _cyclicBufferSize) _cyclicBufferPos = 0;
        super.movePos();
        if (_pos == kMaxValForNormalize) normalize();
    }

	
     public function create(historySize:Int, keepAddBufferBefore:Int, matchMaxLen:Int, keepAddBufferAfter:Int):Bool {

        if (historySize > kMaxValForNormalize - 256) return false;
        _cutValue = 16 + (matchMaxLen >> 1);

        var windowReservSize:Int = Std.int((historySize + keepAddBufferBefore + matchMaxLen + keepAddBufferAfter) / 2 + 256);

        super.Create(historySize + keepAddBufferBefore, matchMaxLen + keepAddBufferAfter, windowReservSize);

        _matchMaxLen = matchMaxLen;

        var cyclicBufferSize:Int = historySize + 1;
        if (_cyclicBufferSize != cyclicBufferSize) {
			_cyclicBufferSize = cyclicBufferSize;
			_son = new Array<Int>();
			for (i in 0..._cyclicBufferSize * 2) {
				_son.push(0);
			}
		}

        var hs:Int = kBT2HashSize;

        if (HASH_ARRAY) {
            hs = historySize - 1;
            hs |= (hs >> 1);
            hs |= (hs >> 2);
            hs |= (hs >> 4);
            hs |= (hs >> 8);
            hs >>= 1;
            hs |= 0xFFFF;
            if (hs > (1 << 24)) hs >>= 1;
            _hashMask = hs;
            hs++;
            hs += kFixHashSize;
        }

        if (hs != _hashSizeSum) {
			_hashSizeSum = hs;
			_hash = new Array<Int>();
			for (i in 0..._hashSizeSum) {
				_hash.push(0);
			}
		}

        return true;
    }

	public function getMatches(distances:Array<Int>):Int {
		var lenLimit:Int;
		if (_pos + _matchMaxLen <= _streamPos) {
			lenLimit = _matchMaxLen;
		} else {
			lenLimit = _streamPos - _pos;
			if (lenLimit < kMinMatchCheck) {
				movePos();
				return 0;
			}
		}

		var offset:Int = 0;
		var matchMinPos:Int = (_pos > _cyclicBufferSize) ? (_pos - _cyclicBufferSize) : 0;
		var cur:Int = _bufferOffset + _pos;
		var maxLen:Int = kStartMaxLen; // to avoid items for len < hashSize;
		var hashValue:Int, hash2Value:Int = 0, hash3Value:Int = 0;

		if (HASH_ARRAY) {
			var temp:Int = CrcTable[_bufferBase.get(cur) & 0xFF] ^ (_bufferBase.get(cur + 1) & 0xFF);
			var hash2Value:Int = temp & (kHash2Size - 1);
			//_hash[hash2Value] = _pos;
			temp ^= ((_bufferBase.get(cur + 2) & 0xFF) << 8);
			var hash3Value:Int = temp & (kHash3Size - 1);
			//_hash[kHash3Offset + hash3Value] = _pos;
			hashValue = (temp ^ (CrcTable[_bufferBase.get(cur + 3) & 0xFF] << 5)) & _hashMask;
		} else {
			hashValue = ((_bufferBase.get(cur) & 0xFF) ^ ((_bufferBase.get(cur + 1) & 0xFF) << 8));
		}


		var curMatch:Int = _hash[kFixHashSize + hashValue];
		if (HASH_ARRAY) {
			var curMatch2:Int = _hash[hash2Value];
			var curMatch3:Int = _hash[kHash3Offset + hash3Value];
			_hash[hash2Value] = _pos;
			_hash[kHash3Offset + hash3Value] = _pos;
			if (curMatch2 > matchMinPos) {
				if (_bufferBase.get(_bufferOffset + curMatch2) == _bufferBase.get(cur)) {
					distances[offset++] = maxLen = 2;
					distances[offset++] = _pos - curMatch2 - 1;
				}
			}
			if (curMatch3 > matchMinPos) {
				if (_bufferBase.get(_bufferOffset + curMatch3) == _bufferBase.get(cur)) {
					if (curMatch3 == curMatch2) {
						offset -= 2;
					}
					distances[offset++] = maxLen = 3;
					distances[offset++] = _pos - curMatch3 - 1;
					curMatch2 = curMatch3;
				}
			}
			if (offset != 0 && curMatch2 == curMatch) {
				offset -= 2;
				maxLen = kStartMaxLen;
			}
		}

		_hash[kFixHashSize + hashValue] = _pos;

		var ptr0:Int = (_cyclicBufferPos << 1) + 1;
		var ptr1:Int = (_cyclicBufferPos << 1);

		var len0:Int, len1:Int;
		len0 = len1 = kNumHashDirectBytes;

		if (kNumHashDirectBytes != 0) {
			if (curMatch > matchMinPos) {
				if (_bufferBase.get(_bufferOffset + curMatch + kNumHashDirectBytes) !=
					_bufferBase.get(cur + kNumHashDirectBytes)) {
					distances[offset++] = maxLen = kNumHashDirectBytes;
					distances[offset++] = _pos - curMatch - 1;
				}
			}
		}

		var count:Int = _cutValue;

		while (true) {
			if (curMatch <= matchMinPos || count-- == 0) {
				_son[ptr0] = _son[ptr1] = kEmptyHashValue;
				break;
			}
			var delta:Int = _pos - curMatch;
			var cyclicPos:Int = ((delta <= _cyclicBufferPos) ?
				(_cyclicBufferPos - delta) :
				(_cyclicBufferPos - delta + _cyclicBufferSize)) << 1;

			var pby1:Int = _bufferOffset + curMatch;
			var len:Int = Std.int(Math.min(len0, len1));
			if (_bufferBase.get(pby1 + len) == _bufferBase.get(cur + len)) {
				while (++len != lenLimit) {
					if (_bufferBase.get(pby1 + len) != _bufferBase.get(cur + len)) {
						break;
					}
				}
				if (maxLen < len) {
					distances[offset++] = maxLen = len;
					distances[offset++] = delta - 1;
					if (len == lenLimit) {
						_son[ptr1] = _son[cyclicPos];
						_son[ptr0] = _son[cyclicPos + 1];
						break;
					}
				}
			}
			if ((_bufferBase.get(pby1 + len) & 0xFF) < (_bufferBase.get(cur + len) & 0xFF)){
				_son[ptr1] = curMatch;
				ptr1 = cyclicPos + 1;
				curMatch = _son[ptr1];
				len1 = len;
			} else {
				_son[ptr0] = curMatch;
				ptr0 = cyclicPos;
				curMatch = _son[ptr0];
				len0 = len;
			}
		}
		movePos();
		return offset;
	}
	
	public function skip(num:Int):Void {
		do {
			var lenLimit:Int;
			if (_pos + _matchMaxLen <= _streamPos) {
				lenLimit = _matchMaxLen;
			} else {
				lenLimit = _streamPos - _pos;
				if (lenLimit < kMinMatchCheck) {
					movePos();
					continue;
				}
			}

			var matchMinPos:Int = (_pos > _cyclicBufferSize) ? (_pos - _cyclicBufferSize) : 0;
			var cur:Int = _bufferOffset + _pos;

			var hashValue:Int;

			if (HASH_ARRAY) {
				var temp:Int = CrcTable[_bufferBase.get(cur) & 0xFF] ^ (_bufferBase.get(cur + 1) & 0xFF);
				var hash2Value:Int = temp & (kHash2Size - 1);
				_hash[hash2Value] = _pos;
				temp ^= ((_bufferBase.get(cur + 2) & 0xFF) << 8);
				var hash3Value:Int = temp & (kHash3Size - 1);
				_hash[kHash3Offset + hash3Value] = _pos;
				hashValue = (temp ^ (CrcTable[_bufferBase.get(cur + 3) & 0xFF] << 5)) & _hashMask;
			} else {
				hashValue = ((_bufferBase.get(cur) & 0xFF) ^ ((_bufferBase.get(cur + 1) & 0xFF) << 8));
			}

			var curMatch:Int = _hash[kFixHashSize + hashValue];
			_hash[kFixHashSize + hashValue] = _pos;

			var ptr0:Int = (_cyclicBufferPos << 1) + 1;
			var ptr1:Int = (_cyclicBufferPos << 1);

			var len0:Int, len1:Int;
			len0 = len1 = kNumHashDirectBytes;

			var count:Int = _cutValue;
			while (true) {
				if (curMatch <= matchMinPos || count-- == 0) {
					_son[ptr0] = _son[ptr1] = kEmptyHashValue;
					break;
				}

				var delta:Int = _pos - curMatch;
				var cyclicPos:Int = ((delta <= _cyclicBufferPos) ?
					(_cyclicBufferPos - delta) :
					(_cyclicBufferPos - delta + _cyclicBufferSize)) << 1;

				var pby1:Int = _bufferOffset + curMatch;
				var len:Int = Std.int(Math.min(len0, len1));
				if (_bufferBase.get(pby1 + len) == _bufferBase.get(cur + len)) {
					while (++len != lenLimit) {
						if (_bufferBase.get(pby1 + len) != _bufferBase.get(cur + len)) {
							break;
						}
					}
					if (len == lenLimit) {
						_son[ptr1] = _son[cyclicPos];
						_son[ptr0] = _son[cyclicPos + 1];
						break;
					}
				}
				if ((_bufferBase.get(pby1 + len) & 0xFF) < (_bufferBase.get(cur + len) & 0xFF)) {
					_son[ptr1] = curMatch;
					ptr1 = cyclicPos + 1;
					curMatch = _son[ptr1];
					len1 = len;
				} else {
					_son[ptr0] = curMatch;
					ptr0 = cyclicPos;
					curMatch = _son[ptr0];
					len0 = len;
				}
			}
			movePos();
		}while (--num != 0);
	}
	
	function normalizeLinks(items:Array<Int>, numItems:Int, subValue:Int):Void
	{
		for (i in 0...numItems)
		{
			var value:Int = items[i];
			if (value <= subValue)
				value = kEmptyHashValue;
			else
				value -= subValue;
			items[i] = value;
		}
	}
	
	public function normalize():Void
	{
		var subValue:Int = _pos - _cyclicBufferSize;
		normalizeLinks(_son, _cyclicBufferSize * 2, subValue);
		normalizeLinks(_hash, _hashSizeSum, subValue);
		reduceOffsets(subValue);
	}
	
	public function setCutValue(cutValue:Int):Void {
		_cutValue = cutValue;
	}

	private static var CrcTable:Array<Int> = initCrcTable();

	private static function initCrcTable():Array<Int> {
		var table:Array<Int> = [];
		for (i in 0...256) {
			var r:Int = i;
			for (j in 0...8) {
				if ((r & 1) != 0) {
					r = (r >>> 1) ^ 0xEDB88320;
				} else {
					r >>>= 1;
				}
			}
			table.push(r);
		}
		return table;
	}
}
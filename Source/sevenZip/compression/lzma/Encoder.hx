package sevenZip.compression.lzma;

import haxe.io.Input;
import haxe.io.Output;
import sevenZip.compression.rangeCoder.BitTreeEncoder;
import sevenZip.compression.lzma.Base;
import sevenZip.compression.lz.BinTree;
import sevenZip.ICodeProgress;
import haxe.display.Protocol.InitializeParams;
import haxe.io.Bytes;
import haxe.io.BytesData;
import sevenZip.compression.rangeCoder.Encoder;
import haxe.Int64;

class Encoder {
	private static function iniArray(length:Int):Array<Int> {
        var arr:Array<Int> = new Array<Int>();
        for (i in 0...length) {
            arr.push(0);
        }
        return arr;
    }
	private static function ini64Array(length:Int):Array<Int64> {
        var arr:Array<Int64> = new Array<Int64>();
        for (i in 0...length) {
            arr.push(0);
        }
        return arr;
    }
	private static function byteArray(length:Int):Array<haxe.io.Bytes> {
        var arr:Array<haxe.io.Bytes> = new Array<haxe.io.Bytes>();
        for (i in 0...length) {
            arr.push(null);
        }
        return arr;
    }
	private static function boolArray(length:Int):Array<Bool> {
        var arr:Array<Bool> = new Array<Bool>();
        for (i in 0...length) {
            arr.push(false);
        }
        return arr;
    }
	private static function iniArrayEncoders(length:Int):Array<BitTreeEncoder> {
        var array:Array<BitTreeEncoder> = new Array<BitTreeEncoder>();
        for (i in 0...length) array.push(new BitTreeEncoder(Base.kNumPosSlotBits));
        return array;
    }
	private static function iniArrayOptimal(length:Int):Array<Optimal> {
        var array:Array<Optimal> = new Array<Optimal>();
        for (i in 0...length) array.push(new Optimal());
        return array;
    }
	
    public static inline var EMatchFinderTypeBT2:Int = 0;
    public static inline var EMatchFinderTypeBT4:Int = 1;
    
    static inline var kIfinityPrice:Int = 0xFFFFFFF;
    
    static var g_FastPos:Bytes = g_FastPosInit();
	
	static function g_FastPosInit():Bytes {
		var table = Bytes.alloc(1 << 11);
		var kFastSlots:Int = 22;
        var c:Int = 2;
        table.set(0, 0);
        table.set(1, 1);
        for (slotFast in 2...kFastSlots)
        {
            var k:Int = (1 << ((slotFast >> 1) - 1));
            for (j in 0...k) {
                table.set(c, slotFast);
                c++;
            }
        }
		return table;
	}
	
	public static function getPosSlot(pos:Int):Int {
		if (pos < (1 << 11))
			return g_FastPos.get(pos);
		if (pos < (1 << 21))
			return (g_FastPos.get(pos >> 10) + 20);
		return (g_FastPos.get(pos >> 20) + 40);
	}
	
	public static function getPosSlot2(pos:Int):Int {
		if (pos < (1 << 17))
			return (g_FastPos.get(pos >> 6) + 12);
		if (pos < (1 << 27))
			return (g_FastPos.get(pos >> 16) + 32);
		return (g_FastPos.get(pos >> 26) + 52);
	}
	
	var _state:Int = Base.stateInit();
	var _previousByte:Int;
	var _repDistances:Array<Int> = iniArray(Base.kNumRepDistances);

	private function baseInit() {
		_state = Base.stateInit();
		_previousByte = 0;
		for (i in 0...Base.kNumRepDistances) _repDistances[i] = 0;
	}

	static inline var kDefaultDictionaryLogSize:Int = 22;
	static inline var kNumFastBytesDefault:Int = 0x20;
	
	public static inline var kNumLenSpecSymbols:Int = Base.kNumLowLenSymbols + Base.kNumMidLenSymbols;
	
	static inline var kNumOpts:Int = 1 << 12;
	
	var _optimum:Array<Optimal> = iniArrayOptimal(kNumOpts);
    var _matchFinder:sevenZip.compression.lz.BinTree = null;
    var _rangeEncoder:sevenZip.compression.rangeCoder.Encoder = new sevenZip.compression.rangeCoder.Encoder();

    var _isMatch:Array<Int> = iniArray(Base.kNumStates << Base.kNumPosStatesBitsMax);
    var _isRep:Array<Int> = iniArray(Base.kNumStates);
    var _isRepG0:Array<Int> = iniArray(Base.kNumStates);
    var _isRepG1:Array<Int> = iniArray(Base.kNumStates);
    var _isRepG2:Array<Int> = iniArray(Base.kNumStates);
    var _isRep0Long:Array<Int> = iniArray(Base.kNumStates << Base.kNumPosStatesBitsMax);

    var _posSlotEncoder:Array<BitTreeEncoder> = iniArrayEncoders(Base.kNumLenToPosStates);

    var _posEncoders:Array<Int> = iniArray(Base.kNumFullDistances - Base.kEndPosModelIndex);
    var _posAlignEncoder:BitTreeEncoder = new BitTreeEncoder(Base.kNumAlignBits);

    var _lenEncoder:LenPriceTableEncoder = new LenPriceTableEncoder();
    var _repMatchLenEncoder:LenPriceTableEncoder = new LenPriceTableEncoder();

    var _literalEncoder:LiteralEncoder = new LiteralEncoder();

    var _matchDistances:Array<Int> = iniArray(Base.kMatchMaxLen * 2 + 2);

    var _numFastBytes:Int = kNumFastBytesDefault;
    var _longestMatchLength:Int;
    var _numDistancePairs:Int;

    var _additionalOffset:Int;

    var _optimumEndIndex:Int;
    var _optimumCurrentIndex:Int;

    var _longestMatchWasFound:Bool;

    var _posSlotPrices:Array<Int> = iniArray(1 << (Base.kNumPosSlotBits + Base.kNumLenToPosStatesBits));
    var _distancesPrices:Array<Int> = iniArray(Base.kNumFullDistances << Base.kNumLenToPosStatesBits);
    var _alignPrices:Array<Int> = iniArray(Base.kAlignTableSize);
    var _alignPriceCount:Int;

    var _distTableSize:Int = (kDefaultDictionaryLogSize * 2);

    var _posStateBits:Int = 2;
    var _posStateMask:Int = (4 - 1);
    var _numLiteralPosStateBits:Int = 0;
    var _numLiteralContextBits:Int = 3;

    var _dictionarySize:Int = (1 << kDefaultDictionaryLogSize);
    var _dictionarySizePrev:Int = -1;
    var _numFastBytesPrev:Int = -1;

    var nowPos64:Int64 = Int64.make(0, 0);
    var _finished:Bool;
    var _inStream:haxe.io.Input;

    var _matchFinderType:Int = EMatchFinderTypeBT4;
    var _writeEndMark:Bool = false;

    var _needReleaseMFStream:Bool = false;
	
	public function create():Void {
		if (_matchFinder == null)
		{
			var bt:sevenZip.compression.lz.BinTree = new sevenZip.compression.lz.BinTree();
			var numHashBytes:Int = 4;
			if (_matchFinderType == EMatchFinderTypeBT2) numHashBytes = 2;
			bt.setType(numHashBytes);
			_matchFinder = bt;
		}
		_literalEncoder.create(_numLiteralPosStateBits, _numLiteralContextBits);

		if (_dictionarySize == _dictionarySizePrev && _numFastBytesPrev == _numFastBytes) return;
		_matchFinder.create(_dictionarySize, kNumOpts, _numFastBytes, Base.kMatchMaxLen + 1);
		_dictionarySizePrev = _dictionarySize;
		_numFastBytesPrev = _numFastBytes;
	}
	
	public function new() {
		for (i in 0...kNumOpts) _optimum[i] = new Optimal();
		for (i in 0...Base.kNumLenToPosStates) _posSlotEncoder[i] = new BitTreeEncoder(Base.kNumPosSlotBits);
    }
	
	function setWriteEndMarkerMode(writeEndMarker:Bool):Void _writeEndMark = writeEndMarker;
	
	function init():Void {
		baseInit();
		_rangeEncoder.init();

		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isMatch);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isRep0Long);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isRep);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isRepG0);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isRepG1);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_isRepG2);
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_posEncoders);
		
		_literalEncoder.init();
		for (i in 0...Base.kNumLenToPosStates) _posSlotEncoder[i].init();

		_lenEncoder.init(1 << _posStateBits);
		_repMatchLenEncoder.init(1 << _posStateBits);

		_posAlignEncoder.init();

		_longestMatchWasFound = false;
		_optimumEndIndex = 0;
		_optimumCurrentIndex = 0;
		_additionalOffset = 0;
	}
	
	function readMatchDistances():Int {
		var lenRes:Int = 0;
		_numDistancePairs = _matchFinder.getMatches(_matchDistances);
		if (_numDistancePairs > 0)
		{
			lenRes = _matchDistances[_numDistancePairs - 2];
			if (lenRes == _numFastBytes) lenRes += _matchFinder.getMatchLen(lenRes - 1, _matchDistances[_numDistancePairs - 1], Base.kMatchMaxLen - lenRes);
		}
		_additionalOffset++;
		return lenRes;
	}
	
	function movePos(num:Int):Void {
		if (num > 0)
		{
			_matchFinder.skip(num);
			_additionalOffset += num;
		}
	}
	
	function getRepLen1Price(state:Int, posState:Int):Int return sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRepG0[state]) + sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRep0Long[(state << Base.kNumPosStatesBitsMax) + posState]);
	
	function getPureRepPrice(repIndex:Int, state:Int, posState:Int):Int {
		var price:Int;
		if (repIndex == 0)
		{
			price = sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRepG0[state]);
			price += sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep0Long[(state << Base.kNumPosStatesBitsMax) + posState]);
		}
		else
		{
			price = sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRepG0[state]);
			if (repIndex == 1)
				price += sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRepG1[state]);
			else
			{
				price += sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRepG1[state]);
				price += sevenZip.compression.rangeCoder.Encoder.getPrice(_isRepG2[state], repIndex - 2);
			}
		}
		return price;
	}
	
	function getRepPrice(repIndex:Int, len:Int, state:Int, posState:Int):Int {
		var price:Int = _repMatchLenEncoder.getPrice(len - Base.kMatchMinLen, posState);
		return price + getPureRepPrice(repIndex, state, posState);
	}

	function getPosLenPrice(pos:Int, len:Int, posState:Int):Int {
		var price:Int;
		var lenToPosState:Int = Base.getLenToPosState(len);
		if (pos < Base.kNumFullDistances) 
			price = _distancesPrices[(lenToPosState * Base.kNumFullDistances) + pos];
		else 
			price = _posSlotPrices[(lenToPosState << Base.kNumPosSlotBits) + getPosSlot2(pos)] + _alignPrices[pos & Base.kAlignMask];
		return price + _lenEncoder.getPrice(len - Base.kMatchMinLen, posState);
	}
	
	function backward(cur:Int):Int {
		_optimumEndIndex = cur;
		var posMem:Int = _optimum[cur].posPrev;
		var backMem:Int = _optimum[cur].backPrev;
		
		do {
			if (_optimum[cur].prev1IsChar) {
				_optimum[posMem].makeAsChar();
				_optimum[posMem].posPrev = posMem - 1;
				
				if (_optimum[cur].prev2) {
					_optimum[posMem - 1].prev1IsChar = false;
					_optimum[posMem - 1].posPrev = _optimum[cur].posPrev2;
					_optimum[posMem - 1].backPrev = _optimum[cur].backPrev2;
				}
			}
			
			var posPrev:Int = posMem;
			var backCur:Int = backMem;
			
			backMem = _optimum[posPrev].backPrev;
			posMem = _optimum[posPrev].posPrev;
			
			_optimum[posPrev].backPrev = backCur;
			_optimum[posPrev].posPrev = cur;
			cur = posPrev;
		} while (cur > 0);
		
		backRes = _optimum[0].backPrev;
		_optimumCurrentIndex = _optimum[0].posPrev;
		return _optimumCurrentIndex;
	}

	var reps:Array<Int> = iniArray(Base.kNumRepDistances);
	var repLens:Array<Int> = iniArray(Base.kNumRepDistances);
	var backRes:Int;
	
	function getOptimum(position:Int):Int {
		if (_optimumEndIndex != _optimumCurrentIndex)
		{
			var lenRes:Int = _optimum[_optimumCurrentIndex].posPrev - _optimumCurrentIndex;
			backRes = _optimum[_optimumCurrentIndex].backPrev;
			_optimumCurrentIndex = _optimum[_optimumCurrentIndex].posPrev;
			return lenRes;
		}
		_optimumCurrentIndex = _optimumEndIndex = 0;
		
		var lenMain, numDistancePairs:Int;
		if (!_longestMatchWasFound)
		{
			lenMain = readMatchDistances();
		}
		else
		{
			lenMain = _longestMatchLength;
			_longestMatchWasFound = false;
		}
		numDistancePairs = _numDistancePairs;
		
		var numAvailableBytes:Int = _matchFinder.getNumAvailableBytes() + 1;
		if (numAvailableBytes < 2)
		{
			backRes = -1;
			return 1;
		}
		if (numAvailableBytes > Base.kMatchMaxLen)
			numAvailableBytes = Base.kMatchMaxLen;
			
		var repMaxIndex:Int = 0;
		var i:Int = 0;
		while (i < Base.kNumRepDistances)
		{
			reps[i] = _repDistances[i];
			repLens[i] = _matchFinder.getMatchLen(0 - 1, reps[i], Base.kMatchMaxLen);
			if (repLens[i] > repLens[repMaxIndex])
				repMaxIndex = i;
			i++;
		}
		if (repLens[repMaxIndex] >= _numFastBytes)
		{
			backRes = repMaxIndex;
			var lenRes:Int = repLens[repMaxIndex];
			movePos(lenRes - 1);
			return lenRes;
		}	
			
		if (lenMain >= _numFastBytes)
		{
			backRes = _matchDistances[numDistancePairs - 1] + Base.kNumRepDistances;
			movePos(lenMain - 1);
			return lenMain;
		}

		var currentByte:Int = _matchFinder.getIndexByte(0 - 1);
		var matchByte:Int = _matchFinder.getIndexByte(0 - _repDistances[0] - 1 - 1);

		if (lenMain < 2 && currentByte != matchByte && repLens[repMaxIndex] < 2)
		{
			backRes = -1;
			return 1;
		}
		
		_optimum[0].state = _state;

		var posState:Int = (position & _posStateMask);

		_optimum[1].price = sevenZip.compression.rangeCoder.Encoder.getPrice0(_isMatch[(_state << Base.kNumPosStatesBitsMax) + posState]) +
			_literalEncoder.getSubCoder(position, _previousByte).getPrice(!Base.stateIsCharState(_state), matchByte, currentByte);
		_optimum[1].makeAsChar();

		var matchPrice:Int = sevenZip.compression.rangeCoder.Encoder.getPrice1(_isMatch[(_state << Base.kNumPosStatesBitsMax) + posState]);
		var repMatchPrice:Int = matchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep[_state]);
			
		if (matchByte == currentByte)
		{
			var shortRepPrice:Int = repMatchPrice + getRepLen1Price(_state, posState);
			if (shortRepPrice < _optimum[1].price)
			{
				_optimum[1].price = shortRepPrice;
				_optimum[1].makeAsShortRep();
			}
		}	
			
		var lenEnd:Int = ((lenMain >= repLens[repMaxIndex]) ? lenMain : repLens[repMaxIndex]);

		if (lenEnd < 2)
		{
			backRes = _optimum[1].backPrev;
			return 1;
		}

		_optimum[1].posPrev = 0;

		_optimum[0].backs0 = reps[0];
		_optimum[0].backs1 = reps[1];
		_optimum[0].backs2 = reps[2];
		_optimum[0].backs3 = reps[3];
	
		var len:Int = lenEnd;
		do {
			_optimum[len--].price = kIfinityPrice;
		} while (len >= 2);

		for (i in 0...Base.kNumRepDistances) {
			var repLen:Int = repLens[i];
			if (repLen < 2) {
				continue;
			}
			var price:Int = repMatchPrice + getPureRepPrice(i, _state, posState);
			do {
				var curAndLenPrice:Int = price + _repMatchLenEncoder.getPrice(repLen - 2, posState);
				var optimum:Optimal = _optimum[repLen];
				if (curAndLenPrice < optimum.price) {
					optimum.price = curAndLenPrice;
					optimum.posPrev = 0;
					optimum.backPrev = i;
					optimum.prev1IsChar = false;
				}
			} while (--repLen >= 2);
		}
	
		var normalMatchPrice:Int = matchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRep[_state]);

		len = ((repLens[0] >= 2) ? repLens[0] + 1 : 2);
		if (len <= lenMain)
		{
			var offs:Int = 0;
			while (len > _matchDistances[offs])
				offs += 2;
			while(true)
			{
				var distance:Int = _matchDistances[offs + 1];
				var curAndLenPrice:Int = normalMatchPrice + getPosLenPrice(distance, len, posState);
				var optimum:Optimal = _optimum[len];
				if (curAndLenPrice < optimum.price)
				{
					optimum.price = curAndLenPrice;
					optimum.posPrev = 0;
					optimum.backPrev = distance + Base.kNumRepDistances;
					optimum.prev1IsChar = false;
				}
				if (len == _matchDistances[offs])
				{
					offs += 2;
					if (offs == numDistancePairs)
						break;
				}
				len++;
			}
		}
		
		var cur:Int = 0;

		while (true)
		{
			cur++;
			if (cur == lenEnd)
				return backward(cur);
			var newLen:Int = readMatchDistances();
			numDistancePairs = _numDistancePairs;
			if (newLen >= _numFastBytes)
			{

				_longestMatchLength = newLen;
				_longestMatchWasFound = true;
				return backward(cur);
			}
			position++;
			var posPrev:Int = _optimum[cur].posPrev;
			var state:Int;
			if (_optimum[cur].prev1IsChar)
			{
				posPrev--;
				if (_optimum[cur].prev2)
				{
					state = _optimum[_optimum[cur].posPrev2].state;
					if (_optimum[cur].backPrev2 < Base.kNumRepDistances)
						state = Base.stateUpdateRep(state);
					else
						state = Base.stateUpdateMatch(state);
				}
				else
					state = _optimum[posPrev].state;
				state = Base.stateUpdateChar(state);
			}
			else
				state = _optimum[posPrev].state;
			if (posPrev == cur - 1)
			{
				if (_optimum[cur].isShortRep())
					state = Base.stateUpdateShortRep(state);
				else
					state = Base.stateUpdateChar(state);
			}
			else
			{
				var pos:Int;
				if (_optimum[cur].prev1IsChar && _optimum[cur].prev2)
				{
					posPrev = _optimum[cur].posPrev2;
					pos = _optimum[cur].backPrev2;
					state = Base.stateUpdateRep(state);
				}
				else
				{
					pos = _optimum[cur].backPrev;
					if (pos < Base.kNumRepDistances)
						state = Base.stateUpdateRep(state);
					else
						state = Base.stateUpdateMatch(state);
				}
				var opt:Optimal = _optimum[posPrev];
				if (pos < Base.kNumRepDistances)
				{
					if (pos == 0)
					{
						reps[0] = opt.backs0;
						reps[1] = opt.backs1;
						reps[2] = opt.backs2;
						reps[3] = opt.backs3;
					}
					else if (pos == 1)
					{
						reps[0] = opt.backs1;
						reps[1] = opt.backs0;
						reps[2] = opt.backs2;
						reps[3] = opt.backs3;
					}
					else if (pos == 2)
					{
						reps[0] = opt.backs2;
						reps[1] = opt.backs0;
						reps[2] = opt.backs1;
						reps[3] = opt.backs3;
					}
					else
					{
						reps[0] = opt.backs3;
						reps[1] = opt.backs0;
						reps[2] = opt.backs1;
						reps[3] = opt.backs2;
					}
				}
				else
				{
					reps[0] = (pos - Base.kNumRepDistances);
					reps[1] = opt.backs0;
					reps[2] = opt.backs1;
					reps[3] = opt.backs2;
				}
			}
		
			_optimum[cur].state = state;
			_optimum[cur].backs0 = reps[0];
			_optimum[cur].backs1 = reps[1];
			_optimum[cur].backs2 = reps[2];
			_optimum[cur].backs3 = reps[3];
			var curPrice:Int = _optimum[cur].price;

			currentByte = _matchFinder.getIndexByte(0 - 1);
			matchByte = _matchFinder.getIndexByte(0 - reps[0] - 1 - 1);

			posState = (position & _posStateMask);

			var curAnd1Price:Int = curPrice +
				sevenZip.compression.rangeCoder.Encoder.getPrice0(_isMatch[(state << Base.kNumPosStatesBitsMax) + posState]) +
				_literalEncoder.getSubCoder(position, _matchFinder.getIndexByte(0 - 2)).getPrice(!Base.stateIsCharState(state), matchByte, currentByte);

			var nextOptimum:Optimal = _optimum[cur + 1];

			var nextIsChar:Bool = false;
			if (curAnd1Price < nextOptimum.price)
			{
				nextOptimum.price = curAnd1Price;
				nextOptimum.posPrev = cur;
				nextOptimum.makeAsChar();
				nextIsChar = true;
			}

			matchPrice = curPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isMatch[(state << Base.kNumPosStatesBitsMax) + posState]);
			repMatchPrice = matchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep[state]);

			if (matchByte == currentByte && !(nextOptimum.posPrev < cur && nextOptimum.backPrev == 0))
			{
				var shortRepPrice:Int = repMatchPrice + getRepLen1Price(state, posState);
				if (shortRepPrice <= nextOptimum.price)
				{
					nextOptimum.price = shortRepPrice;
					nextOptimum.posPrev = cur;
					nextOptimum.makeAsShortRep();
					nextIsChar = true;
				}
			}

			var numAvailableBytesFull:Int = _matchFinder.getNumAvailableBytes() + 1;
			numAvailableBytesFull = Std.int(Math.min(kNumOpts - 1 - cur, numAvailableBytesFull));
			numAvailableBytes = numAvailableBytesFull;
			
			if (numAvailableBytes < 2)
				continue;
			if (numAvailableBytes > _numFastBytes)
				numAvailableBytes = _numFastBytes;
			if (!nextIsChar && matchByte != currentByte)
			{
				// try Literal + rep0
				var t:Int = Std.int(Math.min(numAvailableBytesFull - 1, _numFastBytes));
				var lenTest2:Int = _matchFinder.getMatchLen(0, reps[0], t);
				if (lenTest2 >= 2)
				{
					var state2:Int = Base.stateUpdateChar(state);

					var posStateNext:Int = (position + 1) & _posStateMask;
					var nextRepMatchPrice:Int = curAnd1Price +
						sevenZip.compression.rangeCoder.Encoder.getPrice1(_isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
						sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep[state2]);
					{
						var offset:Int = cur + 1 + lenTest2;
						while (lenEnd < offset)
							_optimum[++lenEnd].price = kIfinityPrice;
						var curAndLenPrice:Int = nextRepMatchPrice + getRepPrice(
								0, lenTest2, state2, posStateNext);
						var optimum:Optimal = _optimum[offset];
						if (curAndLenPrice < optimum.price)
						{
							optimum.price = curAndLenPrice;
							optimum.posPrev = cur + 1;
							optimum.backPrev = 0;
							optimum.prev1IsChar = true;
							optimum.prev2 = false;
						}
					}
				}
			}
				
			var startLen:Int = 2; // speed optimization 

			for (repIndex in 0...Base.kNumRepDistances)
			{
				var lenTest:Int = _matchFinder.getMatchLen(0 - 1, reps[repIndex], numAvailableBytes);
				if (lenTest < 2)
					continue;
				var lenTestTemp:Int = lenTest;
				do
				{
					while (lenEnd < cur + lenTest)
						_optimum[++lenEnd].price = kIfinityPrice;
					var curAndLenPrice:Int = repMatchPrice + getRepPrice(repIndex, lenTest, state, posState);
					var optimum:Optimal = _optimum[cur + lenTest];
					if (curAndLenPrice < optimum.price)
					{
						optimum.price = curAndLenPrice;
						optimum.posPrev = cur;
						optimum.backPrev = repIndex;
						optimum.prev1IsChar = false;
					}
					lenTest--;
				} while (--lenTest >= 2);
				lenTest = lenTestTemp;

				if (repIndex == 0)
					startLen = lenTest + 1;

				// if (_maxMode)
				if (lenTest < numAvailableBytesFull)
				{
					var t:Int = Std.int(Math.min(numAvailableBytesFull - 1 - lenTest, _numFastBytes));
					var lenTest2:Int = _matchFinder.getMatchLen(lenTest, reps[repIndex], t);
					if (lenTest2 >= 2)
					{
						var state2:Int = Base.stateUpdateRep(state);

						var posStateNext:Int = (position + lenTest) & _posStateMask;
						var curAndLenCharPrice:Int =
								repMatchPrice + getRepPrice(repIndex, lenTest, state, posState) +
								sevenZip.compression.rangeCoder.Encoder.getPrice0(_isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
								_literalEncoder.getSubCoder(position + lenTest,
										_matchFinder.getIndexByte(lenTest - 1 - 1)).getPrice(true,
										_matchFinder.getIndexByte(lenTest - 1 - (reps[repIndex] + 1)),
										_matchFinder.getIndexByte(lenTest - 1));
						state2 = Base.stateUpdateChar(state2);
						posStateNext = (position + lenTest + 1) & _posStateMask;
						var nextMatchPrice:Int = curAndLenCharPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]);
						var nextRepMatchPrice:Int = nextMatchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep[state2]);

						// for(; lenTest2 >= 2; lenTest2--)
						{
							var offset:Int = lenTest + 1 + lenTest2;
							while (lenEnd < cur + offset)
								_optimum[++lenEnd].price = kIfinityPrice;
							var curAndLenPrice2:Int = nextRepMatchPrice + getRepPrice(0, lenTest2, state2, posStateNext);
							var optimum:Optimal = _optimum[cur + offset];
							if (curAndLenPrice2 < optimum.price)
							{
								optimum.price = curAndLenPrice2;
								optimum.posPrev = cur + lenTest + 1;
								optimum.backPrev = 0;
								optimum.prev1IsChar = true;
								optimum.prev2 = true;
								optimum.posPrev2 = cur;
								optimum.backPrev2 = repIndex;
							}
						}
					}
				}
			}

			if (newLen > numAvailableBytes)
			{
				newLen = numAvailableBytes;
				var numDistancePairs:Int = 0;
				while (newLen > _matchDistances[numDistancePairs])
					numDistancePairs += 2;
				_matchDistances[numDistancePairs] = newLen;
				numDistancePairs += 2;
			}
			if (newLen >= startLen)
			{
				normalMatchPrice = matchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice0(_isRep[state]);
				while (lenEnd < cur + newLen)
					_optimum[++lenEnd].price = kIfinityPrice;

				var offs:Int = 0;
				while (startLen > _matchDistances[offs])
					offs += 2;

				var lenTest:Int = startLen;
				while (true)
				{
					var curBack:Int = _matchDistances[offs + 1];
					var curAndLenPrice:Int = normalMatchPrice + getPosLenPrice(curBack, lenTest, posState);
					var optimum:Optimal = _optimum[cur + lenTest];
					if (curAndLenPrice < optimum.price)
					{
						optimum.price = curAndLenPrice;
						optimum.posPrev = cur;
						optimum.backPrev = curBack + Base.kNumRepDistances;
						optimum.prev1IsChar = false;
					}

					if (lenTest == _matchDistances[offs])
					{
						if (lenTest < numAvailableBytesFull)
						{
							var t:Int = Std.int(Math.min(numAvailableBytesFull - 1 - lenTest, _numFastBytes));
							var lenTest2:Int = _matchFinder.getMatchLen(lenTest, curBack, t);
							if (lenTest2 >= 2)
							{
								var state2:Int = Base.stateUpdateMatch(state);

								var posStateNext:Int = (position + lenTest) & _posStateMask;
								var curAndLenCharPrice:Int = curAndLenPrice +
									sevenZip.compression.rangeCoder.Encoder.getPrice0(_isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
									_literalEncoder.getSubCoder(position + lenTest,
										_matchFinder.getIndexByte(lenTest - 1 - 1)).getPrice(true,
										_matchFinder.getIndexByte(lenTest - (curBack + 1) - 1),
										_matchFinder.getIndexByte(lenTest - 1));
								state2 = Base.stateUpdateChar(state2);
								posStateNext = (position + lenTest + 1) & _posStateMask;
								var nextMatchPrice:Int = curAndLenCharPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]);
								var nextRepMatchPrice:Int = nextMatchPrice + sevenZip.compression.rangeCoder.Encoder.getPrice1(_isRep[state2]);

								var offset:Int = lenTest + 1 + lenTest2;
								while (lenEnd < cur + offset)
									_optimum[++lenEnd].price = kIfinityPrice;
								curAndLenPrice = nextRepMatchPrice + getRepPrice(0, lenTest2, state2, posStateNext);
								optimum = _optimum[cur + offset];
								if (curAndLenPrice < optimum.price)
								{
									optimum.price = curAndLenPrice;
									optimum.posPrev = cur + lenTest + 1;
									optimum.backPrev = 0;
									optimum.prev1IsChar = true;
									optimum.prev2 = true;
									optimum.posPrev2 = cur;
									optimum.backPrev2 = curBack + Base.kNumRepDistances;
								}
							}
						}
						offs += 2;
						if (offs == numDistancePairs)
							break;
					}
					lenTest++;
				}
			}
		}
	}
	
	function changePair(smallDist:Int, bigDist:Int):Bool {
		var kDif:Int = 7;
		return (smallDist < (1 << (32 - kDif)) && bigDist >= (smallDist << kDif));
	}
	
	function writeEndMarker(posState:Int):Void {
		if (!_writeEndMark)
			return;

		_rangeEncoder.encode(_isMatch, (_state << Base.kNumPosStatesBitsMax) + posState, 1);
		_rangeEncoder.encode(_isRep, _state, 0);
		_state = Base.stateUpdateMatch(_state);
		var len:Int = Base.kMatchMinLen;
		_lenEncoder.encode(_rangeEncoder, len - Base.kMatchMinLen, posState);
		var posSlot:Int = (1 << Base.kNumPosSlotBits) - 1;
		var lenToPosState:Int = Base.getLenToPosState(len);
		_posSlotEncoder[lenToPosState].encode(_rangeEncoder, posSlot);
		var footerBits:Int = 30;
		var posReduced:Int = (1 << footerBits) - 1;
		_rangeEncoder.encodeDirectBits(posReduced >> Base.kNumAlignBits, footerBits - Base.kNumAlignBits);
		_posAlignEncoder.reverseEncodeImpl(_rangeEncoder, posReduced & Base.kAlignMask);
	}
	
	function flush(nowPos:Int):Void
	{
		releaseMFStream();
		writeEndMarker(nowPos & _posStateMask);
		_rangeEncoder.flushData();
		_rangeEncoder.flushStream();
	}

	public function codeOneBlock(inSize:Array<Int64>, outSize:Array<Int64>, finished:Array<Bool>):Void {
		inSize[0] = 0;
		outSize[0] = 0;
		finished[0] = true;

		if (_inStream != null)
		{
			_matchFinder.setStream(_inStream);
			_matchFinder.init();
			_needReleaseMFStream = true;
			_inStream = null;
		}

		if (_finished)
			return;
		_finished = true;


		var progressPosValuePrev:Int64 = nowPos64;
		if (nowPos64 == 0)
		{
			if (_matchFinder.getNumAvailableBytes() == 0)
			{
				flush(nowPos64.low);
				return;
			}

			readMatchDistances();
			var posState:Int = nowPos64.low & _posStateMask;
			_rangeEncoder.encode(_isMatch, (_state << Base.kNumPosStatesBitsMax) + posState, 0);
			_state = Base.stateUpdateChar(_state);
			var curByte:Int = _matchFinder.getIndexByte(0 - _additionalOffset);
			_literalEncoder.getSubCoder(nowPos64.low, _previousByte).encode(_rangeEncoder, curByte);
			_previousByte = curByte;
			_additionalOffset--;
			nowPos64++;
		}
		if (_matchFinder.getNumAvailableBytes() == 0)
		{
			flush(nowPos64.low);
			return;
		}
		while (true)
		{

			var len:Int = getOptimum(nowPos64.low);
			var pos:Int = backRes;
			var posState:Int = (nowPos64.low) & _posStateMask;
			var complexState:Int = (_state << Base.kNumPosStatesBitsMax) + posState;
			if (len == 1 && pos == -1)
			{
				_rangeEncoder.encode(_isMatch, complexState, 0);
				var curByte:Int = _matchFinder.getIndexByte((0 - _additionalOffset));
				var subCoder:Encoder2 = _literalEncoder.getSubCoder(nowPos64.low, _previousByte);
				if (!Base.stateIsCharState(_state))
				{
					var matchByte:Int =  _matchFinder.getIndexByte((0 - _repDistances[0] - 1 - _additionalOffset));
					subCoder.encodeMatched(_rangeEncoder, matchByte, curByte);
				}
				else
					subCoder.encode(_rangeEncoder, curByte);
				_previousByte = curByte;
				_state = Base.stateUpdateChar(_state);
			}
			else
			{
				_rangeEncoder.encode(_isMatch, complexState, 1);
				if (pos < Base.kNumRepDistances)
				{
					_rangeEncoder.encode(_isRep, _state, 1);
					if (pos == 0)
					{
						_rangeEncoder.encode(_isRepG0, _state, 0);
						if (len == 1)
							_rangeEncoder.encode(_isRep0Long, complexState, 0);
						else
							_rangeEncoder.encode(_isRep0Long, complexState, 1);
					}
					else
					{
						_rangeEncoder.encode(_isRepG0, _state, 1);
						if (pos == 1)
							_rangeEncoder.encode(_isRepG1, _state, 0);
						else
						{
							_rangeEncoder.encode(_isRepG1, _state, 1);
							_rangeEncoder.encode(_isRepG2, _state, pos - 2);
						}
					}
					if (len == 1)
						_state = Base.stateUpdateShortRep(_state);
					else
					{
						_repMatchLenEncoder.encode(_rangeEncoder, len - Base.kMatchMinLen, posState);
						_state = Base.stateUpdateRep(_state);
					}
					var distance:Int = _repDistances[pos];
					if (pos != 0)
					{							
						var i = pos;
						while (i >= 1) {
							_repDistances[i] = _repDistances[i - 1];
							i--;
						}
						_repDistances[0] = distance;
					}
				}
				else
				{
					_rangeEncoder.encode(_isRep, _state, 0);
					_state = Base.stateUpdateMatch(_state);
					_lenEncoder.encode(_rangeEncoder, len - Base.kMatchMinLen, posState);
					pos -= Base.kNumRepDistances;
					var posSlot:Int = getPosSlot(pos);
					var lenToPosState:Int = Base.getLenToPosState(len);
					_posSlotEncoder[lenToPosState].encode(_rangeEncoder, posSlot);

					if (posSlot >= Base.kStartPosModelIndex)
					{
						var footerBits:Int = ((posSlot >> 1) - 1);
						var baseVal:Int = ((2 | (posSlot & 1)) << footerBits);
						var posReduced:Int = pos - baseVal;

						if (posSlot < Base.kEndPosModelIndex)
							BitTreeEncoder.reverseEncode(_posEncoders,
									baseVal - posSlot - 1, _rangeEncoder, footerBits, posReduced);
						else
						{
							_rangeEncoder.encodeDirectBits(posReduced >> Base.kNumAlignBits, footerBits - Base.kNumAlignBits);
							_posAlignEncoder.reverseEncodeImpl(_rangeEncoder, posReduced & Base.kAlignMask);
							_alignPriceCount++;
						}
					}
					var distance:Int = pos;
					for (i in Base.kNumRepDistances - 1...1)
						_repDistances[i] = _repDistances[i - 1];
					_repDistances[0] = distance;
					_matchPriceCount++;
				}
				_previousByte = _matchFinder.getIndexByte(len - 1 - _additionalOffset);
			}
			_additionalOffset -= len;
			nowPos64 += len;
			if (_additionalOffset == 0)
			{
				// if (!_fastMode)
				if (_matchPriceCount >= (1 << 7))
					fillDistancesPrices();
				if (_alignPriceCount >= Base.kAlignTableSize)
					fillAlignPrices();
				inSize[0] = nowPos64;
				outSize[0] = _rangeEncoder.getProcessedSizeAdd();
				if (_matchFinder.getNumAvailableBytes() == 0)
				{
					flush(nowPos64.low);
					return;
				}

				if (nowPos64 - progressPosValuePrev >= (1 << 12))
				{
					_finished = false;
					finished[0] = false;
					return;
				}
			}
		}
	}

	
	function releaseMFStream():Void
	{
		if (_matchFinder != null && _needReleaseMFStream)
		{
			_matchFinder.releaseStream();
			_needReleaseMFStream = false;
		}
	}
	
	function setOutStream(outStream:Output):Void
	{ _rangeEncoder.setStream(outStream); }
	function releaseOutStream():Void
	{ _rangeEncoder.releaseStream(); }

	function releaseStreams():Void
	{
		releaseMFStream();
		releaseOutStream();
	}
	
	function setStreams(inStream:Input, outStream:Output, inSize:Int64, outSize:Int64):Void {
		_inStream = inStream;
		_finished = false;
		create();
		setOutStream(outStream);
		init();

		// if (!_fastMode)
		{
			fillDistancesPrices();
			fillAlignPrices();
		}

		_lenEncoder.setTableSize(_numFastBytes + 1 - Base.kMatchMinLen);
		_lenEncoder.updateTables(1 << _posStateBits);
		_repMatchLenEncoder.setTableSize(_numFastBytes + 1 - Base.kMatchMinLen);
		_repMatchLenEncoder.updateTables(1 << _posStateBits);

		nowPos64 = 0;
	}
	
	var processedInSize:Array<Int64> = ini64Array(1); 
	var processedOutSize:Array<Int64> = ini64Array(1); 
	var finished:Array<Bool> = boolArray(1);
	
	public function code(inStream:Input, outStream:Output, inSize:Int64, outSize:Int64, progress:ICodeProgress):Void {
		_needReleaseMFStream = false;
		var testRelStr = false;
		try
		{
			setStreams(inStream, outStream, inSize, outSize);
			while (true)
			{
				codeOneBlock(processedInSize, processedOutSize, finished);
				if (finished[0]) {
					releaseStreams();
					return;
				}
				if (progress != null)
				{
					progress.setProgress(processedInSize[0], processedOutSize[0]);
				}
			}
		} catch (e) {
			testRelStr = true;
			releaseStreams();
			trace(e.message);
		}
		releaseStreams();
	}
	
	
	public static inline var kPropSize:Int = 5;
	var properties:Bytes = Bytes.alloc(kPropSize);

	public function writeCoderProperties(outStream:Output):Void {
		properties.set(0, ((_posStateBits * 5 + _numLiteralPosStateBits) * 9 + _numLiteralContextBits));
		for (i in 0...4) {
			properties.set(1 + i, (_dictionarySize >> (8 * i)));
		}
		outStream.writeBytes(properties, 0, kPropSize);
	}


	var tempPrices:Array<Int> = iniArray(Base.kNumFullDistances);
	var _matchPriceCount:Int;
	
	function fillDistancesPrices():Void {
		for (i in Base.kStartPosModelIndex...Base.kNumFullDistances)
		{
			var posSlot:Int = getPosSlot(i);
			var footerBits:Int = ((posSlot >> 1) - 1);
			var baseVal:Int = ((2 | (posSlot & 1)) << footerBits);
			tempPrices[i] = BitTreeEncoder.reverseGetPrice(_posEncoders,
				baseVal - posSlot - 1, footerBits, i - baseVal);
		}

		for (lenToPosState in 0...Base.kNumLenToPosStates)
		{
			var posSlot:Int = 0;
			var encoder:BitTreeEncoder = _posSlotEncoder[lenToPosState];

			var st:Int = (lenToPosState << Base.kNumPosSlotBits);
			while (posSlot < _distTableSize) {
				_posSlotPrices[st + posSlot] = encoder.getPrice(posSlot);
				_posSlotPrices[st + posSlot] += 384;
				posSlot++;
			}
			posSlot = Base.kEndPosModelIndex;
			while (posSlot < _distTableSize)  {
				_posSlotPrices[st + posSlot] += ((((posSlot >> 1) - 1) - Base.kNumAlignBits) << sevenZip.compression.rangeCoder.Encoder.kNumBitPriceShiftBits);
				posSlot++;
			}
			var st2:Int = lenToPosState * Base.kNumFullDistances;
			var i:Int = 0;
			while (i < Base.kStartPosModelIndex) {
				_distancesPrices[st2 + i] = _posSlotPrices[st + i];
				i++;
			}
			while (i < Base.kNumFullDistances) {
				_distancesPrices[st2 + i] = _posSlotPrices[st + getPosSlot(i)] + tempPrices[i];
				_distancesPrices[st2 + i] += st2;
				//trace(st);
				i++;
			}
		}
		_matchPriceCount = 0;
	}

	function fillAlignPrices():Void {
		for (i in 0...Base.kAlignTableSize)
			_alignPrices[i] = _posAlignEncoder.reverseGetPriceImpl(i);
		_alignPriceCount = 0;
	}
	
	public function setAlgorithm(algorithm:Int):Bool {
		/*
		_fastMode = (algorithm == 0);
		_maxMode = (algorithm >= 2);
		*/
		return true;
	}
	
	public function setDictionarySize(dictionarySize:Int):Bool {
		var kDicLogSizeMaxCompress:Int = 29;
		if (dictionarySize < (1 << Base.kDicLogSizeMin) || dictionarySize > (1 << kDicLogSizeMaxCompress))
			return false;
		_dictionarySize = dictionarySize;
		var dicLogSize:Int = 0;
		while (dictionarySize > (1 << dicLogSize)) 
			dicLogSize++;
		_distTableSize = dicLogSize * 2;
		return true;
	}

	public function setNumFastBytes(numFastBytes:Int):Bool {
		if (numFastBytes < 5 || numFastBytes > Base.kMatchMaxLen) return false;
		_numFastBytes = numFastBytes;
		return true;
	}

	public function setMatchFinder(matchFinderIndex:Int):Bool {
		if (matchFinderIndex < 0 || matchFinderIndex > 2) return false;
		var matchFinderIndexPrev:Int = _matchFinderType;
		_matchFinderType = matchFinderIndex;
		if (_matchFinder != null && matchFinderIndexPrev != _matchFinderType) {
			_dictionarySizePrev = -1;
			_matchFinder = null;
		}
		return true;
	}

	public function setLcLpPb(lc:Int, lp:Int, pb:Int):Bool {
		if (lp < 0 || lp > Base.kNumLitPosStatesBitsEncodingMax ||
			lc < 0 || lc > Base.kNumLitContextBitsMax ||
			pb < 0 || pb > Base.kNumPosStatesBitsEncodingMax) return false;
		_numLiteralPosStateBits = lp;
		_numLiteralContextBits = lc;
		_posStateBits = pb;
		_posStateMask = (1 << _posStateBits) - 1;
		return true;
	}

	public function setEndMarkerMode(endMarkerMode:Bool):Void {
		_writeEndMark = endMarkerMode;
	}
}

class LiteralEncoder {
    var m_Coders:Array<Encoder2>;
    var m_NumPrevBits:Int;
    var m_NumPosBits:Int;
    var m_PosMask:Int;

    public function new() {}

    public function create(numPosBits:Int, numPrevBits:Int):Void {
        if (m_Coders != null && m_NumPrevBits == numPrevBits && m_NumPosBits == numPosBits)
            return;
        m_NumPosBits = numPosBits;
        m_PosMask = (1 << numPosBits) - 1;
        m_NumPrevBits = numPrevBits;
        var numStates = 1 << (m_NumPrevBits + m_NumPosBits);
        m_Coders = new Array<Encoder2>();
        for (i in 0...numStates)
            m_Coders[i] = new Encoder2();
    }

    public function init():Void {
        var numStates = 1 << (m_NumPrevBits + m_NumPosBits);
        for (i in 0...numStates)
            m_Coders[i].init();
    }

    public function getSubCoder(pos:Int, prevByte:Int):Encoder2 {
        return m_Coders[((pos & m_PosMask) << m_NumPrevBits) + ((prevByte & 0xFF) >>> (8 - m_NumPrevBits))];
    }
}

class Encoder2 {
    var m_Encoders:Array<Int> = initM_Encoders();
	private static function initM_Encoders():Array<Int> {
		var table:Array<Int> = new Array<Int>();
		for (i in 0...0x300) table.push(0);
		return table;
	}


    public function new() {}

    public function init():Void {
        sevenZip.compression.rangeCoder.Encoder.initBitModels(m_Encoders);
    }

    public function encode(rangeEncoder:sevenZip.compression.rangeCoder.Encoder, symbol:Int):Void {
        var context = 1;
        var i = 7;
        while (i >= 0) {
            var bit = (symbol >> i) & 1;
            rangeEncoder.encode(m_Encoders, context, bit);
            context = (context << 1) | bit;
			i--;
        }
    }

    public function encodeMatched(rangeEncoder:sevenZip.compression.rangeCoder.Encoder, matchByte:Int, symbol:Int):Void {
        var context = 1;
        var same = true;
        var i = 7;
        while (i >= 0) {
            var bit = (symbol >> i) & 1;
            var state = context;
            if (same) {
                var matchBit = (matchByte >> i) & 1;
                state += ((1 + matchBit) << 8);
                same = (matchBit == bit);
            }
            rangeEncoder.encode(m_Encoders, state, bit);
            context = (context << 1) | bit;
			i--;
        }
    }

    public function getPrice(matchMode:Bool, matchByte:Int, symbol:Int):Int {
        var price = 0;
        var context = 1;
        var i = 7;
        if (matchMode) {
            while (i >= 0) {
                var matchBit = (matchByte >> i) & 1;
                var bit = (symbol >> i) & 1;
                price += sevenZip.compression.rangeCoder.Encoder.getPrice(m_Encoders[((1 + matchBit) << 8) + context], bit);
                context = (context << 1) | bit;
                if (matchBit != bit) {
                    i--;
                    break;
                }
                i--;
            }
        }
        while (i >= 0) {
            var bit = (symbol >> i) & 1;
            price += sevenZip.compression.rangeCoder.Encoder.getPrice(m_Encoders[context], bit);
            context = (context << 1) | bit;
            i--;
        }
        return price;
    }
}

class LenEncoder {
	var _choice:Array<Int> = ini_choice();
	private static function ini_choice():Array<Int> {
		var table:Array<Int> = new Array<Int>();
		for (i in 0...2) table.push(0);
		return table;
	}
	var _lowCoder:Array<BitTreeEncoder> = ini_lowCoder();
	private static function ini_lowCoder():Array<BitTreeEncoder> {
		var table:Array<BitTreeEncoder> = new Array<BitTreeEncoder>();
		for (i in 0...Base.kNumPosStatesEncodingMax) table.push(new BitTreeEncoder(Base.kNumLowLenBits));
		return table;
	}
	var _midCoder:Array<BitTreeEncoder> = ini_midCoder();
	private static function ini_midCoder():Array<BitTreeEncoder> {
		var table:Array<BitTreeEncoder> = new Array<BitTreeEncoder>();
		for (i in 0...Base.kNumPosStatesEncodingMax) table.push(new BitTreeEncoder(Base.kNumMidLenBits));
		return table;
	}
	var _highCoder:Dynamic = new BitTreeEncoder(Base.kNumHighLenBits);
	private static function ini_highCoder():Array<Int> {
		var table:Array<Int> = new Array<Int>();
		for (i in 0...Base.kNumHighLenBits) table.push(0);
		return table;
	}


	public function new()
	{
		for (posState in 0...Base.kNumPosStatesEncodingMax)
		{
			_lowCoder[posState] = new BitTreeEncoder(Base.kNumLowLenBits);
			_midCoder[posState] = new BitTreeEncoder(Base.kNumMidLenBits);
		}
	}

	public function init(numPosStates:Int):Void
	{
		sevenZip.compression.rangeCoder.Encoder.initBitModels(_choice);

		for (posState in 0...numPosStates)
		{
			_lowCoder[posState].init();
			_midCoder[posState].init();
		}
		_highCoder.init();
	}

	public function encode(rangeEncoder:sevenZip.compression.rangeCoder.Encoder, symbol:Int, posState:Int)
	{
		if (symbol < Base.kNumLowLenSymbols)
		{
			rangeEncoder.encode(_choice, 0, 0);
			_lowCoder[posState].encode(rangeEncoder, symbol);
		}
		else
		{
			symbol -= Base.kNumLowLenSymbols;
			rangeEncoder.encode(_choice, 0, 1);
			if (symbol < Base.kNumMidLenSymbols)
			{
				rangeEncoder.encode(_choice, 1, 0);
				_midCoder[posState].encode(rangeEncoder, symbol);
			}
			else
			{
				rangeEncoder.encode(_choice, 1, 1);
				_highCoder.encode(rangeEncoder, symbol - Base.kNumMidLenSymbols);
			}
		}
	}

	public function setPrices(posState:Int, numSymbols:Int, prices:Array<Int>, st:Int):Void {
		var a0:Int = sevenZip.compression.rangeCoder.Encoder.getPrice0(_choice[0]);
		var a1:Int = sevenZip.compression.rangeCoder.Encoder.getPrice1(_choice[0]);
		var b0:Int = a1 + sevenZip.compression.rangeCoder.Encoder.getPrice0(_choice[1]);
		var b1:Int = a1 + sevenZip.compression.rangeCoder.Encoder.getPrice1(_choice[1]);
		
		var i = 0;
		
		while (i < Base.kNumLowLenSymbols) {
			if (i >= numSymbols)
				return;
			prices[st + i] = a0 + _lowCoder[posState].getPrice(i);
			i++;
		}
		
		while (i < Base.kNumLowLenSymbols + Base.kNumMidLenSymbols) {
			if (i >= numSymbols)
				return;
			prices[st + i] = b0 + _midCoder[posState].getPrice(i - Base.kNumLowLenSymbols);
			i++;
		}
		
		while (i < numSymbols) {
			prices[st + i] = b1 + _highCoder.getPrice(i - Base.kNumLowLenSymbols - Base.kNumMidLenSymbols);
			i++;
		}
	}
}

class LenPriceTableEncoder extends LenEncoder {
    var _prices:Array<Int> = iniArray(Base.kNumLenSymbols << Base.kNumPosStatesBitsEncodingMax);
    var _tableSize:Int;
    var _counters:Array<Int> = iniArray(Base.kNumPosStatesEncodingMax);
    
    public function new() {
        super();
    }

    public function setTableSize(tableSize:Int):Void _tableSize = tableSize;

    public function getPrice(symbol:Int, posState:Int):Int return _prices[posState * Base.kNumLenSymbols + symbol];

    function updateTable(posState:Int):Void {
        setPrices(posState, _tableSize, _prices, posState * Base.kNumLenSymbols);
        _counters[posState] = _tableSize;
    }

    public function updateTables(numPosStates:Int):Void {
        for (posState in 0...numPosStates) {
            updateTable(posState);
        }
    }

    override public function encode(rangeEncoder:sevenZip.compression.rangeCoder.Encoder, symbol:Int, posState:Int):Void {
        super.encode(rangeEncoder, symbol, posState);
        if (--_counters[posState] == 0) {
            updateTable(posState);
        }
    }

    private static function iniArray(length:Int):Array<Int> {
        var arr:Array<Int> = new Array<Int>();
        for (i in 0...length) {
            arr.push(0);
        }
        return arr;
    }
}

class Optimal {
    public var state:Int;
	
    public var prev1IsChar:Bool;
    public var prev2:Bool;
	
    public var posPrev2:Int;
    public var backPrev2:Int;
	
    public var price:Int;
    public var posPrev:Int;
    public var backPrev:Int;
	
    public var backs0:Int;
    public var backs1:Int;
    public var backs2:Int;
    public var backs3:Int;

    public function new() {}

    public function makeAsChar():Void {
        backPrev = -1;
        prev1IsChar = false;
    }

    public function makeAsShortRep():Void {
        backPrev = 0;
        prev1IsChar = false;
    }

    public function isShortRep():Bool {
        return backPrev == 0;
    }
}

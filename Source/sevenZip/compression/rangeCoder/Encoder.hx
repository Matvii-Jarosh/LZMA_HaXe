package sevenZip.compression.rangeCoder;

import haxe.Int64;

class Encoder {
	public function new() {}
	
    public static inline var kTopMask:Int = ~((1 << 24) - 1);

    public static inline var kNumBitModelTotalBits:Int = 11;
    public static inline var kBitModelTotal:Int = 1 << kNumBitModelTotalBits;
    public static inline var kNumMoveBits:Int = 5;

    public var stream:haxe.io.Output;

    public var _low:Int64;
    public var range:Int;
    public var _cacheSize:Int;
    public var _cache:Int;

    public var _position:Int64;

    public function setStream(_stream:haxe.io.Output) stream = _stream;
    
    public function releaseStream() stream = null;

    public function init() {
        _position = 0;
        _low = 0;
        range = -1;
        _cacheSize = 1;
        _cache = 0;
    }

    public function flushData() for (i in 0...5) shiftLow();
    
    public function flushStream() stream.flush();
 
    public function shiftLow() {
		var test:Int64 = _low;
		var lowHi:Int = cast (_low >>> 32);
		if (test.low < 4278190080 || lowHi != 0) {
			_position += _cacheSize;
			var temp:Int = _cache;
			while (true) {
				stream.writeByte(temp + lowHi);
				temp = 0xFF;
				if (--_cacheSize == 0) break;
			}
			_cache = (test.low >>> 24);
		}
		_cacheSize++;
		var newLow:Int64 = (_low & 0xFFFFFF);
		_low = (newLow << 8);
		//trace(_low);
	}


    public function encodeDirectBits(v:Int, numTotalBits:Int) {
        for (i in (numTotalBits - 1)...0) {
            range >>>= 1;
            if (((v >>> i) & 1) == 1) _low += range;
            if ((range & kTopMask) == 0) {
                range <<= 8;
                shiftLow();
            }
        }
    }

    public function getProcessedSizeAdd():Int64 return _cacheSize + _position + 4;
 
    public static inline var kNumMoveReducingBits:Int = 2;
    public static inline var kNumBitPriceShiftBits:Int = 6;

    public static function initBitModels(probs:Array<Int>) for (i in 0...probs.length) probs[i] = kBitModelTotal >>> 1;
    
	public var _ind = 0;
    public function encode(probs:Array<Int>, index:Int, symbol:Int) {
        var prob:Int = probs[index];
        var newBound:Int = (range >>> kNumBitModelTotalBits) * prob;
        if (symbol == 0) {
            range = newBound;
            probs[index] = (prob + ((kBitModelTotal - prob) >>> kNumMoveBits));
        } else {
            _low += newBound & 0xFFFFFFFF;
			//trace(_low);
            range -= newBound;
            probs[index] = (prob - (prob >>> kNumMoveBits));
        }
        if ((range & kTopMask) == 0) {
            range <<= 8;
            shiftLow();
        }
		_ind++;
    };

    private static var ProbPrices:Array<Int> = {
		var table:Array<Int> = [];
		var kNumBits:Int = kNumBitModelTotalBits - kNumMoveReducingBits;
		for (i in 0...(kBitModelTotal >>> kNumMoveReducingBits)) {
			table.push(0);
		}
		var i:Int = kNumBits - 1;
		while (i >= 0) {
			var start:Int = 1 << (kNumBits - i - 1);
			var end:Int = 1 << (kNumBits - i);
			var j:Int = start;
			while (j < end) {
				table[j] = (i << kNumBitPriceShiftBits) +
					(((end - j) << kNumBitPriceShiftBits) >>> (kNumBits - i - 1));
				j++;
			}
			i--;
		}
		table;
	};

    public static function getPrice(Prob:Int, symbol:Int):Int return ProbPrices[(((Prob - symbol) ^ ((-symbol))) & (kBitModelTotal - 1)) >>> kNumMoveReducingBits];
    
    public static function getPrice0(Prob:Int):Int return ProbPrices[Prob >>> kNumMoveReducingBits];
    
    public static function getPrice1(Prob:Int):Int return ProbPrices[(kBitModelTotal - Prob) >>> kNumMoveReducingBits];
}
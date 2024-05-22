package sevenZip.compression.rangeCoder;

class Decoder {
    public static inline var kTopMask:Int = ~((1 << 24) - 1);

    public static inline var kNumBitModelTotalBits:Int = 11;
    public static inline var kBitModelTotal:Int = 1 << kNumBitModelTotalBits;
    public static inline var kNumMoveBits:Int = 5;

    public var range:Int;
    public var code:Int;

    public var stream:haxe.io.Input;

    public function setStream(_stream:haxe.io.Input):Void stream = _stream;
    
    public function releaseStream():Void stream = null;
    
	public function new() {}

    public function init():Void {
        code = 0;
        range = -1;
        for (i in 0...5) {
			var byte:Int = -1;
			try {
				byte = stream.readByte();
			} catch(e) {
				byte = -1;
			}
            code = ((code << 8) | byte);
        }
    }
    
    public function decodeDirectBits(numTotalBits:Int):Int {
        var result:Int = 0;
        for (i in 0...numTotalBits) {
            range >>>= 1;
            var t:Int = ((code - range) >>> 31);
            code -= range & (t - 1);
            result = (result << 1) | (1 - t);
            if ((range & kTopMask) == 0) {
                var byte:Int = -1;
				try {
					byte = stream.readByte();
				} catch(e) {
					byte = -1;
				}
				code = ((code << 8) | byte);
                range <<= 8;
            }
        }
        return result;
    }
    
    public function decodeBit(probs:Array<Int>, index:Int):Int {
        var prob:Int = probs[index];
        var newBound:Int = (range >>> kNumBitModelTotalBits) * prob;
        if ((code ^ 0x80000000) < (newBound ^ 0x80000000)) {
            range = newBound;
            probs[index] = (prob + ((kBitModelTotal - prob) >>> kNumMoveBits));
            if ((range & kTopMask) == 0) {
                 var byte:Int = -1;
				try {
					byte = stream.readByte();
				} catch(e) {
					byte = -1;
				}
				code = ((code << 8) | byte);
                range <<= 8;
            }
            return 0;
        } else {
            range -= newBound;
            code -= newBound;
            probs[index] = (prob - ((prob) >>> kNumMoveBits));
            if ((range & kTopMask) == 0) {
				var byte:Int = -1; 
                try {
					byte = stream.readByte();
				} catch(e) {
					byte = -1;
				}
				code = ((code << 8) | byte);
                range <<= 8;
            }
            return 1;
        }
    }
    
    public static function initBitModels(probs:Array<Int>):Void for (i in 0...probs.length) probs[i] = (kBitModelTotal >>> 1);
}

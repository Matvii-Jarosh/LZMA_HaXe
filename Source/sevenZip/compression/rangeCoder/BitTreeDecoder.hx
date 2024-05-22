package sevenZip.compression.rangeCoder;

class BitTreeDecoder {
    public var models:Array<Int>;
    public var numBitLevels:Int;
    
    public function new(numBitLevels:Int) {
        this.numBitLevels = numBitLevels;
        models = new Array<Int>();
		for (i in 0...(1 << numBitLevels)) models.push(0);
    }
    
    public function init():Void {
        Decoder.initBitModels(models);
    }
    
    public function decode(rangeDecoder:Decoder):Int {
        var m:Int = 1;
        for (bitIndex in 0...numBitLevels) {
            m = (m << 1) + rangeDecoder.decodeBit(models, m);
        }
        return m - (1 << numBitLevels);
    }
    
    public function reverseDecode(rangeDecoder:Decoder):Int {
        var m:Int = 1;
        var symbol:Int = 0;
        for (bitIndex in 0...numBitLevels) {
            var bit:Int = rangeDecoder.decodeBit(models, m);
            m <<= 1;
            m += bit;
            symbol |= (bit << bitIndex);
        }
        return symbol;
    }
    
    public static function _reverseDecode(_models:Array<Int>, startIndex:Int, rangeDecoder:Decoder, _numBitLevels:Int):Int {
        var m:Int = 1;
        var symbol:Int = 0;
        for (bitIndex in 0..._numBitLevels) {
            var bit:Int = rangeDecoder.decodeBit(_models, startIndex + m);
            m <<= 1;
            m += bit;
            symbol |= (bit << bitIndex);
        }
        return symbol;
    }
}

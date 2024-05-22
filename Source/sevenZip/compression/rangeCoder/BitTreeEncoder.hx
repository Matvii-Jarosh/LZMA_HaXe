package sevenZip.compression.rangeCoder;

class BitTreeEncoder {
    public var models:Array<Int>;
    public var numBitLevels:Int;
    
    public function new(_numBitLevels:Int) {
        numBitLevels = _numBitLevels;
        models = new Array<Int>();
        for (i in 0...(1 << _numBitLevels)) models.push(0);
    }
    
    public function init():Void {
        Decoder.initBitModels(models);
    }
    
    public function encode(rangeEncoder:Encoder, symbol:Int):Void {
        var m:Int = 1;
		var bitIndex:Int = numBitLevels;
		while (bitIndex != 0) {
			bitIndex--;
			var bit:Int = (symbol >>> bitIndex) & 1;
			rangeEncoder.encode(models, m, bit);
			m = (m << 1) | bit;
		}
    }
    
    public function reverseEncodeImpl(rangeEncoder:Encoder, symbol:Int):Void {
        var m:Int = 1;
        for (i in 0...numBitLevels) {
            var bit:Int = symbol & 1;
            rangeEncoder.encode(models, m, bit);
            m = (m << 1) | bit;
            symbol >>= 1;
        }
    }
    
    public function getPrice(symbol:Int):Int {
        var price:Int = 0;
		var m:Int = 1;
		var bitIndex:Int = numBitLevels;
		while (bitIndex != 0) {
			bitIndex--;
			var bit:Int = (symbol >>> bitIndex) & 1;
			price += Encoder.getPrice(models[m], bit);
			m = (m << 1) | bit;
		}
        return price;
    }
    
    public function reverseGetPriceImpl(symbol:Int):Int {
        var price:Int = 0;
        var m:Int = 1;
		var i = numBitLevels;
        while (i != 0) {
            var bit:Int = symbol & 1;
            symbol >>>= 1;
            price += Encoder.getPrice(models[m], bit);
            m = (m << 1) | bit;
			i--;
        }
        return price;
    }
    
	public static function reverseGetPrice(models:Array<Int>, startIndex:Int, numBitLevels:Int, symbol:Int):Int {
        var price:Int = 0;
        var m:Int = 1;
        var i = numBitLevels;
        while (i != 0) {
            var bit:Int = symbol & 1;
            symbol >>>= 1;
            price += Encoder.getPrice(models[startIndex + m], bit);
            m = (m << 1) | bit;
			i--;
        }
        return price;
    }
	
    public static function reverseEncode(models:Array<Int>, startIndex:Int, rangeEncoder:Encoder, numBitLevels:Int, symbol:Int):Void {
        var m:Int = 1;
        for (i in 0...numBitLevels) {
            var bit:Int = symbol & 1;
            rangeEncoder.encode(models, startIndex + m, bit);
            m = (m << 1) | bit;
            symbol >>= 1;
        }
    }
}

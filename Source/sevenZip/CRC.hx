package sevenZip;

class CRC {
    public static var Table:Array<Int> = initTable();
	
	static function initTable():Array<Int> {
		var table = [];
        for (i in 0...256) {
            var r = i;
            for (j in 0...8) {
                if ((r & 1) != 0)
                    r = (r >>> 1) ^ 0xEDB88320;
                else
                    r >>>= 1;
            }
            table.push(r);
        }
	}

    var _value:Int = -1;

    public function new() {}

    public function init():Void {
        _value = -1;
    }

    public function update(data:haxe.io.Bytes, offset:Int, size:Int):Void {
        for (i in 0...size)
            _value = Table[(_value ^ data.get(offset + i)) & 0xFF] ^ (_value >>> 8);
    }

    public function updateBytes(data:haxe.io.Bytes):Void {
        var size = data.length;
        for (i in 0...size)
            _value = Table[(_value ^ data.get(i)) & 0xFF] ^ (_value >>> 8);
    }

    public function updateByte(b:Int):Void {
        _value = Table[(_value ^ b) & 0xFF] ^ (_value >>> 8);
    }

    public function getDigest():Int {
        return _value ^ -1;
    }
}
